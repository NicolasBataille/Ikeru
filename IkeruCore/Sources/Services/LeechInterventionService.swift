import Foundation
import os

// MARK: - LeechIntervention

/// The generated intervention content for a leech card.
public struct LeechIntervention: Sendable {
    /// The companion's message text (may contain [KANJI:X] and [QUIZ:...] tags).
    public let message: String

    /// The detected confusion pattern.
    public let confusionPattern: ConfusionPattern

    /// A short mnemonic suggestion for the card.
    public let mnemonic: String

    /// The embedded quiz tag for inline practice.
    public let quizTag: String

    public init(
        message: String,
        confusionPattern: ConfusionPattern,
        mnemonic: String,
        quizTag: String
    ) {
        self.message = message
        self.confusionPattern = confusionPattern
        self.mnemonic = mnemonic
        self.quizTag = quizTag
    }
}

// MARK: - LeechInterventionService

/// Generates personalized intervention content for leech cards.
///
/// All content is built locally from card data — no paid APIs.
/// Mnemonics use radical decomposition and common learning strategies.
/// Mini practice exercises are embedded as quiz tags for the chat.
public enum LeechInterventionService {

    // MARK: - Intervention Generation

    /// Generates a complete intervention for a leech card.
    ///
    /// - Parameters:
    ///   - card: The leech card to generate intervention for.
    ///   - confusionPattern: The detected confusion pattern.
    /// - Returns: A `LeechIntervention` with message, mnemonic, and quiz.
    public static func generateIntervention(
        card: CardDTO,
        confusionPattern: ConfusionPattern
    ) -> LeechIntervention {
        let mnemonic = generateMnemonic(card: card, confusion: confusionPattern)
        let quizTag = generateQuizTag(card: card, confusion: confusionPattern)
        let message = buildInterventionMessage(
            card: card,
            confusion: confusionPattern,
            mnemonic: mnemonic,
            quizTag: quizTag
        )

        Logger.srs.info("Generated leech intervention for: \(card.front)")

        return LeechIntervention(
            message: message,
            confusionPattern: confusionPattern,
            mnemonic: mnemonic,
            quizTag: quizTag
        )
    }

    // MARK: - Mnemonic Generation

    /// Generates a local mnemonic from card content.
    /// Uses radical decomposition for kanji, contextual hints for vocabulary.
    private static func generateMnemonic(
        card: CardDTO,
        confusion: ConfusionPattern
    ) -> String {
        switch card.type {
        case .kanji:
            return generateKanjiMnemonic(card: card, confusion: confusion)
        case .vocabulary:
            return generateVocabularyMnemonic(card: card)
        case .grammar:
            return generateGrammarMnemonic(card: card)
        case .listening:
            return generateListeningMnemonic(card: card)
        }
    }

    private static func generateKanjiMnemonic(
        card: CardDTO,
        confusion: ConfusionPattern
    ) -> String {
        let character = card.front
        let meaning = card.back

        switch confusion.type {
        case .visuallySimilar:
            return "Focus on the unique part of \(character) that makes it different. "
                + "Remember: \(character) means \"\(meaning)\" — "
                + "picture the shape telling you this specific meaning."

        case .similarReading:
            return "The reading for \(character) (\(meaning)) sounds similar to another kanji. "
                + "Try associating the meaning \"\(meaning)\" with a vivid image."

        case .relatedMeaning, .generalDifficulty:
            return "Think of \(character) as a picture: "
                + "the shape itself tells the story of \"\(meaning)\". "
                + "Break it into parts and build a mini-scene."
        }
    }

    private static func generateVocabularyMnemonic(card: CardDTO) -> String {
        "Connect \(card.front) (\(card.back)) to a situation you know. "
            + "Imagine using this word in a real conversation — "
            + "the more vivid the scene, the better it sticks."
    }

    private static func generateGrammarMnemonic(card: CardDTO) -> String {
        "Think of \(card.front) as a sentence building block. "
            + "Try saying a sentence out loud using this pattern."
    }

    private static func generateListeningMnemonic(card: CardDTO) -> String {
        "Listen for the key sounds in \(card.front). "
            + "Try to hear each syllable clearly, then say it yourself."
    }

    // MARK: - Quiz Tag Generation

    /// Generates a [QUIZ:...] tag for inline practice in the chat.
    ///
    /// Format: [QUIZ:question|correct|wrong1|wrong2]
    private static func generateQuizTag(
        card: CardDTO,
        confusion: ConfusionPattern
    ) -> String {
        let question = quizQuestion(for: card)
        let correct = card.back
        let distractors = generateDistractors(card: card, confusion: confusion)

        return "[QUIZ:\(question)|\(correct)|\(distractors.0)|\(distractors.1)]"
    }

    private static func quizQuestion(for card: CardDTO) -> String {
        switch card.type {
        case .kanji:
            return "What does \(card.front) mean?"
        case .vocabulary:
            return "What does \(card.front) mean?"
        case .grammar:
            return "What is the function of \(card.front)?"
        case .listening:
            return "What did you hear?"
        }
    }

    /// Generates two distractor answers for the quiz.
    private static func generateDistractors(
        card: CardDTO,
        confusion: ConfusionPattern
    ) -> (String, String) {
        // Use confusion-aware distractors when possible
        switch card.type {
        case .kanji:
            return kanjiDistractors(card: card, confusion: confusion)
        case .vocabulary:
            return vocabularyDistractors(card: card)
        case .grammar:
            return ("connects clauses", "marks topic")
        case .listening:
            return ("similar sound", "different word")
        }
    }

    private static func kanjiDistractors(
        card: CardDTO,
        confusion: ConfusionPattern
    ) -> (String, String) {
        // Common meaning distractors for basic kanji
        let meaningPool: [String: [String]] = [
            "day/sun": ["eye", "moon"],
            "eye": ["day/sun", "ear"],
            "moon": ["day/sun", "month"],
            "person": ["enter", "big"],
            "enter": ["person", "eight"],
            "big": ["dog", "heaven"],
            "dog": ["big", "large"],
            "earth": ["warrior", "king"],
            "warrior": ["earth", "samurai"],
            "tree": ["forest", "grove"],
            "mountain": ["river", "stone"],
            "river": ["mountain", "water"],
            "water": ["fire", "ice"],
            "fire": ["water", "light"],
        ]

        if let distractors = meaningPool[card.back.lowercased()], distractors.count >= 2 {
            return (distractors[0], distractors[1])
        }

        // Fallback distractors
        return ("not this meaning", "something else")
    }

    private static func vocabularyDistractors(card: CardDTO) -> (String, String) {
        ("opposite meaning", "similar but different")
    }

    // MARK: - Message Building

    /// Builds the full companion message with inline content tags.
    private static func buildInterventionMessage(
        card: CardDTO,
        confusion: ConfusionPattern,
        mnemonic: String,
        quizTag: String
    ) -> String {
        let kanjiTag = card.type == .kanji ? "[KANJI:\(card.front)]" : ""
        let separator = kanjiTag.isEmpty ? "" : "\n\n"

        let parts = [
            "I noticed you're having trouble with \(card.front)! Let me help.",
            "",
            confusion.description,
            separator + kanjiTag,
            "",
            "Here's a tip: \(mnemonic)",
            "",
            "Let's do a quick practice:",
            quizTag,
        ]

        return parts.joined(separator: "\n")
    }
}
