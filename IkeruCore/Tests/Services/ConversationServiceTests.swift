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

    @Test("Le prénom de l'apprenant est injecté comme préférence souple (OBS2-028)")
    func injectsLearnerName() async throws {
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
            learnerName: "Hugo"
        )

        let prompt = try #require(provider.lastPrompt?.systemPrompt)
        #expect(prompt.contains("LEARNER'S NAME: Hugo"))
        // Même cadrage souple que pour le vocabulaire : une partenaire qui
        // place le prénom à chaque tour est plus artificielle que celle qui
        // ne le dit jamais.
        #expect(prompt.contains("SOFT preference"))
        #expect(prompt.contains("do NOT open every message with it"))
    }

    @Test("Un prénom vide ou blanc laisse le prompt rigoureusement inchangé")
    func omitsLearnerNameWhenBlank() async throws {
        for name in ["", "   "] {
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
                learnerName: name
            )

            let prompt = try #require(provider.lastPrompt?.systemPrompt)
            #expect(!prompt.contains("LEARNER'S NAME"), "prénom vide : aucune section (\(name.count) caractères)")
        }
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

// MARK: - Bounded Network Retry

/// Counts `generate()` invocations and can inject a controlled delay before
/// throwing a fixed `AIError`, so retry tests can pin down exactly how many
/// full `AIRouterService.generate` attempts `ConversationService` made — and
/// roughly how long each one took — without depending on real network
/// conditions.
private final class RetryCountingAIProvider: AIProvider, @unchecked Sendable {
    let name = "RetryCountingProvider"
    let tier: AITier
    private let delay: Duration
    private let errorToThrow: AIError
    private let lock = NSLock()
    private var _callCount = 0

    init(tier: AITier, delay: Duration = .zero, errorToThrow: AIError) {
        self.tier = tier
        self.delay = delay
        self.errorToThrow = errorToThrow
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }

    var isAvailable: Bool { get async { true } }

    func generate(prompt: AIPrompt) async throws -> AIResponse {
        lock.withLock { _callCount += 1 }
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        throw errorToThrow
    }
}

/// Covers the `timeoutSeconds`-gated retry added to
/// `ConversationService.generateWithSingleNetworkRetry`: a first attempt
/// that already burned the retry budget must NOT trigger a second one — see
/// CLAUDE.md-adjacent task notes on the ~20s worst case this closes.
///
/// The same `RetryCountingAIProvider` instance is wired as BOTH the
/// on-device and Gemini provider (mirroring the positional
/// `AIRouterService` test initializer used elsewhere in this file), so its
/// `callCount` sums across the two-tier `.medium` fallback chain
/// (`[gemini, onDevice]` once Cerebras/Groq/OpenRouter/GitHub Models are
/// absent from the injected providers dict) — one full router attempt is 2
/// calls, a retried attempt is 4. Both tests also inject
/// `MockNetworkChecker(online: true)` explicitly — the positional
/// initializer's real `NWPathNetworkChecker()` default reports offline
/// until its monitor's first async callback lands, which can otherwise
/// race the very first `generate()` call and collapse the chain to
/// on-device-only, making these exact call counts flaky.
@Suite("ConversationService — Bounded Network Retry")
@MainActor
struct ConversationServiceRetryTests {

    @Test("A fast, non-actionable failure still gets one silent retry")
    func fastFailureStillRetries() async {
        let provider = RetryCountingAIProvider(tier: .gemini, errorToThrow: .invalidResponse)
        let unavailable = MockConversationAIProvider(available: false)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: unavailable,
            localGPUProvider: unavailable,
            // Deterministic in place of the real `NWPathNetworkChecker()`
            // default: that monitor's first callback lands asynchronously,
            // so `buildFallbackChain` can race it and see `isOnline ==
            // false` on the very first call, collapsing the chain to
            // on-device-only (1 call) instead of the `.medium` [gemini,
            // onDevice] chain (2 calls) the callCount assertions below
            // assume — flaky depending on how fast NWPathMonitor's queue
            // schedules its first update relative to this test.
            networkChecker: MockNetworkChecker(online: true)
        )
        // Generous budget relative to the near-instant provider failures
        // below, so the retry gate is not the thing under test here.
        let service = ConversationService(aiRouter: router, timeoutSeconds: 5.0)

        await #expect(throws: AIError.self) {
            try await service.sendMessage("hello", history: [], jlptLevel: JLPTLevel.n5)
        }

        #expect(provider.callCount == 4)
    }

    @Test("A first attempt that already used the time budget skips the retry")
    func slowFirstAttemptSkipsRetry() async {
        let provider = RetryCountingAIProvider(
            tier: .gemini,
            delay: .milliseconds(200),
            errorToThrow: .timeout(.gemini)
        )
        let unavailable = MockConversationAIProvider(available: false)
        let router = AIRouterService(
            onDeviceProvider: provider,
            geminiProvider: provider,
            claudeProvider: unavailable,
            localGPUProvider: unavailable,
            // See the matching comment in `fastFailureStillRetries` above —
            // without this, the real `NWPathNetworkChecker()` default can
            // report offline on its first (pre-callback) read and collapse
            // the fallback chain to on-device-only.
            networkChecker: MockNetworkChecker(online: true)
        )
        // 50ms budget against ~400ms for the first attempt alone (two
        // 200ms provider calls) -- comfortably exceeded, so the retry must
        // be skipped rather than doubling the wait to ~800ms.
        let service = ConversationService(aiRouter: router, timeoutSeconds: 0.05)

        await #expect(throws: AIError.self) {
            try await service.sendMessage("hello", history: [], jlptLevel: JLPTLevel.n5)
        }

        #expect(provider.callCount == 2)
    }
}
