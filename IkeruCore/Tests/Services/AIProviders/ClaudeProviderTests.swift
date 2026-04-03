import Testing
import Foundation
@testable import IkeruCore

@Suite("ClaudeProvider")
struct ClaudeProviderTests {

    // MARK: - Provider Properties

    @Test("Provider name is Claude")
    func providerName() {
        let keychain = MockKeychainStore()
        let provider = ClaudeProvider(keychainStore: keychain)
        #expect(provider.name == "Claude")
    }

    @Test("Provider tier is claude")
    func providerTier() {
        let keychain = MockKeychainStore()
        let provider = ClaudeProvider(keychainStore: keychain)
        #expect(provider.tier == .claude)
    }

    // MARK: - Availability

    @Test("Provider is unavailable without session token")
    func unavailableWithoutToken() async {
        let keychain = MockKeychainStore()
        let provider = ClaudeProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true)
        )
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("Provider is unavailable when offline")
    func unavailableWhenOffline() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let provider = ClaudeProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: false)
        )
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("Provider is available with token and network")
    func availableWithTokenAndNetwork() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let provider = ClaudeProvider(
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
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: claudeSuccessJSON,
            statusCode: 200
        )
        let provider = ClaudeProvider(
            keychainStore: keychain,
            networkChecker: MockNetworkChecker(online: true),
            urlSession: mockSession
        )
        let prompt = AIPrompt(
            systemPrompt: "Tutor",
            userMessage: "Explain this grammar",
            complexity: .complex
        )
        let response = try await provider.generate(prompt: prompt)
        #expect(response.content == "Here is the explanation.")
        #expect(response.tier == .claude)
    }

    @Test("Rate limited response throws rateLimited error")
    func rateLimited() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("{}".utf8),
            statusCode: 429
        )
        let provider = ClaudeProvider(
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
                #expect(tier == .claude)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Missing session token throws keyNotFound error")
    func missingToken() async {
        let keychain = MockKeychainStore()
        let provider = ClaudeProvider(
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
                #expect(key == KeychainKeys.claudeSessionToken)
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
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("not json".utf8),
            statusCode: 200
        )
        let provider = ClaudeProvider(
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

    @Test("Server error (500) throws invalidResponse error")
    func serverError() async {
        let keychain = MockKeychainStore(
            initialValues: [KeychainKeys.claudeSessionToken: "test-token"]
        )
        let mockSession = MockURLSessionProvider(
            responseData: Data("{}".utf8),
            statusCode: 500
        )
        let provider = ClaudeProvider(
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

    private var claudeSuccessJSON: Data {
        Data("""
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "text",
                    "text": "Here is the explanation."
                }
            ],
            "model": "claude-sonnet-4-20250514",
            "usage": {
                "input_tokens": 50,
                "output_tokens": 25
            }
        }
        """.utf8)
    }
}
