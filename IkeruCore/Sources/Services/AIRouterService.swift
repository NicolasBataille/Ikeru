import Foundation
import Observation
import os

// MARK: - AIRouterService

/// Routes AI requests to the appropriate provider tier with automatic fallback.
///
/// Tier selection (per `PromptComplexity`):
/// - Offline: always FoundationModels
/// - `.simple` (low latency wins): onDevice -> Cerebras -> Groq -> onDevice
/// - `.medium` (balance): Cerebras -> Groq -> OpenRouter -> Gemini -> onDevice
/// - `.complex` (quality wins): OpenRouter -> Gemini -> Cerebras -> Groq -> onDevice
/// - `.batch` (large volume, latency irrelevant): Gemini -> OpenRouter -> Cerebras -> onDevice
///
/// Claude is excluded from the default chain because Anthropic closed third-party
/// subscription auth (2026-04-04). Users may still configure a paid Claude API key
/// from Settings; when present, Claude is appended ahead of OpenRouter for complex
/// prompts. localGPU is reserved for the future ikeru-rig bridge (Stories 7.3-7.5).
///
/// On provider failure, falls back to the next available tier within a 2-second budget.
@Observable
@MainActor
public final class AIRouterService {

    // MARK: - Properties

    @ObservationIgnored
    private let providers: [AITier: any AIProvider]
    @ObservationIgnored
    private let networkChecker: any NetworkChecker

    /// Current status of each tier. Updated after each generation attempt.
    public private(set) var tierStatuses: [AITier: ProviderStatus]

    /// Total fallback budget in seconds. Generous enough that Gemini and
    /// OpenRouter cold-starts (which routinely take 1–3s) don't time out before
    /// returning a response.
    private static let fallbackBudgetSeconds: Double = 10.0

    // MARK: - Initialization

    /// Designated initializer accepting an explicit dictionary of providers.
    /// Use this for tests with mocked providers.
    public init(
        providers: [AITier: any AIProvider],
        networkChecker: any NetworkChecker = NWPathNetworkChecker()
    ) {
        self.providers = providers
        self.networkChecker = networkChecker
        self.tierStatuses = Dictionary(uniqueKeysWithValues: AITier.allCases.map {
            ($0, providers[$0] != nil ? ProviderStatus.unavailable : ProviderStatus.unavailable)
        })
        self.tierStatuses[.onDevice] = .available
    }

    /// Convenience initializer that wires up all default providers (FoundationModels +
    /// Gemini + Cerebras + Groq + OpenRouter + GitHub Models + Claude + LocalGPU).
    /// Each provider self-checks key availability via Keychain at request time.
    public convenience init(networkChecker: any NetworkChecker = NWPathNetworkChecker()) {
        self.init(
            providers: [
                .onDevice: FoundationModelsProvider(),
                .gemini: GeminiProvider(),
                .cerebras: CerebrasProvider(),
                .groq: GroqProvider(),
                .openRouter: OpenRouterProvider(),
                .githubModels: GitHubModelsProvider(),
                .claude: ClaudeProvider(),
                .localGPU: LocalGPUProvider(),
            ],
            networkChecker: networkChecker
        )
    }

    /// Backwards-compatible positional initializer kept so the existing test suite
    /// (which injects `onDeviceProvider`, `geminiProvider`, `claudeProvider`,
    /// `localGPUProvider`) keeps compiling. New cloud providers (Cerebras, Groq,
    /// OpenRouter, GitHub Models) default to a stub that is always unavailable
    /// when called via this initializer — tests that need them should use the
    /// designated `init(providers:networkChecker:)`.
    public convenience init(
        onDeviceProvider: any AIProvider,
        geminiProvider: any AIProvider,
        claudeProvider: any AIProvider,
        localGPUProvider: any AIProvider,
        networkChecker: any NetworkChecker = NWPathNetworkChecker()
    ) {
        self.init(
            providers: [
                .onDevice: onDeviceProvider,
                .gemini: geminiProvider,
                .claude: claudeProvider,
                .localGPU: localGPUProvider,
            ],
            networkChecker: networkChecker
        )
    }

    // MARK: - Public API

    /// Generate a response using the appropriate AI tier.
    /// Automatically falls back to lower tiers on failure.
    /// - Parameter prompt: The structured AI prompt.
    /// - Returns: The AI response from whichever tier successfully served it.
    /// - Throws: AIError if all providers are exhausted.
    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let chain = buildFallbackChain(for: prompt.complexity)

        let tierNames = chain.map { $0.name }.joined(separator: " -> ")
        Logger.ai.info("AI request: complexity=\(String(describing: prompt.complexity)), chain=\(tierNames)")

        let deadline = ContinuousClock.now + .seconds(Self.fallbackBudgetSeconds)

        for (index, provider) in chain.enumerated() {
            let isLastProvider = index == chain.count - 1
            let isOnDevice = provider.tier == .onDevice

            // Check availability before attempting
            let available = await provider.isAvailable
            guard available else {
                Logger.ai.info("Skipping \(provider.name): unavailable")
                updateTierStatus(provider.tier, status: .unavailable)
                continue
            }

            do {
                let response: AIResponse
                if isOnDevice {
                    // FoundationModels (final fallback) has no timeout -- on-device, always fast
                    response = try await provider.generate(prompt: prompt)
                } else {
                    // Give the current provider the FULL remaining budget instead of
                    // dividing it across remaining providers. With 5-6 providers in the
                    // chain, the per-provider slice was 300-400ms, way below a real
                    // Gemini/OpenRouter cold start (1-3s), causing systematic timeouts
                    // even with valid keys.
                    let remaining = deadline - ContinuousClock.now

                    response = try await withTimeout(duration: remaining, tier: provider.tier) {
                        try await provider.generate(prompt: prompt)
                    }
                }

                updateTierStatus(provider.tier, status: .available)
                Logger.ai.info("AI response served by \(provider.name) in \(response.latencyMs)ms")
                return response
            } catch {
                let tierError = error as? AIError
                Logger.ai.warning("Provider \(provider.name) failed: \(error.localizedDescription)")

                if tierError != nil {
                    updateTierStatus(provider.tier, status: .degraded)
                } else {
                    updateTierStatus(provider.tier, status: .unavailable)
                }

                // If this was the last provider, throw
                if isLastProvider {
                    Logger.ai.error("All providers exhausted for this request")
                    throw AIError.allProvidersExhausted
                }

                // Check if we still have budget
                if ContinuousClock.now >= deadline && !isOnDevice {
                    Logger.ai.warning("Fallback budget exhausted, falling back to on-device")
                    // Skip remaining network providers — try on-device as last resort
                    if let onDeviceIndex = chain.firstIndex(where: { $0.tier == .onDevice }) {
                        let onDeviceAvailable = await chain[onDeviceIndex].isAvailable
                        if onDeviceAvailable {
                            do {
                                let fallbackResponse = try await chain[onDeviceIndex].generate(prompt: prompt)
                                updateTierStatus(.onDevice, status: .available)
                                return fallbackResponse
                            } catch {
                                throw AIError.allProvidersExhausted
                            }
                        }
                    }
                    throw AIError.allProvidersExhausted
                }
            }
        }

        throw AIError.allProvidersExhausted
    }

    /// Refresh the status of all tiers.
    public func refreshTierStatuses() async {
        for tier in AITier.allCases {
            guard let provider = providers[tier] else {
                updateTierStatus(tier, status: .unavailable)
                continue
            }
            let available = await provider.isAvailable
            updateTierStatus(tier, status: available ? .available : .unavailable)
        }
    }

    // MARK: - Tier Selection

    /// Resolve a tier order to concrete providers, dropping any that aren't installed.
    /// On-device is always appended last as the final fallback.
    private func resolve(_ order: [AITier]) -> [any AIProvider] {
        var resolved = order.compactMap { providers[$0] }
        if !order.contains(.onDevice), let onDevice = providers[.onDevice] {
            resolved.append(onDevice)
        }
        return resolved
    }

    /// Build the fallback chain based on complexity and network state.
    /// The chain starts with the ideal provider and ends with FoundationModels.
    private func buildFallbackChain(for complexity: PromptComplexity) -> [any AIProvider] {
        // Offline: only on-device
        guard networkChecker.isOnline else {
            return providers[.onDevice].map { [$0] } ?? []
        }

        switch complexity {
        case .simple:
            // Latency wins. Prefer on-device, then sub-second Cerebras/Groq.
            return resolve([.onDevice, .cerebras, .groq])

        case .medium:
            // Balance latency and quality. Cerebras first, broaden out before falling back.
            return resolve([.cerebras, .groq, .openRouter, .gemini, .githubModels])

        case .complex:
            // Quality wins. OpenRouter (Llama 70B free) and Gemini Pro-class first.
            // Claude is inserted ahead only if a paid key is configured (handled at runtime
            // by isAvailable; the chain itself just lists it).
            return resolve([.openRouter, .gemini, .cerebras, .groq, .githubModels, .claude])

        case .batch:
            // Volume jobs (build-time content gen). Free tiers with high daily quotas first.
            return resolve([.gemini, .openRouter, .cerebras, .githubModels])
        }
    }

    // MARK: - Status Tracking

    private func updateTierStatus(_ tier: AITier, status: ProviderStatus) {
        tierStatuses[tier] = status
    }

    // MARK: - Timeout Helper

    /// Execute an async operation with a timeout.
    private func withTimeout<T: Sendable>(
        duration: Duration,
        tier: AITier,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // If duration is zero or negative, still attempt the operation
        // but with minimal timeout
        let effectiveDuration = max(duration, .milliseconds(50))

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: effectiveDuration)
                throw AIError.timeout(tier)
            }

            guard let result = try await group.next() else {
                throw AIError.allProvidersExhausted
            }

            group.cancelAll()
            return result
        }
    }
}
