import Testing
import Foundation
@testable import IkeruCore

// MARK: - Mock AI Provider

private final class MockAIProvider: AIProvider, @unchecked Sendable {
    let name: String
    var available: Bool
    var responseText: String
    var shouldThrow: Error?

    init(
        name: String = "MockProvider",
        available: Bool = true,
        responseText: String = "こんにちは！元気ですか？",
        shouldThrow: Error? = nil
    ) {
        self.name = name
        self.available = available
        self.responseText = responseText
        self.shouldThrow = shouldThrow
    }

    func isAvailable() async -> Bool {
        available
    }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        if let error = shouldThrow {
            throw error
        }
        return AIResponse(text: responseText, providerName: name)
    }
}

// MARK: - ConversationService Tests

@Suite("ConversationService")
struct ConversationServiceTests {

    @Test("Sends message and receives response")
    func sendMessage() async throws {
        let provider = MockAIProvider(responseText: "はい、いい天気ですね！")
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "こんにちは",
            history: [],
            jlptLevel: .n5
        )

        #expect(response.role == .assistant)
        #expect(response.content == "はい、いい天気ですね！")
    }

    @Test("Parses corrections from response")
    func parsesCorrections() async throws {
        let responseText = """
        いいですね！
        [CORRECTION: 食べます → 食べました | Past tense needed here]
        """
        let provider = MockAIProvider(responseText: responseText)
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "昨日、寿司を食べます。",
            history: [],
            jlptLevel: .n4
        )

        #expect(response.content == "いいですね！")
        #expect(response.corrections.count == 1)
        #expect(response.corrections[0].original == "食べます")
        #expect(response.corrections[0].corrected == "食べました")
        #expect(response.corrections[0].explanation == "Past tense needed here")
    }

    @Test("Parses vocabulary hints from response")
    func parsesVocabularyHints() async throws {
        let responseText = """
        散歩しましょう！
        [VOCAB: 散歩(さんぽ) = walk]
        [VOCAB: 公園(こうえん) = park]
        """
        let provider = MockAIProvider(responseText: responseText)
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "外に行きたいです",
            history: [],
            jlptLevel: .n5
        )

        #expect(response.content == "散歩しましょう！")
        #expect(response.vocabularyHints.count == 2)
        #expect(response.vocabularyHints[0].word == "散歩")
        #expect(response.vocabularyHints[0].reading == "さんぽ")
        #expect(response.vocabularyHints[0].meaning == "walk")
        #expect(response.vocabularyHints[1].word == "公園")
    }

    @Test("Parses mixed content, corrections, and vocab")
    func parsesMixedContent() async throws {
        let responseText = """
        そうですか！楽しかったですか？
        [CORRECTION: 行きます → 行きました | Use past tense for completed actions]
        [VOCAB: 映画(えいが) = movie]
        """
        let provider = MockAIProvider(responseText: responseText)
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "昨日映画に行きます",
            history: [],
            jlptLevel: .n5
        )

        #expect(response.content == "そうですか！楽しかったですか？")
        #expect(response.corrections.count == 1)
        #expect(response.vocabularyHints.count == 1)
    }

    @Test("Includes history in AI messages")
    func includesHistory() async throws {
        let provider = MockAIProvider(responseText: "はい！")
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        let history = [
            ConversationMessage(role: .user, content: "こんにちは"),
            ConversationMessage(role: .assistant, content: "こんにちは！")
        ]

        let response = try await service.sendMessage(
            "元気ですか？",
            history: history,
            jlptLevel: .n5
        )

        #expect(response.role == .assistant)
    }

    @Test("Throws when no providers available")
    func throwsWhenUnavailable() async {
        let provider = MockAIProvider(available: false)
        let router = AIRouterService(providers: [provider])
        let service = ConversationService(aiRouter: router)

        await #expect(throws: AIProviderError.self) {
            try await service.sendMessage("hello", history: [], jlptLevel: .n5)
        }
    }

    @Test("Reports availability correctly")
    func availabilityCheck() async {
        let available = MockAIProvider(available: true)
        let unavailable = MockAIProvider(available: false)

        let routerAvailable = AIRouterService(providers: [available])
        let routerUnavailable = AIRouterService(providers: [unavailable])

        let serviceAvailable = ConversationService(aiRouter: routerAvailable)
        let serviceUnavailable = ConversationService(aiRouter: routerUnavailable)

        #expect(await serviceAvailable.isAvailable() == true)
        #expect(await serviceUnavailable.isAvailable() == false)
    }
}

// MARK: - AIRouterService Tests

@Suite("AIRouterService")
struct AIRouterServiceTests {

    @Test("Routes to first available provider")
    func routesToFirstAvailable() async throws {
        let provider1 = MockAIProvider(name: "First", available: false)
        let provider2 = MockAIProvider(name: "Second", responseText: "From second")
        let router = AIRouterService(providers: [provider1, provider2])

        let request = AIRequest(systemPrompt: "test", messages: [])
        let response = try await router.generate(request)

        #expect(response.providerName == "Second")
    }

    @Test("Falls back on provider error")
    func fallsBackOnError() async throws {
        let provider1 = MockAIProvider(
            name: "Failing",
            shouldThrow: AIProviderError.networkError("test")
        )
        let provider2 = MockAIProvider(name: "Fallback", responseText: "fallback response")
        let router = AIRouterService(providers: [provider1, provider2])

        let request = AIRequest(systemPrompt: "test", messages: [])
        let response = try await router.generate(request)

        #expect(response.providerName == "Fallback")
    }

    @Test("Throws when all providers fail")
    func throwsWhenAllFail() async {
        let provider = MockAIProvider(
            shouldThrow: AIProviderError.networkError("test")
        )
        let router = AIRouterService(providers: [provider])

        let request = AIRequest(systemPrompt: "test", messages: [])
        await #expect(throws: (any Error).self) {
            try await router.generate(request)
        }
    }

    @Test("Has available provider check")
    func hasAvailableProvider() async {
        let available = MockAIProvider(available: true)
        let unavailable = MockAIProvider(available: false)

        let router1 = AIRouterService(providers: [available])
        let router2 = AIRouterService(providers: [unavailable])
        let router3 = AIRouterService(providers: [])

        #expect(await router1.hasAvailableProvider() == true)
        #expect(await router2.hasAvailableProvider() == false)
        #expect(await router3.hasAvailableProvider() == false)
    }
}
