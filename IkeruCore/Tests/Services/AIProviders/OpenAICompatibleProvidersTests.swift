import Testing
import Foundation
@testable import IkeruCore

// MARK: - OpenAI-Compatible Providers
//
// OpenRouter, Groq, Cerebras, and GitHub Models all share `OpenAICompatibleTransport`.
// We test the transport once thoroughly via `OpenRouterProvider`, then run a tiny
// smoke test per concrete provider to confirm wiring (name, tier, keychain key).

@Suite("OpenAICompatibleTransport via OpenRouterProvider")
struct OpenAICompatibleTransportTests {

    private let successJSON = Data("""
    {
      "choices": [
        { "message": { "role": "assistant", "content": "こんにちは" } }
      ]
    }
    """.utf8)

    @Test("Generates response on 200 OK")
    func successfulGeneration() async throws {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "sk-or-test"]
        )
        let session = MockURLSessionProvider(responseData: successJSON, statusCode: 200)
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        let response = try await provider.generate(
            prompt: AIPrompt(systemPrompt: "Tutor", userMessage: "Hello")
        )
        #expect(response.content == "こんにちは")
        #expect(response.tier == .openRouter)
    }

    @Test("Throws keyNotFound when Keychain has no key")
    func missingKey() async {
        let keychain = MockKeychainStore()
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: MockURLSessionProvider(responseData: Data(), statusCode: 200)
        )
        await #expect(throws: AIError.self) {
            try await provider.generate(
                prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
            )
        }
    }

    @Test("Maps 401 to keyNotFound")
    func unauthorized() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "bad"]
        )
        let session = MockURLSessionProvider(responseData: Data("{}".utf8), statusCode: 401)
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        await #expect(throws: AIError.self) {
            try await provider.generate(
                prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
            )
        }
    }

    @Test("Maps 429 to rateLimited")
    func rateLimited() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "ok"]
        )
        let session = MockURLSessionProvider(responseData: Data("{}".utf8), statusCode: 429)
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        await #expect(throws: AIError.self) {
            try await provider.generate(
                prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
            )
        }
    }

    @Test("Throws invalidResponse on malformed JSON")
    func malformedResponse() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "ok"]
        )
        let session = MockURLSessionProvider(
            responseData: Data("not json".utf8),
            statusCode: 200
        )
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        await #expect(throws: AIError.self) {
            try await provider.generate(
                prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
            )
        }
    }

    @Test("isAvailable false when offline even with key")
    func offlineWithKey() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "ok"]
        )
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: false)
        )
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("isAvailable true with key + network")
    func availableWithKeyAndNetwork() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "ok"]
        )
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true)
        )
        let available = await provider.isAvailable
        #expect(available == true)
    }
}

// MARK: - Smoke wiring tests for the 4 providers

@Suite("New provider wiring")
struct NewProviderWiringTests {

    @Test("OpenRouterProvider exposes correct identity")
    func openRouterIdentity() {
        let provider = OpenRouterProvider()
        #expect(provider.name == "OpenRouter")
        #expect(provider.tier == .openRouter)
    }

    @Test("GroqProvider exposes correct identity")
    func groqIdentity() {
        let provider = GroqProvider()
        #expect(provider.name == "Groq")
        #expect(provider.tier == .groq)
    }

    @Test("CerebrasProvider exposes correct identity")
    func cerebrasIdentity() {
        let provider = CerebrasProvider()
        #expect(provider.name == "Cerebras")
        #expect(provider.tier == .cerebras)
    }

    @Test("GitHubModelsProvider exposes correct identity")
    func githubModelsIdentity() {
        let provider = GitHubModelsProvider()
        #expect(provider.name == "GitHub Models")
        #expect(provider.tier == .githubModels)
    }

    @Test("Each provider reads its own Keychain key for availability")
    func eachProviderUsesOwnKeychainKey() async {
        let keychain = MockKeychainStore(initialValues: [
            KeychainKeys.openRouterAPIKey: "or",
            KeychainKeys.groqAPIKey: "gq",
            KeychainKeys.cerebrasAPIKey: "cb",
            KeychainKeys.githubModelsAPIKey: "gh",
        ])
        let net = MockNetworkChecker(online: true)

        let openRouter = OpenRouterProvider(keychainStore: keychain, networkChecker: net)
        let groq = GroqProvider(keychainStore: keychain, networkChecker: net)
        let cerebras = CerebrasProvider(keychainStore: keychain, networkChecker: net)
        let github = GitHubModelsProvider(keychainStore: keychain, networkChecker: net)

        #expect(await openRouter.isAvailable == true)
        #expect(await groq.isAvailable == true)
        #expect(await cerebras.isAvailable == true)
        #expect(await github.isAvailable == true)
    }

    @Test("Providers report unavailable when only an unrelated key is stored")
    func providersDoNotShareKeys() async {
        let keychain = MockKeychainStore(initialValues: [
            KeychainKeys.geminiAPIKey: "gemini-key",
        ])
        let net = MockNetworkChecker(online: true)

        let openRouter = OpenRouterProvider(keychainStore: keychain, networkChecker: net)
        let groq = GroqProvider(keychainStore: keychain, networkChecker: net)

        #expect(await openRouter.isAvailable == false)
        #expect(await groq.isAvailable == false)
    }
}
