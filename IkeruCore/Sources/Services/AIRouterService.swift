import Foundation
import Observation
import os

// MARK: - AIRouterService

/// Routes AI requests to the appropriate provider tier with automatic fallback.
///
/// Tier selection:
/// - Offline: always FoundationModels
/// - Online simple: FoundationModels (lowest latency)
/// - Online medium: Gemini free tier
/// - Online complex: Claude subscription
/// - Online batch: LocalGPU (if discovered)
///
/// On provider failure, falls back to the next available tier within a 2-second budget.
@Observable
@MainActor
public final class AIRouterService {

    // MARK: - Properties

    @ObservationIgnored
    private let onDeviceProvider: any AIProvider
    @ObservationIgnored
    private let geminiProvider: any AIProvider
    @ObservationIgnored
    private let claudeProvider: any AIProvider
    @ObservationIgnored
    private let localGPUProvider: any AIProvider
    @ObservationIgnored
    private let networkChecker: any NetworkChecker

    /// Current status of each tier. Updated after each generation attempt.
    public private(set) var tierStatuses: [AITier: ProviderStatus] = [
        .onDevice: .available,
        .gemini: .unavailable,
        .claude: .unavailable,
        .localGPU: .unavailable,
    ]

    /// Total fallback budget in seconds.
    private static let fallbackBudgetSeconds: Double = 2.0

    // MARK: - Initialization

    public init(
        onDeviceProvider: any AIProvider = FoundationModelsProvider(),
        geminiProvider: any AIProvider = GeminiProvider(),
        claudeProvider: any AIProvider = ClaudeProvider(),
        localGPUProvider: any AIProvider = LocalGPUProvider(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker()
    ) {
        self.onDeviceProvider = onDeviceProvider
        self.geminiProvider = geminiProvider
        self.claudeProvider = claudeProvider
        self.localGPUProvider = localGPUProvider
        self.networkChecker = networkChecker
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
                    // Apply deadline-aware timeout
                    let remaining = deadline - ContinuousClock.now
                    let remainingProviders = chain.count - index
                    let perProviderBudget = remaining / remainingProviders

                    response = try await withTimeout(duration: perProviderBudget, tier: provider.tier) {
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
        let providers: [(any AIProvider, AITier)] = [
            (onDeviceProvider, .onDevice),
            (geminiProvider, .gemini),
            (claudeProvider, .claude),
            (localGPUProvider, .localGPU),
        ]

        for (provider, tier) in providers {
            let available = await provider.isAvailable
            updateTierStatus(tier, status: available ? .available : .unavailable)
        }
    }

    // MARK: - Tier Selection

    /// Build the fallback chain based on complexity and network state.
    /// The chain starts with the ideal provider and includes fallbacks down to FoundationModels.
    private func buildFallbackChain(for complexity: PromptComplexity) -> [any AIProvider] {
        let isOnline = networkChecker.isOnline

        // Offline: only on-device
        guard isOnline else {
            return [onDeviceProvider]
        }

        // Online: build chain based on complexity
        switch complexity {
        case .simple:
            return [onDeviceProvider]

        case .medium:
            return [geminiProvider, onDeviceProvider]

        case .complex:
            return [claudeProvider, geminiProvider, onDeviceProvider]

        case .batch:
            return [localGPUProvider, claudeProvider, geminiProvider, onDeviceProvider]
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
