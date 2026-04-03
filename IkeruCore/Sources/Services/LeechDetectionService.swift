import Foundation
import os

// MARK: - LeechEvent

/// Describes a leech detection event for companion intervention.
public struct LeechEvent: Sendable {
    /// The card that was flagged as a leech.
    public let card: CardDTO

    /// The number of lapses that triggered the detection.
    public let lapseCount: Int

    /// Whether this is the first time this card has been flagged (vs. recurring leech).
    public let isNewLeech: Bool

    public init(card: CardDTO, lapseCount: Int, isNewLeech: Bool) {
        self.card = card
        self.lapseCount = lapseCount
        self.isNewLeech = isNewLeech
    }
}

// MARK: - ConfusionPattern

/// Describes a detected confusion pattern between items.
public struct ConfusionPattern: Sendable {
    /// The item the learner struggles with.
    public let target: String

    /// Description of the confusion (e.g., "You confuse 食 with 飲").
    public let description: String

    /// The type of confusion detected.
    public let type: ConfusionType

    public init(target: String, description: String, type: ConfusionType) {
        self.target = target
        self.description = description
        self.type = type
    }
}

/// Types of confusion patterns detected in leech cards.
public enum ConfusionType: String, Sendable {
    /// Visually similar kanji characters.
    case visuallySimilar
    /// Characters with similar or overlapping readings.
    case similarReading
    /// Characters with related or overlapping meanings.
    case relatedMeaning
    /// High lapse count but no specific confusion identified.
    case generalDifficulty
}

// MARK: - LeechDetectionService

/// Monitors card review outcomes and detects leech cards.
///
/// A leech is a card that has been failed (grade == .again) at or above
/// the leech threshold. This service provides pure-function detection
/// and confusion pattern analysis.
public enum LeechDetectionService {

    /// Default leech threshold — a card is flagged after this many lapses.
    public static let defaultThreshold = 3

    // MARK: - Detection

    /// Checks whether a card has become a leech after a review.
    ///
    /// - Parameters:
    ///   - card: The card's state before grading.
    ///   - grade: The grade applied.
    ///   - threshold: Lapse count that triggers leech status (default 3).
    /// - Returns: A `LeechEvent` if the card just crossed the threshold, nil otherwise.
    public static func checkForLeech(
        card: CardDTO,
        grade: Grade,
        threshold: Int = defaultThreshold
    ) -> LeechEvent? {
        guard grade == .again else { return nil }

        // The lapse count after this review (card.lapseCount reflects pre-grade state;
        // FSRS increments lapses on .again, so the new count is lapseCount + 1).
        let newLapseCount = card.lapseCount + 1

        guard newLapseCount >= threshold else { return nil }

        let isNewLeech = !card.leechFlag
        Logger.srs.info(
            "Leech detected: \(card.front), lapses=\(newLapseCount), isNew=\(isNewLeech)"
        )

        return LeechEvent(
            card: card,
            lapseCount: newLapseCount,
            isNewLeech: isNewLeech
        )
    }

    // MARK: - Confusion Analysis

    /// Analyzes a leech card to identify likely confusion patterns.
    ///
    /// Uses the card's front/back content and type to infer what
    /// the learner is struggling with. This is a heuristic analysis
    /// based on common Japanese learning pitfalls.
    ///
    /// - Parameter card: The leech card to analyze.
    /// - Returns: A confusion pattern describing the likely issue.
    public static func analyzeConfusion(card: CardDTO) -> ConfusionPattern {
        switch card.type {
        case .kanji:
            return analyzeKanjiConfusion(card: card)
        case .vocabulary:
            return analyzeVocabularyConfusion(card: card)
        case .grammar:
            return analyzeGrammarConfusion(card: card)
        case .listening:
            return analyzeListeningConfusion(card: card)
        }
    }

    // MARK: - Private Analysis

    private static func analyzeKanjiConfusion(card: CardDTO) -> ConfusionPattern {
        let character = card.front

        // Check for known visually-similar kanji pairs
        if let similarPair = findVisuallySimilarKanji(character) {
            return ConfusionPattern(
                target: character,
                description: "You may be confusing \(character) with \(similarPair) — they look similar but have different meanings.",
                type: .visuallySimilar
            )
        }

        // Default: general difficulty
        return ConfusionPattern(
            target: character,
            description: "This kanji \(character) (\(card.back)) is tricky. Let's break it down with its radicals.",
            type: .generalDifficulty
        )
    }

    private static func analyzeVocabularyConfusion(card: CardDTO) -> ConfusionPattern {
        let word = card.front

        return ConfusionPattern(
            target: word,
            description: "The word \(word) (\(card.back)) keeps slipping away. Let's reinforce it with context.",
            type: .generalDifficulty
        )
    }

    private static func analyzeGrammarConfusion(card: CardDTO) -> ConfusionPattern {
        ConfusionPattern(
            target: card.front,
            description: "This grammar pattern is challenging. Let's practice it in a sentence.",
            type: .generalDifficulty
        )
    }

    private static func analyzeListeningConfusion(card: CardDTO) -> ConfusionPattern {
        ConfusionPattern(
            target: card.front,
            description: "This listening item is difficult to catch. Let's slow it down and practice.",
            type: .generalDifficulty
        )
    }

    // MARK: - Visually Similar Kanji Database

    /// Returns a visually similar kanji for the given character, if known.
    /// This is a static lookup of common confusion pairs.
    private static func findVisuallySimilarKanji(_ character: String) -> String? {
        let similarPairs: [String: String] = [
            "日": "目", "目": "日",
            "人": "入", "入": "人",
            "大": "太", "太": "大",
            "犬": "太",
            "土": "士", "士": "土",
            "未": "末", "末": "未",
            "刀": "力", "力": "刀",
            "千": "干", "干": "千",
            "夫": "天", "天": "夫",
            "牛": "午", "午": "牛",
            "田": "由", "由": "田",
            "白": "自", "自": "白",
            "食": "飲", "飲": "食",
            "見": "貝", "貝": "見",
            "右": "左", "左": "右",
            "上": "下", "下": "上",
            "休": "体", "体": "休",
            "持": "待", "待": "持",
            "特": "持",
            "間": "問", "問": "間",
        ]
        return similarPairs[character]
    }
}
