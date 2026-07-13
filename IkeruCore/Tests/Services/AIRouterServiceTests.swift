import Testing
import Foundation
@testable import IkeruCore

@Suite("AIRouterService")
@MainActor
struct AIRouterServiceTests {

    // MARK: - Helpers

    /// Create a router with configurable mock providers.
    private func makeRouter(
        onDevice: (any AIProvider)? = nil,
        gemini: (any AIProvider)? = nil,
        claude: (any AIProvider)? = nil,
        localGPU: (any AIProvider)? = nil,
        networkChecker: MockNetworkChecker = MockNetworkChecker(online: true)
    ) -> AIRouterService {
        AIRouterService(
            onDeviceProvider: onDevice ?? MockFoundationModelsProvider(available: true, responseContent: "on-device response"),
            geminiProvider: gemini ?? makeConfigurableMock(tier: .gemini, content: "gemini response"),
            claudeProvider: claude ?? makeConfigurableMock(tier: .claude, content: "claude response"),
            localGPUProvider: localGPU ?? makeConfigurableMock(tier: .localGPU, content: "localGPU response"),
            networkChecker: networkChecker
        )
    }

    private func makeConfigurableMock(
        tier: AITier,
        content: String,
        available: Bool = true,
        error: AIError? = nil,
        delay: Duration? = nil
    ) -> ConfigurableMockProvider {
        ConfigurableMockProvider(
            tier: tier,
            content: content,
            available: available,
            error: error,
            delay: delay
        )
    }

    /// `ProviderStatus` isn't `Equatable`, so pattern-match instead of `==`.
    private func isDegraded(_ status: ProviderStatus?) -> Bool {
        if case .degraded = status {
            return true
        }
        return false
    }

    // MARK: - Tier Selection: Offline

    @Test("Offline routes all complexities to FoundationModels")
    func offlineRoutesToOnDevice() async throws {
        let networkChecker = MockNetworkChecker(online: false)
        let router = makeRouter(networkChecker: networkChecker)

        for complexity in [PromptComplexity.simple, .medium, .complex, .batch] {
            let prompt = AIPrompt(
                systemPrompt: "System",
                userMessage: "Test",
                complexity: complexity
            )
            let response = try await router.generate(prompt: prompt)
            #expect(response.tier == .onDevice)
        }
    }

    // MARK: - Tier Selection: Online

    @Test("Online simple prompt routes to FoundationModels")
    func onlineSimpleRoutesToOnDevice() async throws {
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .simple
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    @Test("Online medium prompt routes to Gemini")
    func onlineMediumRoutesToGemini() async throws {
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .gemini)
    }

    @Test("Online complex prompt routes to first available free cloud (Gemini in this fixture)")
    func onlineComplexRoutesToFirstFreeCloud() async throws {
        // Story 7.2 chain for .complex: openRouter -> gemini -> cerebras -> groq -> githubModels -> claude -> onDevice
        // The legacy positional initializer only supplies onDevice/gemini/claude/localGPU,
        // so the resolved chain is [gemini, claude, onDevice]. Gemini wins.
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .gemini)
    }

    @Test("Online batch prompt routes to first free cloud (Gemini in this fixture)")
    func onlineBatchRoutesToFirstFreeCloud() async throws {
        // Story 7.2 chain for .batch: gemini -> openRouter -> cerebras -> githubModels -> onDevice
        // localGPU is no longer in the .batch chain — it is reserved for the future ikeru-rig bridge.
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .gemini)
    }

    // MARK: - Fallback Chains

    @Test("Gemini failure falls back to FoundationModels")
    func geminiFallbackToOnDevice() async throws {
        let router = makeRouter(
            gemini: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .providerUnavailable(.gemini)
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    @Test("Claude failure falls back through Gemini to FoundationModels")
    func claudeFallbackChain() async throws {
        let router = makeRouter(
            gemini: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .providerUnavailable(.gemini)
            ),
            claude: makeConfigurableMock(
                tier: .claude,
                content: "",
                available: true,
                error: .providerUnavailable(.claude)
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    @Test("LocalGPU failure falls back through Claude, Gemini to FoundationModels")
    func localGPUFallbackChain() async throws {
        let router = makeRouter(
            gemini: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .rateLimited(.gemini, retryAfter: nil)
            ),
            claude: makeConfigurableMock(
                tier: .claude,
                content: "",
                available: true,
                error: .timeout(.claude)
            ),
            localGPU: makeConfigurableMock(
                tier: .localGPU,
                content: "",
                available: true,
                error: .providerUnavailable(.localGPU)
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    @Test("Claude failure falls back to Gemini when Gemini is available")
    func claudeFallbackToGemini() async throws {
        let router = makeRouter(
            claude: makeConfigurableMock(
                tier: .claude,
                content: "",
                available: true,
                error: .timeout(.claude)
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .gemini)
    }

    // MARK: - Unavailable Provider Skipping

    @Test("Batch with unavailable Gemini falls through to onDevice via legacy 4-provider fixture")
    func batchSkipsUnavailableGemini() async throws {
        // Story 7.2 chain for .batch: [gemini, openRouter, cerebras, githubModels, onDevice].
        // Legacy fixture only has gemini + onDevice; making gemini unavailable falls
        // through directly to onDevice. (Claude is not in the .batch chain anymore.)
        let router = makeRouter(
            gemini: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: false
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    // MARK: - All Providers Exhausted

    @Test("All providers failing throws allProvidersExhausted")
    func allProvidersFailing() async {
        let router = makeRouter(
            onDevice: MockFoundationModelsProvider(available: false, responseContent: ""),
            gemini: makeConfigurableMock(tier: .gemini, content: "", available: false),
            claude: makeConfigurableMock(tier: .claude, content: "", available: false),
            localGPU: makeConfigurableMock(tier: .localGPU, content: "", available: false)
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )
        do {
            _ = try await router.generate(prompt: prompt)
            Issue.record("Expected allProvidersExhausted")
        } catch let error as AIError {
            if case .allProvidersExhausted = error {
                // passes
            } else {
                Issue.record("Expected allProvidersExhausted, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Tier Status Tracking

    @Test("Router tracks tier status for every AITier case")
    func tierStatusTracking() {
        let router = makeRouter()
        let statuses = router.tierStatuses
        // Story 7.2: AITier now has 8 cases (onDevice + 6 cloud providers + localGPU).
        // The router seeds a status for each case so the UI can render all sections.
        #expect(statuses.count == AITier.allCases.count)
    }

    // MARK: - Fallback Budget

    @Test("Fallback completes within 2.5 seconds budget across the new wider chain")
    func fallbackBudget() async throws {
        // Story 7.2: .medium chain widened from [gemini, onDevice] to
        // [cerebras, groq, openRouter, gemini, githubModels, onDevice].
        // The legacy positional fixture only supplies onDevice + gemini, so the
        // resolved chain is [gemini, onDevice]. We give gemini a short delay + failure
        // and expect the router to fall through to onDevice well within budget.
        let router = makeRouter(
            gemini: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .timeout(.gemini),
                delay: .milliseconds(200)
            )
        )
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )
        let start = ContinuousClock.now
        let response = try await router.generate(prompt: prompt)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2.5))
        #expect(response.tier == .onDevice)
    }

    // MARK: - Rate-Limit Cooldown

    @Test("Rate-limited provider is skipped on the next call within its cooldown window")
    func rateLimitedProviderSkippedWithinCooldown() async throws {
        let geminiMock = ConfigurableMockProvider(
            tier: .gemini,
            content: "gemini response",
            available: true,
            error: .rateLimited(.gemini, retryAfter: 30)
        )
        let onDeviceMock = MockFoundationModelsProvider(available: true, responseContent: "on-device response")
        let router = AIRouterService(
            providers: [.gemini: geminiMock, .onDevice: onDeviceMock],
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(systemPrompt: "System", userMessage: "Test", complexity: .medium)

        // First call: Gemini is hit, rate-limited, falls back to on-device.
        let first = try await router.generate(prompt: prompt)
        #expect(first.tier == .onDevice)
        #expect(geminiMock.generateCallCount == 1)
        #expect(isDegraded(router.tierStatuses[.gemini]))

        // Second call within the 30s cooldown: Gemini must be skipped entirely
        // (no retry storm), falling straight through to on-device again.
        let second = try await router.generate(prompt: prompt)
        #expect(second.tier == .onDevice)
        #expect(geminiMock.generateCallCount == 1, "Gemini must not be re-hit while its cooldown is active")
        #expect(isDegraded(router.tierStatuses[.gemini]))
    }

    @Test("Only rate-limited provider and on-device: second call is served by on-device without re-hitting the cooldown tier")
    func rateLimitedProviderOnlyOnDeviceFallbackServesSecondCall() async throws {
        let geminiMock = ConfigurableMockProvider(
            tier: .gemini,
            content: "gemini response",
            available: true,
            error: .rateLimited(.gemini, retryAfter: 60)
        )
        let onDeviceMock = MockFoundationModelsProvider(available: true, responseContent: "last resort")
        let router = AIRouterService(
            providers: [.gemini: geminiMock, .onDevice: onDeviceMock],
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(systemPrompt: "System", userMessage: "Test", complexity: .batch)

        _ = try await router.generate(prompt: prompt)
        let second = try await router.generate(prompt: prompt)

        #expect(second.tier == .onDevice)
        #expect(second.content == "last resort")
        #expect(geminiMock.generateCallCount == 1)
    }

    @Test("After the cooldown window elapses, the provider is retried normally")
    func rateLimitedProviderRetriedAfterCooldownElapses() async throws {
        // A zero-second retryAfter means the cooldown window is already in the
        // past by the time the second `generate` call runs (real time elapses
        // between the two awaits), so the tier is retried instead of skipped —
        // no sleep or clock seam required.
        let geminiMock = ConfigurableMockProvider(
            tier: .gemini,
            content: "gemini response",
            available: true,
            error: .rateLimited(.gemini, retryAfter: 0)
        )
        let onDeviceMock = MockFoundationModelsProvider(available: true, responseContent: "on-device response")
        let router = AIRouterService(
            providers: [.gemini: geminiMock, .onDevice: onDeviceMock],
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(systemPrompt: "System", userMessage: "Test", complexity: .medium)

        _ = try await router.generate(prompt: prompt)
        #expect(geminiMock.generateCallCount == 1)

        _ = try await router.generate(prompt: prompt)
        #expect(geminiMock.generateCallCount == 2, "Gemini should be retried once its cooldown has elapsed")
    }

    @Test("Cooled-down tier that is last in the chain (no on-device) throws rate-limited without re-hitting it")
    func rateLimitedLastProviderInCooldownThrows() async throws {
        // No on-device registered, so the chain is just [gemini]: the cooldown
        // check fires on the LAST provider, exercising the skip-path throw
        // branch (which the two-provider tests never reach).
        let geminiMock = ConfigurableMockProvider(
            tier: .gemini,
            content: "gemini response",
            available: true,
            error: .rateLimited(.gemini, retryAfter: 30)
        )
        let router = AIRouterService(
            providers: [.gemini: geminiMock],
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(systemPrompt: "System", userMessage: "Test", complexity: .medium)

        // First call hits Gemini, gets 429, exhausts the chain → throws.
        await #expect(throws: AIError.self) { try await router.generate(prompt: prompt) }
        #expect(geminiMock.generateCallCount == 1)

        // Second call within cooldown skips Gemini and throws via the skip path,
        // without re-hitting the rate-limited provider.
        await #expect(throws: AIError.self) { try await router.generate(prompt: prompt) }
        #expect(geminiMock.generateCallCount == 1, "Gemini must not be re-hit while cooling down, even as last provider")
    }

    @Test("refreshTierStatuses reports a cooling-down tier as degraded even when its provider is available")
    func refreshTierStatusesHonorsCooldown() async throws {
        let geminiMock = ConfigurableMockProvider(
            tier: .gemini,
            content: "gemini response",
            available: true,
            error: .rateLimited(.gemini, retryAfter: 30)
        )
        let onDeviceMock = MockFoundationModelsProvider(available: true, responseContent: "on-device response")
        let router = AIRouterService(
            providers: [.gemini: geminiMock, .onDevice: onDeviceMock],
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(systemPrompt: "System", userMessage: "Test", complexity: .medium)

        _ = try await router.generate(prompt: prompt)

        // Gemini's provider is still "available", but a Settings refresh must
        // surface the active cooldown as degraded rather than green.
        await router.refreshTierStatuses()
        #expect(isDegraded(router.tierStatuses[.gemini]))
    }
}

// MARK: - ConfigurableMockProvider

/// Highly configurable mock for router testing.
final class ConfigurableMockProvider: AIProvider, @unchecked Sendable {

    let name: String
    let tier: AITier
    private let content: String
    private let _available: Bool
    private let _error: AIError?
    private let _delay: Duration?

    /// Number of times `generate(prompt:)` was invoked. Used by cooldown tests
    /// to assert a rate-limited provider is NOT re-hit while its cooldown is
    /// still active. Router calls into mocks are sequential (single in-flight
    /// request per test), so a plain counter is sufficient here.
    private(set) var generateCallCount = 0

    init(
        tier: AITier,
        content: String,
        available: Bool = true,
        error: AIError? = nil,
        delay: Duration? = nil
    ) {
        self.tier = tier
        self.name = "\(tier)"
        self.content = content
        self._available = available
        self._error = error
        self._delay = delay
    }

    var isAvailable: Bool {
        get async { _available }
    }

    func generate(prompt: AIPrompt) async throws -> AIResponse {
        generateCallCount += 1

        if let delay = _delay {
            try await Task.sleep(for: delay)
        }

        if let error = _error {
            throw error
        }

        return AIResponse(
            content: content,
            tier: tier,
            latencyMs: 50
        )
    }
}
