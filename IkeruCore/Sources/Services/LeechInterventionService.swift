import Foundation
import os

// MARK: - LeechContentContext

/// Pre-fetched, same-level (and adjacent-level) content bundle entries used
/// to source real distractors for a leech quiz. `ContentRepository` is async
/// and `LeechInterventionService` is a synchronous pure-function service, so
/// callers fetch the relevant slices once (see the `contentRepository:`
/// overload of `generateIntervention` below) and pass them in here.
///
/// Defaults to empty arrays so existing call sites — and older tests written
/// before this context existed — keep compiling and fall back to the
/// hand-written generic distractors.
public struct LeechContentContext: Sendable {
    public let sameLevelKanji: [Kanji]
    public let adjacentLevelKanji: [Kanji]
    public let sameLevelVocabulary: [Vocabulary]
    public let adjacentLevelVocabulary: [Vocabulary]
    public let sameLevelGrammar: [GrammarPoint]
    public let adjacentLevelGrammar: [GrammarPoint]

    public init(
        sameLevelKanji: [Kanji] = [],
        adjacentLevelKanji: [Kanji] = [],
        sameLevelVocabulary: [Vocabulary] = [],
        adjacentLevelVocabulary: [Vocabulary] = [],
        sameLevelGrammar: [GrammarPoint] = [],
        adjacentLevelGrammar: [GrammarPoint] = []
    ) {
        self.sameLevelKanji = sameLevelKanji
        self.adjacentLevelKanji = adjacentLevelKanji
        self.sameLevelVocabulary = sameLevelVocabulary
        self.adjacentLevelVocabulary = adjacentLevelVocabulary
        self.sameLevelGrammar = sameLevelGrammar
        self.adjacentLevelGrammar = adjacentLevelGrammar
    }

    /// No bundle content available — quiz distractors fall back to the
    /// hand-written generic pools.
    public static let empty = LeechContentContext()
}

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
    ///   - contentContext: Pre-fetched same-level (and adjacent-level) content
    ///     bundle entries used to source real quiz distractors. Defaults to
    ///     `.empty`, which falls back to the hand-written generic distractors
    ///     — safe for callers that haven't wired a `ContentRepository` yet.
    /// - Returns: A `LeechIntervention` with message, mnemonic, and quiz.
    public static func generateIntervention(
        card: CardDTO,
        confusionPattern: ConfusionPattern,
        contentContext: LeechContentContext = .empty
    ) -> LeechIntervention {
        let mnemonic = generateMnemonic(card: card, confusion: confusionPattern)
        let quizTag = generateQuizTag(card: card, confusion: confusionPattern, context: contentContext)
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

    /// Async convenience overload that fetches same-level and adjacent-level
    /// content from `ContentRepository` before generating the intervention —
    /// bridges the sync distractor-sampling core to the app's async data
    /// layer so a future call site only needs a repository and a card.
    /// - Parameters:
    ///   - card: The leech card to generate intervention for.
    ///   - confusionPattern: The detected confusion pattern.
    ///   - contentRepository: Read-only bundle repository to sample distractors from.
    /// - Returns: A `LeechIntervention` whose quiz distractors are drawn from
    ///   the card's JLPT level (padding from the adjacent level when needed).
    public static func generateIntervention(
        card: CardDTO,
        confusionPattern: ConfusionPattern,
        contentRepository: ContentRepository
    ) async -> LeechIntervention {
        let level = card.jlptLevel ?? .n5
        let adjacent = adjacentLevel(to: level)

        async let sameKanji = contentRepository.kanjiByLevel(level)
        async let adjacentKanji = contentRepository.kanjiByLevel(adjacent)
        async let sameVocabulary = contentRepository.vocabularyByLevel(level)
        async let adjacentVocabulary = contentRepository.vocabularyByLevel(adjacent)
        async let sameGrammar = contentRepository.grammarPointsByLevel(level)
        async let adjacentGrammar = contentRepository.grammarPointsByLevel(adjacent)

        let context = LeechContentContext(
            sameLevelKanji: await sameKanji,
            adjacentLevelKanji: await adjacentKanji,
            sameLevelVocabulary: await sameVocabulary,
            adjacentLevelVocabulary: await adjacentVocabulary,
            sameLevelGrammar: await sameGrammar,
            adjacentLevelGrammar: await adjacentGrammar
        )

        return generateIntervention(card: card, confusionPattern: confusionPattern, contentContext: context)
    }

    /// The neighboring JLPT level to pad distractors from when the card's own
    /// level doesn't have enough same-level entries. N5 has no easier
    /// neighbor, so it borrows from N4; every other level borrows from the
    /// next-easier (lower) level, which tends to have the largest bundle.
    static func adjacentLevel(to level: JLPTLevel) -> JLPTLevel {
        switch level {
        case .n5: .n4
        case .n4: .n5
        case .n3: .n4
        case .n2: .n3
        case .n1: .n2
        }
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
        confusion: ConfusionPattern,
        context: LeechContentContext
    ) -> String {
        let question = quizQuestion(for: card)
        let correct = card.back
        let distractors = generateDistractors(card: card, confusion: confusion, context: context)

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

    /// Generates two distractor answers for the quiz. Prefers real same-JLPT-level
    /// entries from the content bundle (via `context`), padding from the adjacent
    /// level when the same level can't supply enough, and only falling back to the
    /// hand-written generic pools when the bundle has nothing usable at all.
    private static func generateDistractors(
        card: CardDTO,
        confusion: ConfusionPattern,
        context: LeechContentContext
    ) -> (String, String) {
        switch card.type {
        case .kanji:
            return kanjiDistractors(card: card, context: context)
        case .vocabulary:
            return vocabularyDistractors(card: card, context: context)
        case .grammar:
            return grammarDistractors(card: card, context: context)
        case .listening:
            return listeningDistractors(card: card, context: context)
        }
    }

    private static func kanjiDistractors(
        card: CardDTO,
        context: LeechContentContext
    ) -> (String, String) {
        sampleDistractors(
            correctAnswer: card.back,
            sameLevel: context.sameLevelKanji.compactMap(\.meanings.first),
            adjacentLevel: context.adjacentLevelKanji.compactMap(\.meanings.first),
            fallback: fallbackKanjiMeanings(for: card.back),
            seedKey: "\(card.front)|\(card.back)"
        )
    }

    /// Hand-written meaning pool retained as the last-resort fallback for
    /// common basic kanji when the content bundle has no same/adjacent-level
    /// entries at all (e.g. in unit tests that don't inject a context).
    private static func fallbackKanjiMeanings(for meaning: String) -> [String] {
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

        return meaningPool[meaning.lowercased()] ?? ["not this meaning", "something else"]
    }

    private static func vocabularyDistractors(
        card: CardDTO,
        context: LeechContentContext
    ) -> (String, String) {
        sampleDistractors(
            correctAnswer: card.back,
            sameLevel: context.sameLevelVocabulary.map(\.meaning),
            adjacentLevel: context.adjacentLevelVocabulary.map(\.meaning),
            fallback: ["opposite meaning", "similar but different"],
            seedKey: "\(card.front)|\(card.back)"
        )
    }

    private static func grammarDistractors(
        card: CardDTO,
        context: LeechContentContext
    ) -> (String, String) {
        sampleDistractors(
            correctAnswer: card.back,
            sameLevel: context.sameLevelGrammar.map(\.title),
            adjacentLevel: context.adjacentLevelGrammar.map(\.title),
            fallback: ["connects clauses", "marks topic"],
            seedKey: "\(card.front)|\(card.back)"
        )
    }

    /// Listening cards quiz the meaning of what was heard, so they draw from
    /// the same vocabulary pool as `vocabularyDistractors` — the bundle has
    /// no separate "listening" content table.
    private static func listeningDistractors(
        card: CardDTO,
        context: LeechContentContext
    ) -> (String, String) {
        sampleDistractors(
            correctAnswer: card.back,
            sameLevel: context.sameLevelVocabulary.map(\.meaning),
            adjacentLevel: context.adjacentLevelVocabulary.map(\.meaning),
            fallback: ["similar sound", "different word"],
            seedKey: "\(card.front)|\(card.back)"
        )
    }

    // MARK: - Distractor Sampling

    /// Deterministically samples two distractors, preferring `sameLevel`
    /// candidates, padding from `adjacentLevel` when there aren't enough, and
    /// falling back to hand-written `fallback` strings only if the bundle
    /// truly can't supply two distinct, non-empty answers. Never crashes and
    /// never repeats `correctAnswer` (case-insensitive comparison).
    ///
    /// Sampling is deterministic: the same inputs always produce the same
    /// pair, via a seeded generator keyed on `seedKey` (typically the card's
    /// front+back) rather than `Swift`'s per-process-randomized `hashValue`,
    /// so results are reproducible across test runs and processes.
    static func sampleDistractors(
        correctAnswer: String,
        sameLevel: [String],
        adjacentLevel: [String],
        fallback: [String],
        seedKey: String
    ) -> (String, String) {
        let normalizedCorrect = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var candidates = uniqueNonEmpty(sameLevel, excluding: normalizedCorrect)
        if candidates.count < 2 {
            let existing = Set(candidates.map { $0.lowercased() })
            let padding = uniqueNonEmpty(adjacentLevel, excluding: normalizedCorrect)
                .filter { !existing.contains($0.lowercased()) }
            candidates.append(contentsOf: padding)
        }

        var generator = DeterministicGenerator(seed: seedKey)
        candidates.shuffle(using: &generator)

        if candidates.count < 2 {
            let existing = Set(candidates.map { $0.lowercased() })
            let fallbackCandidates = uniqueNonEmpty(fallback, excluding: normalizedCorrect)
                .filter { !existing.contains($0.lowercased()) }
            candidates.append(contentsOf: fallbackCandidates)
        }

        // Guarantees a populated tuple even if every pool above was empty —
        // should be unreachable in practice given the non-empty hand-written
        // fallback pools, but a quiz tag must never crash.
        let first = candidates.first ?? "distractor A"
        let second = candidates.count > 1 ? candidates[1] : "distractor B"
        return (first, second)
    }

    /// Trims, drops empties, drops anything matching `correct`
    /// (case-insensitive), and dedupes case-insensitively while preserving
    /// first-seen order.
    private static func uniqueNonEmpty(_ values: [String], excluding correct: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard key != correct, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
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

// MARK: - DeterministicGenerator

/// A seeded, process-independent pseudo-random generator (xorshift64*),
/// keyed via an FNV-1a hash of a string seed. Swift's `String.hashValue` is
/// randomized per process launch (for hash-flooding resistance), which would
/// make distractor sampling non-reproducible across test runs — this type
/// exists specifically to avoid that.
struct DeterministicGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        let hashed = Self.fnv1aHash(seed)
        // xorshift64* requires a non-zero state.
        state = hashed == 0 ? 0x9E3779B97F4A7C15 : hashed
    }

    private static func fnv1aHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
