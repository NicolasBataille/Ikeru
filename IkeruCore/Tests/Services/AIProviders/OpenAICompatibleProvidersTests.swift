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

    @Test("429 with Retry-After header carries retryAfter on rateLimited")
    func rateLimitedWithRetryAfterHeader() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.openRouterAPIKey: "ok"]
        )
        let session = MockURLSessionProvider(
            responseData: Data("{}".utf8),
            statusCode: 429,
            headerFields: ["Retry-After": "12"]
        )
        let provider = OpenRouterProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        do {
            _ = try await provider.generate(
                prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
            )
            Issue.record("Expected rateLimited error")
        } catch let error as AIError {
            if case .rateLimited(let tier, let retryAfter) = error {
                #expect(tier == .openRouter)
                #expect(retryAfter == 12)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
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

    @Test("GitHubModelsProvider posts to the native models.github.ai endpoint with a publisher-prefixed model id")
    func githubModelsUsesNativeEndpoint() async throws {
        let responseJSON = Data("""
        {
          "choices": [
            { "message": { "role": "assistant", "content": "hello" } }
          ]
        }
        """.utf8)
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.githubModelsAPIKey: "gh-test"]
        )
        let session = RequestCapturingURLSessionProvider(responseData: responseJSON, statusCode: 200)
        let provider = GitHubModelsProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: session
        )
        _ = try await provider.generate(
            prompt: AIPrompt(systemPrompt: "s", userMessage: "u")
        )

        let capturedURL = await session.lastRequest?.url
        #expect(capturedURL?.host == "models.github.ai")
        #expect(capturedURL?.path == "/inference/chat/completions")

        let body = await session.lastRequest?.httpBody
        let json = try #require(body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let model = try #require(json["model"] as? String)
        // Exact id from the live catalog (https://models.github.ai/catalog/models):
        // lowercase, publisher-prefixed — the Azure-bridge-era bare/UpperCamel
        // forms are rejected by the native endpoint.
        #expect(model == "meta/llama-3.3-70b-instruct", "unexpected default model id: \(model)")
    }
}

/// Captures the last outgoing request for assertions the built-in
/// `MockURLSessionProvider` doesn't expose (e.g. resolved host/path/body).
private actor RequestCapturingURLSessionProvider: URLSessionProvider {
    private let responseData: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseData, response)
    }
}
