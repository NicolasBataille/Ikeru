import Testing
import Foundation
@testable import IkeruCore

@Suite("GeminiProvider")
struct GeminiProviderTests {

    // MARK: - Provider Properties

    @Test("Provider name is Gemini")
    func providerName() {
        let keychain = MockKeychainStore()
        let provider = GeminiProvider(keychainStore: keychain)
        #expect(provider.name == "Gemini")
    }

    @Test("Provider tier is gemini")
    func providerTier() {
        let keychain = MockKeychainStore()
        let provider = GeminiProvider(keychainStore: keychain)
        #expect(provider.tier == .gemini)
    }

    // MARK: - Availability

    @Test("Provider is unavailable without API key")
    func unavailableWithoutKey() async {
        let keychain = MockKeychainStore()
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true)
        )
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("Provider is unavailable when offline")
    func unavailableWhenOffline() async throws {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.geminiAPIKey: "test-key"]
        )
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: false)
        )
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("Provider is available with API key and network")
    func availableWithKeyAndNetwork() async throws {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.geminiAPIKey: "test-key"]
        )
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true)
        )
        let available = await provider.isAvailable
        #expect(available == true)
    }

    // MARK: - Generation with mock session

    @Test("Successful generation returns response")
    func successfulGeneration() async throws {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.geminiAPIKey: "test-key"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: geminiSuccessJSON,
            statusCode: 200
        )
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "Tutor",
            userMessage: "Hello"
        )
        let response = try await provider.generate(prompt: prompt)
        #expect(response.content == "Hello! How can I help?")
        #expect(response.tier == .gemini)
    }

    @Test("Rate limited response throws rateLimited error")
    func rateLimited() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.geminiAPIKey: "test-key"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("{}".utf8),
            statusCode: 429
        )
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "Tutor",
            userMessage: "Hello"
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected rateLimited error")
        } catch let error as AIError {
            if case .rateLimited(let tier) = error {
                #expect(tier == .gemini)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Missing API key throws keyNotFound error")
    func missingAPIKey() async {
        let keychain = MockKeychainStore()
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true)
        )
        let prompt = AIPrompt(
            systemPrompt: "Tutor",
            userMessage: "Hello"
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected keyNotFound error")
        } catch let error as AIError {
            if case .keyNotFound(let key) = error {
                #expect(key == KeychainKeys.geminiAPIKey)
            } else {
                Issue.record("Expected keyNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Invalid JSON response throws invalidResponse error")
    func invalidJSON() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.geminiAPIKey: "test-key"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("not json".utf8),
            statusCode: 200
        )
        let provider = GeminiProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "Tutor",
            userMessage: "Hello"
        )
        do {
            _ = try await provider.generate(prompt: prompt)
            Issue.record("Expected invalidResponse error")
        } catch let error as AIError {
            if case .invalidResponse = error {
                // passes
            } else {
                Issue.record("Expected invalidResponse, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Test Data

    private var geminiSuccessJSON: Data {
        Data("""
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": "Hello! How can I help?"
                            }
                        ]
                    }
                }
            ]
        }
        """.utf8)
    }
}
