import Foundation
import os

// MARK: - Conversation Service

/// Manages AI conversation for the Japanese learning partner.
/// Builds prompts adapted to the learner's JLPT level and parses
/// AI responses for corrections and vocabulary hints.
public final class ConversationService: @unchecked Sendable {

    public let aiRouter: AIRouterService
    private let timeoutSeconds: TimeInterval

    public init(
        aiRouter: AIRouterService,
        timeoutSeconds: TimeInterval = 10.0
    ) {
        self.aiRouter = aiRouter
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Public API

    /// Send a message and get an AI response adapted to the learner's level.
    /// - Parameters:
    ///   - userMessage: The learner's message text.
    ///   - history: Previous conversation messages for context.
    ///   - jlptLevel: The learner's current JLPT level.
    ///   - knownVocabulary: Words the learner has already studied, as
    ///     `word(reading)` tokens. Passed as a SOFT preference: Sakura is
    ///     told to reuse them only when they fit naturally, never to force
    ///     them. Empty by default so existing callers are unaffected.
    ///   - bundleReadings: `word -> reading` lookup built from the curated
    ///     content bundle (see `ContentRepository.readingLookup(for:)`). The
    ///     AI's furigana is generated text and can be hallucinated; every
    ///     parsed vocabulary hint whose word is a known bundle word has its
    ///     reading reconciled against this map (bundle wins) via
    ///     `ReadingValidator`. Empty by default so existing callers are
    ///     unaffected.
    /// - Returns: A ConversationMessage from the assistant.
    @MainActor
    public func sendMessage(
        _ userMessage: String,
        history: [ConversationMessage],
        jlptLevel: JLPTLevel,
        knownVocabulary: [String] = [],
        bundleReadings: [String: String] = [:]
    ) async throws -> ConversationMessage {
        let prompt = buildPrompt(
            userMessage: userMessage,
            history: history,
            jlptLevel: jlptLevel,
            knownVocabulary: knownVocabulary
        )

        let response = try await aiRouter.generate(prompt: prompt)

        Logger.ai.info("Conversation response from tier \(String(describing: response.tier)) in \(response.latencyMs)ms")

        let parsed = parseResponse(response.content)
        let reconciledHints = reconcileVocabularyHints(parsed.vocabularyHints, against: bundleReadings)

        return ConversationMessage(
            role: .assistant,
            content: parsed.content,
            corrections: parsed.corrections,
            vocabularyHints: reconciledHints
        )
    }

    /// Reconciles each parsed vocabulary hint's reading against the content
    /// bundle via `ReadingValidator`, logging once per correction so
    /// hallucinated readings are traceable in the console.
    private func reconcileVocabularyHints(
        _ hints: [VocabularyHint],
        against bundleReadings: [String: String]
    ) -> [VocabularyHint] {
        hints.map { hint in
            let reconciled = ReadingValidator.reconcile(hint, against: bundleReadings)
            if reconciled.corrected {
                Logger.ai.info(
                    "Corrected AI reading for \(hint.word): \(hint.reading) -> \(reconciled.hint.reading)"
                )
            }
            return reconciled.hint
        }
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(for level: JLPTLevel, knownVocabulary: [String] = []) -> String {
        let levelGuidance = levelSpecificGuidance(for: level)
        let knownVocabSection = knownVocabularySection(knownVocabulary)

        return """
        You are a friendly Japanese conversation partner for a language learner.
        Your name is Sakura (さくら). You are patient, encouraging, and helpful.

        LEARNER LEVEL: \(level.displayName) — \(level.complexityDescription)

        RULES:
        1. Respond bilingually. Write Japanese first, then add an inline translation \
        in the learner's language inside parentheses on the SAME line.
           Example: 今日(きょう)は友達(ともだち)と映画(えいが)を見(み)ました。(Today I watched a movie with a friend.)
        2. Detect the learner's language from their messages (English, French, etc.) and \
        use THAT language for inline translations. If they write in French, translate into French.
        3. \(levelGuidance)
        4. ALWAYS annotate EVERY kanji with its reading in the format 漢字(かんじ). \
        Never skip furigana for any kanji, regardless of the learner's level. This is critical \
        because the app uses these annotations to display pronunciation guides.
        5. When the learner makes a grammar or vocabulary mistake, gently correct it.
           Format corrections as: [CORRECTION: original → corrected | explanation]
        6. Naturally introduce useful vocabulary related to the topic.
           Format hints as: [VOCAB: word(reading) = meaning]
        7. Keep responses concise: 2-3 sentences typical.
        8. Be warm and conversational — use appropriate casual/polite speech for the level.
        9. Ask follow-up questions to keep the conversation going.
        10. Encourage the learner to try responding in Japanese, even partially.

        \(knownVocabSection)RESPONSE FORMAT:
        Write your conversational response first (Japanese with inline translations), \
        then any corrections and vocab on separate lines.

        EXAMPLE RESPONSE for a French-speaking N5 learner who said "Bonjour":
        こんにちは！元気(げんき)ですか？(Bonjour ! Comment vas-tu ?)
        今日(きょう)は何(なに)をしましたか？(Qu'as-tu fait aujourd'hui ?)
        """
    }

    /// Builds an optional, soft-preference vocabulary block for the system
    /// prompt. Returns an empty string when the learner has no studied words
    /// (so the prompt is unchanged). When present, it lists the words and
    /// explicitly frames them as a gentle preference — Sakura must reuse them
    /// only when they fit naturally and must never force or distort the
    /// conversation to include them. Returns a trailing blank line so it slots
    /// cleanly before the RESPONSE FORMAT section.
    private func knownVocabularySection(_ knownVocabulary: [String]) -> String {
        guard !knownVocabulary.isEmpty else { return "" }
        return """
        WORDS THE LEARNER ALREADY KNOWS (\(knownVocabulary.count)): \(knownVocabulary.joined(separator: ", ")).
        When one of these fits the conversation NATURALLY, prefer reusing it — it helps the learner \
        consolidate what they have studied. This is a SOFT preference, never a requirement: do NOT force \
        these words in, do NOT distort a sentence or steer the topic just to use one. If none of them fit \
        naturally, simply ignore this list.

        """
    }

    private func levelSpecificGuidance(for level: JLPTLevel) -> String {
        switch level {
        case .n5:
            return """
            Use only basic hiragana/katakana and the simplest kanji (数字, 日, 月, etc.). \
            Use です/ます form exclusively. Very short sentences.
            """
        case .n4:
            return """
            Use N5-N4 kanji. Use です/ます form primarily. Simple compound sentences allowed.
            """
        case .n3:
            return """
            Use kanji up to N3 level freely. \
            Mix polite and casual forms. Natural mid-length sentences.
            """
        case .n2:
            return """
            Use kanji up to N2 level freely. \
            Use natural speech patterns including casual contractions. Complex sentences OK.
            """
        case .n1:
            return """
            Use any kanji naturally. \
            Speak near-natively with idioms, nuance, and sophisticated grammar.
            """
        }
    }

    // MARK: - Prompt Building

    /// Number of most-recent history turns forwarded to the provider. Bounds
    /// token use on long conversations. Mirrors the previous flattened cap.
    private static let maxHistoryTurns = 20

    /// Assemble the `AIPrompt` for a turn as a real ordered multi-turn
    /// conversation. Prior turns become `AIMessage` values (oldest first,
    /// capped to `maxHistoryTurns`) and `userMessage` is carried as the latest
    /// user turn, so the provider receives system + prior user/assistant turns
    /// + new user message instead of one flattened string.
    ///
    /// The app view model appends the new user bubble to its `messages` before
    /// calling, so `history` typically already ends with a `.user` turn equal
    /// to `userMessage`. That trailing duplicate is dropped here so the latest
    /// user message appears exactly once (as the final turn of `prompt.messages`).
    ///
    /// `internal` rather than `private` so it can be unit-tested without the
    /// network — pinning the multi-turn shape end to end.
    func buildPrompt(
        userMessage: String,
        history: [ConversationMessage],
        jlptLevel: JLPTLevel,
        knownVocabulary: [String] = []
    ) -> AIPrompt {
        let systemPrompt = buildSystemPrompt(for: jlptLevel, knownVocabulary: knownVocabulary)

        var priorTurns = history
            .suffix(Self.maxHistoryTurns)
            .compactMap { message -> AIMessage? in
                // Exhaustive over MessageRole so a future `.system` history turn
                // is never silently relabelled `assistant` and replayed to the AI
                // as if Sakura had said it. System content lives in the system
                // prompt, so any `.system` turn in the transcript is dropped here.
                switch message.role {
                case .user: return AIMessage(role: .user, text: message.content)
                case .assistant: return AIMessage(role: .assistant, text: message.content)
                case .system: return nil
                }
            }

        // Avoid duplicating the latest user message when the caller already
        // included it in `history`.
        if let last = priorTurns.last, last.role == .user, last.text == userMessage {
            priorTurns.removeLast()
        }

        return AIPrompt(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            history: priorTurns,
            context: ["jlpt_level": jlptLevel.rawValue],
            complexity: .medium
        )
    }

    // MARK: - Response Parsing

    private struct ParsedResponse {
        let content: String
        let corrections: [Correction]
        let vocabularyHints: [VocabularyHint]
    }

    /// Delegates to `ChatMarkerParser` for the tolerant marker parsing
    /// itself; this method just adapts its result into the service's own
    /// `ParsedResponse` shape.
    private func parseResponse(_ text: String) -> ParsedResponse {
        let result = ChatMarkerParser.parse(text)
        return ParsedResponse(
            content: result.content,
            corrections: result.corrections,
            vocabularyHints: result.vocabularyHints
        )
    }
}
