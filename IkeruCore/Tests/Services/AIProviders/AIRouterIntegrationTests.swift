import Testing
import Foundation
@testable import IkeruCore

@Suite("AI Router Integration Tests")
struct AIRouterIntegrationTests {

    // MARK: - Helpers

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

    // MARK: - Tier Selection Integration

    @Test("Offline routes to FoundationModels regardless of complexity")
    func offlineAlwaysOnDevice() async throws {
        let networkChecker = MockNetworkChecker(online: false)
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "offline answer"),
            geminiProvider: makeConfigurableMock(tier: .gemini, content: "gemini", available: true),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "claude", available: true),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "gpu", available: true),
            networkChecker: networkChecker
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
        #expect(response.content == "offline answer")
    }

    @Test("Online simple routes to FoundationModels")
    func onlineSimpleRoutesToOnDevice() async throws {
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "on-device"),
            geminiProvider: makeConfigurableMock(tier: .gemini, content: "gemini"),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "claude"),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "gpu"),
            networkChecker: MockNetworkChecker(online: true)
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Simple question",
            complexity: .simple
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
    }

    @Test("Online complex routes to Claude")
    func onlineComplexRoutesToClaude() async throws {
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "on-device"),
            geminiProvider: makeConfigurableMock(tier: .gemini, content: "gemini"),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "claude complex answer"),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "gpu"),
            networkChecker: MockNetworkChecker(online: true)
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Complex grammar explanation",
            complexity: .complex
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .claude)
        #expect(response.content == "claude complex answer")
    }

    // MARK: - Fallback Integration

    @Test("Gemini failure falls back to FoundationModels within 2 seconds")
    func geminiFallbackWithin2Seconds() async throws {
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "fallback answer"),
            geminiProvider: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .rateLimited(.gemini)
            ),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "claude"),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "gpu"),
            networkChecker: MockNetworkChecker(online: true)
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )

        let start = ContinuousClock.now
        let response = try await router.generate(prompt: prompt)
        let elapsed = ContinuousClock.now - start

        #expect(response.tier == .onDevice)
        #expect(response.content == "fallback answer")
        #expect(elapsed < .seconds(2), "Fallback must complete within 2 seconds")
    }

    @Test("All cloud providers fail, FoundationModels serves as final fallback")
    func allCloudFailFinalFallback() async throws {
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "last resort"),
            geminiProvider: makeConfigurableMock(tier: .gemini, content: "", available: true, error: .networkError(URLError(.notConnectedToInternet))),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "", available: true, error: .timeout(.claude)),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "", available: true, error: .providerUnavailable(.localGPU)),
            networkChecker: MockNetworkChecker(online: true)
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )
        let response = try await router.generate(prompt: prompt)
        #expect(response.tier == .onDevice)
        #expect(response.content == "last resort")
    }

    // MARK: - Network Transition

    @Test("Going offline mid-session gracefully degrades")
    func networkTransition() async throws {
        let networkChecker = MockNetworkChecker(online: true)
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "on-device fallback"),
            geminiProvider: makeConfigurableMock(tier: .gemini, content: "gemini answer"),
            claudeProvider: makeConfigurableMock(tier: .claude, content: "claude"),
            localGPUProvider: makeConfigurableMock(tier: .localGPU, content: "gpu"),
            networkChecker: networkChecker
        )

        // First request online
        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .medium
        )
        let onlineResponse = try await router.generate(prompt: prompt)
        #expect(onlineResponse.tier == .gemini)

        // Go offline
        networkChecker.setOnline(false)

        // Second request should route to on-device
        let offlineResponse = try await router.generate(prompt: prompt)
        #expect(offlineResponse.tier == .onDevice)
    }

    // MARK: - Bonjour Discovery

    @Test("Mock service discovery enables LocalGPUProvider availability")
    func bonjourDiscoveryTest() async {
        let discovery = MockBonjourDiscovery(endpoint: nil)
        let provider = LocalGPUProvider(bonjourDiscovery: discovery)

        // Initially unavailable
        let unavailable = await provider.isAvailable
        #expect(unavailable == false)

        // Discover service
        discovery.setEndpoint(BonjourEndpoint(host: "192.168.1.50", port: 9090))

        // Now available
        let available = await provider.isAvailable
        #expect(available == true)
    }

    // MARK: - Keychain Integration

    @Test("Save and load API keys via mock Keychain")
    func keychainSaveAndLoad() throws {
        let store = MockKeychainStore()

        try store.save(key: KeychainKeys.geminiAPIKey, value: "test-gemini-key")
        try store.save(key: KeychainKeys.claudeSessionToken, value: "test-claude-token")

        let geminiKey = try store.load(key: KeychainKeys.geminiAPIKey)
        let claudeToken = try store.load(key: KeychainKeys.claudeSessionToken)

        #expect(geminiKey == "test-gemini-key")
        #expect(claudeToken == "test-claude-token")
    }

    @Test("Delete API keys via mock Keychain")
    func keychainDeletion() throws {
        let store = MockKeychainStore(
            initialValues: [
                KeychainKeys.geminiAPIKey: "key",
                KeychainKeys.claudeSessionToken: "token",
            ]
        )

        try store.delete(key: KeychainKeys.geminiAPIKey)
        let geminiKey = try store.load(key: KeychainKeys.geminiAPIKey)
        #expect(geminiKey == nil)

        // Claude token still exists
        let claudeToken = try store.load(key: KeychainKeys.claudeSessionToken)
        #expect(claudeToken == "token")
    }

    // MARK: - 2-Second Fallback Budget

    @Test("Total fallback time from first attempt to response is under 2000ms")
    func fallbackBudgetEnforcement() async throws {
        let router = AIRouterService(
            onDeviceProvider: MockFoundationModelsProvider(available: true, responseContent: "fast fallback"),
            geminiProvider: makeConfigurableMock(
                tier: .gemini,
                content: "",
                available: true,
                error: .timeout(.gemini),
                delay: .milliseconds(100)
            ),
            claudeProvider: makeConfigurableMock(
                tier: .claude,
                content: "",
                available: true,
                error: .timeout(.claude),
                delay: .milliseconds(100)
            ),
            localGPUProvider: makeConfigurableMock(
                tier: .localGPU,
                content: "",
                available: true,
                error: .providerUnavailable(.localGPU),
                delay: .milliseconds(100)
            ),
            networkChecker: MockNetworkChecker(online: true)
        )

        let prompt = AIPrompt(
            systemPrompt: "System",
            userMessage: "Test",
            complexity: .batch
        )

        let start = ContinuousClock.now
        let response = try await router.generate(prompt: prompt)
        let elapsed = ContinuousClock.now - start

        #expect(response.tier == .onDevice)
        #expect(elapsed < .milliseconds(2000), "Total fallback time must be under 2000ms")
    }
}
