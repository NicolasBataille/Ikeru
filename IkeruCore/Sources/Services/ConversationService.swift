import Foundation
import os

// MARK: - Conversation Service

/// Manages AI conversation for the Japanese learning partner.
/// Builds prompts adapted to the learner's JLPT level and parses
/// AI responses for corrections and vocabulary hints.
public final class ConversationService: @unchecked Sendable {

    private let aiRouter: AIRouterService
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
    /// - Returns: A ConversationMessage from the assistant.
    @MainActor
    public func sendMessage(
        _ userMessage: String,
        history: [ConversationMessage],
        jlptLevel: JLPTLevel
    ) async throws -> ConversationMessage {
        let systemPrompt = buildSystemPrompt(for: jlptLevel)

        // Build combined user message with recent history context
        let contextMessage = buildContextMessage(from: history, userMessage: userMessage)

        let prompt = AIPrompt(
            systemPrompt: systemPrompt,
            userMessage: contextMessage,
            context: ["jlpt_level": jlptLevel.rawValue],
            complexity: .medium
        )

        let response = try await aiRouter.generate(prompt: prompt)

        Logger.ai.info("Conversation response from tier \(String(describing: response.tier)) in \(response.latencyMs)ms")

        let parsed = parseResponse(response.content)

        return ConversationMessage(
            role: .assistant,
            content: parsed.content,
            corrections: parsed.corrections,
            vocabularyHints: parsed.vocabularyHints
        )
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(for level: JLPTLevel) -> String {
        let levelGuidance = levelSpecificGuidance(for: level)

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

        RESPONSE FORMAT:
        Write your conversational response first (Japanese with inline translations), \
        then any corrections and vocab on separate lines.

        EXAMPLE RESPONSE for a French-speaking N5 learner who said "Bonjour":
        こんにちは！元気(げんき)ですか？(Bonjour ! Comment vas-tu ?)
        今日(きょう)は何(なに)をしましたか？(Qu'as-tu fait aujourd'hui ?)
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

    // MARK: - Message Building

    private func buildContextMessage(
        from history: [ConversationMessage],
        userMessage: String
    ) -> String {
        // Include recent history (last 20 messages) as context
        let recentHistory = history.suffix(20)

        if recentHistory.isEmpty {
            return userMessage
        }

        var context = "Previous messages:\n"
        for msg in recentHistory {
            let role = msg.role == .user ? "Learner" : "Sakura"
            context += "\(role): \(msg.content)\n"
        }
        context += "\nLearner: \(userMessage)"
        return context
    }

    // MARK: - Response Parsing

    private struct ParsedResponse {
        let content: String
        let corrections: [Correction]
        let vocabularyHints: [VocabularyHint]
    }

    private func parseResponse(_ text: String) -> ParsedResponse {
        var contentLines: [String] = []
        var corrections: [Correction] = []
        var vocabularyHints: [VocabularyHint] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let correction = parseCorrection(trimmed) {
                corrections.append(correction)
            } else if let hint = parseVocabularyHint(trimmed) {
                vocabularyHints.append(hint)
            } else if !trimmed.isEmpty {
                contentLines.append(trimmed)
            }
        }

        let content = contentLines.joined(separator: "\n")
        return ParsedResponse(
            content: content,
            corrections: corrections,
            vocabularyHints: vocabularyHints
        )
    }

    /// Parses `[CORRECTION: original → corrected | explanation]`
    private func parseCorrection(_ line: String) -> Correction? {
        guard line.hasPrefix("[CORRECTION:"), line.hasSuffix("]") else {
            return nil
        }

        let inner = String(line.dropFirst("[CORRECTION:".count).dropLast())
            .trimmingCharacters(in: .whitespaces)

        let arrowParts = inner.components(separatedBy: " → ")
        guard arrowParts.count == 2 else { return nil }

        let original = arrowParts[0].trimmingCharacters(in: .whitespaces)
        let restParts = arrowParts[1].components(separatedBy: " | ")

        let corrected = restParts[0].trimmingCharacters(in: .whitespaces)
        let explanation = restParts.count > 1
            ? restParts[1].trimmingCharacters(in: .whitespaces)
            : ""

        return Correction(
            original: original,
            corrected: corrected,
            explanation: explanation
        )
    }

    /// Parses `[VOCAB: word(reading) = meaning]`
    private func parseVocabularyHint(_ line: String) -> VocabularyHint? {
        guard line.hasPrefix("[VOCAB:"), line.hasSuffix("]") else {
            return nil
        }

        let inner = String(line.dropFirst("[VOCAB:".count).dropLast())
            .trimmingCharacters(in: .whitespaces)

        let equalParts = inner.components(separatedBy: " = ")
        guard equalParts.count == 2 else { return nil }

        let wordPart = equalParts[0].trimmingCharacters(in: .whitespaces)
        let meaning = equalParts[1].trimmingCharacters(in: .whitespaces)

        if let parenStart = wordPart.firstIndex(of: "("),
           let parenEnd = wordPart.firstIndex(of: ")") {
            let word = String(wordPart[wordPart.startIndex..<parenStart])
            let reading = String(wordPart[wordPart.index(after: parenStart)..<parenEnd])
            return VocabularyHint(word: word, reading: reading, meaning: meaning)
        }

        return VocabularyHint(word: wordPart, reading: "", meaning: meaning)
    }
}
