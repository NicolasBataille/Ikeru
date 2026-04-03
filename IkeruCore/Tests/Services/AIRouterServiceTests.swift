import Testing
import Foundation
@testable import IkeruCore

@Suite("AIRouterService")
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

    @Test("Online complex prompt routes to Claude")
    func onlineComplexRoutesToClaude() async throws {
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .claude)
    }

    @Test("Online batch prompt routes to LocalGPU when available")
    func onlineBatchRoutesToLocalGPU() async throws {
        let router = makeRouter()
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .localGPU)
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
                error: .rateLimited(.gemini)
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

    @Test("Batch skips unavailable LocalGPU and tries Claude")
    func batchSkipsUnavailableLocalGPU() async throws {
        let router = makeRouter(
            localGPU: makeConfigurableMock(
                tier: .localGPU,
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
        #expect(response.tier == .claude)
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

    @Test("Router tracks tier status")
    func tierStatusTracking() {
        let router = makeRouter()
        let statuses = router.tierStatuses
        #expect(statuses.count == 4)
    }

    // MARK: - Fallback Budget

    @Test("Fallback completes within 2 seconds budget")
    func fallbackBudget() async throws {
        // First provider has a short delay then fails
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
        #expect(elapsed < .seconds(2))
        #expect(response.tier == .onDevice)
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
