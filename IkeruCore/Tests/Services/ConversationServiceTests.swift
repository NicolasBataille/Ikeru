import Testing
import Foundation
@testable import IkeruCore

// MARK: - Mock AI Provider for ConversationService Tests

private final class MockConversationAIProvider: AIProvider, @unchecked Sendable {
    let name: String
    let tier: AITier
    private let _available: Bool
    private let responseContent: String
    private let shouldThrow: Error?

    init(
        name: String = "MockProvider",
        tier: AITier = .onDevice,
        available: Bool = true,
        responseContent: String = "こんにちは！元気ですか？",
        shouldThrow: Error? = nil
    ) {
        self.name = name
        self.tier = tier
        self._available = available
        self.responseContent = responseContent
        self.shouldThrow = shouldThrow
    }

    var isAvailable: Bool {
        get async { _available }
    }

    func generate(prompt: AIPrompt) async throws -> AIResponse {
        if let error = shouldThrow {
            throw error
        }
        return AIResponse(
            content: responseContent,
            tier: tier,
            latencyMs: 50
        )
    }
}

/// Records the last prompt it was handed so tests can assert on the assembled
/// system prompt. Tests drive it serially on the MainActor.
private final class CapturingAIProvider: AIProvider, @unchecked Sendable {
    let name = "CapturingProvider"
    let tier: AITier = .onDevice
    private let lock = NSLock()
    private var _lastPrompt: AIPrompt?

    var lastPrompt: AIPrompt? {
        lock.withLock { _lastPrompt }
    }

    var isAvailable: Bool { get async { true } }

    func generate(prompt: AIPrompt) async throws -> AIResponse {
        lock.withLock { _lastPrompt = prompt }
        return AIResponse(content: "はい！", tier: tier, latencyMs: 10)
    }
}

// MARK: - ConversationService Tests

@Suite("ConversationService")
@MainActor
struct ConversationServiceTests {

    @Test("Sends message and receives response")
    func sendMessage() async throws {
        let provider = MockConversationAIProvider(responseContent: "はい、いい天気ですね！")
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "こんにちは",
            history: [],
            jlptLevel: JLPTLevel.n5
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
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "昨日、寿司を食べます。",
            history: [],
            jlptLevel: JLPTLevel.n4
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
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "外に行きたいです",
            history: [],
            jlptLevel: JLPTLevel.n5
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
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "昨日映画に行きます",
            history: [],
            jlptLevel: JLPTLevel.n5
        )

        #expect(response.content == "そうですか！楽しかったですか？")
        #expect(response.corrections.count == 1)
        #expect(response.vocabularyHints.count == 1)
    }

    @Test("Includes history in AI messages")
    func includesHistory() async throws {
        let provider = MockConversationAIProvider(responseContent: "はい！")
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let history = [
            ConversationMessage(role: .user, content: "こんにちは"),
            ConversationMessage(role: MessageRole.assistant, content: "こんにちは！")
        ]

        let response = try await service.sendMessage(
            "元気ですか？",
            history: history,
            jlptLevel: JLPTLevel.n5
        )

        #expect(response.role == .assistant)
    }

    @Test("Throws when no providers available")
    func throwsWhenUnavailable() async {
        let provider = MockConversationAIProvider(available: false)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        await #expect(throws: AIError.self) {
            try await service.sendMessage("hello", history: [], jlptLevel: JLPTLevel.n5)
        }
    }

    @Test("Known vocabulary is injected as a soft preference")
    func injectsKnownVocabulary() async throws {
        let provider = CapturingAIProvider()
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        _ = try await service.sendMessage(
            "こんにちは",
            history: [],
            jlptLevel: JLPTLevel.n5,
            knownVocabulary: ["猫(ねこ)", "犬(いぬ)"]
        )

        let prompt = try #require(provider.lastPrompt?.systemPrompt)
        #expect(prompt.contains("WORDS THE LEARNER ALREADY KNOWS"))
        #expect(prompt.contains("猫(ねこ)"))
        #expect(prompt.contains("犬(いぬ)"))
        // The soft-preference framing must be present so Sakura never forces words.
        #expect(prompt.contains("SOFT preference"))
        #expect(prompt.contains("do NOT force"))
    }

    @Test("No known-vocabulary section when the list is empty")
    func omitsKnownVocabularyWhenEmpty() async throws {
        let provider = CapturingAIProvider()
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        _ = try await service.sendMessage(
            "こんにちは",
            history: [],
            jlptLevel: JLPTLevel.n5
        )

        let prompt = try #require(provider.lastPrompt?.systemPrompt)
        #expect(!prompt.contains("WORDS THE LEARNER ALREADY KNOWS"))
    }

    // MARK: - Reading Reconciliation

    @Test("A wrong AI reading is corrected against the bundle reading")
    func correctsWrongReadingAgainstBundle() async throws {
        let responseText = """
        こんにちは！
        [VOCAB: 日本(にっぽん) = Japan]
        """
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "日本は好きですか？",
            history: [],
            jlptLevel: JLPTLevel.n5,
            bundleReadings: ["日本": "にほん"]
        )

        #expect(response.vocabularyHints.count == 1)
        #expect(response.vocabularyHints[0].word == "日本")
        #expect(response.vocabularyHints[0].reading == "にほん")
        #expect(response.vocabularyHints[0].meaning == "Japan")
    }

    @Test("An unknown word's AI reading passes through untouched")
    func unknownWordPassesThrough() async throws {
        let responseText = """
        散歩しましょう！
        [VOCAB: 散歩(さんぽ) = walk]
        """
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "外に行きたいです",
            history: [],
            jlptLevel: JLPTLevel.n5,
            bundleReadings: ["日本": "にほん"]
        )

        #expect(response.vocabularyHints.count == 1)
        #expect(response.vocabularyHints[0].word == "散歩")
        #expect(response.vocabularyHints[0].reading == "さんぽ")
    }

    @Test("Empty bundleReadings default leaves existing hint behavior unchanged")
    func emptyBundleReadingsDefaultIsNoOp() async throws {
        let responseText = """
        散歩しましょう！
        [VOCAB: 散歩(さんぽ) = walk]
        [VOCAB: 公園(こうえん) = park]
        """
        let provider = MockConversationAIProvider(responseContent: responseText)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: provider,
            localGPUProvider: provider
        )
        let service = ConversationService(aiRouter: router)

        let response = try await service.sendMessage(
            "外に行きたいです",
            history: [],
            jlptLevel: JLPTLevel.n5
        )

        #expect(response.vocabularyHints.count == 2)
        #expect(response.vocabularyHints[0].word == "散歩")
        #expect(response.vocabularyHints[0].reading == "さんぽ")
        #expect(response.vocabularyHints[1].word == "公園")
        #expect(response.vocabularyHints[1].reading == "こうえん")
    }
}
