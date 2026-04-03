import Foundation

// MARK: - ShadowingDifficulty

/// Progressive difficulty levels for shadowing exercises.
/// Maps from simple single words to full conversation speed.
public enum ShadowingDifficulty: String, Codable, CaseIterable, Sendable, Comparable {
    case word
    case shortPhrase
    case sentence
    case conversation

    private var sortOrder: Int {
        switch self {
        case .word: 0
        case .shortPhrase: 1
        case .sentence: 2
        case .conversation: 3
        }
    }

    public static func < (lhs: ShadowingDifficulty, rhs: ShadowingDifficulty) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// Human-readable label for display in the UI.
    public var displayLabel: String {
        switch self {
        case .word: "Word"
        case .shortPhrase: "Short Phrase"
        case .sentence: "Sentence"
        case .conversation: "Conversation"
        }
    }
}

// MARK: - ShadowingMode

/// The mode of a shadowing exercise.
public enum ShadowingMode: String, Codable, CaseIterable, Sendable {
    /// Listen first, then repeat after playback finishes.
    case listenAndRepeat = "listen_and_repeat"

    /// Speak simultaneously with the audio (advanced).
    case shadowing

    /// Human-readable label for display in the UI.
    public var displayLabel: String {
        switch self {
        case .listenAndRepeat: "Listen & Repeat"
        case .shadowing: "Shadowing"
        }
    }
}

// MARK: - ShadowingExercise

/// A single shadowing exercise with target text, reading, and metadata.
public struct ShadowingExercise: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// The Japanese text to speak (may include kanji).
    public let targetText: String

    /// The hiragana reading of the target text.
    public let reading: String

    /// The English translation of the target text.
    public let translation: String

    /// The difficulty level of the exercise.
    public let difficulty: ShadowingDifficulty

    /// The exercise mode (listen-and-repeat or simultaneous shadowing).
    public let exerciseMode: ShadowingMode

    /// The JLPT level of the exercise content.
    public let jlptLevel: JLPTLevel

    public init(
        id: UUID = UUID(),
        targetText: String,
        reading: String,
        translation: String,
        difficulty: ShadowingDifficulty,
        exerciseMode: ShadowingMode = .listenAndRepeat,
        jlptLevel: JLPTLevel
    ) {
        self.id = id
        self.targetText = targetText
        self.reading = reading
        self.translation = translation
        self.difficulty = difficulty
        self.exerciseMode = exerciseMode
        self.jlptLevel = jlptLevel
    }
}

// MARK: - ShadowingExerciseGenerator

/// Generates shadowing exercises from vocabulary content.
public enum ShadowingExerciseGenerator {

    /// Generates a word-level shadowing exercise from a vocabulary item.
    /// - Parameters:
    ///   - item: The vocabulary item to practice.
    ///   - mode: The exercise mode (defaults to listen-and-repeat).
    /// - Returns: A shadowing exercise.
    public static func generateFromVocabulary(
        item: VocabularyItem,
        mode: ShadowingMode = .listenAndRepeat
    ) -> ShadowingExercise {
        ShadowingExercise(
            targetText: item.japanese,
            reading: item.reading,
            translation: item.meaning,
            difficulty: .word,
            exerciseMode: mode,
            jlptLevel: item.jlptLevel
        )
    }

    /// Generates exercises filtered by difficulty and JLPT level.
    /// - Parameters:
    ///   - vocabulary: The pool of vocabulary items.
    ///   - difficulty: The desired difficulty level.
    ///   - level: The JLPT level to filter by.
    ///   - mode: The exercise mode (defaults to listen-and-repeat).
    ///   - count: Maximum number of exercises to generate.
    /// - Returns: An array of shadowing exercises.
    public static func generateExercises(
        from vocabulary: [VocabularyItem],
        difficulty: ShadowingDifficulty,
        level: JLPTLevel,
        mode: ShadowingMode = .listenAndRepeat,
        count: Int = 5
    ) -> [ShadowingExercise] {
        let filtered = vocabulary.filter { $0.jlptLevel == level }
        let selected = Array(filtered.shuffled().prefix(count))

        return selected.map { item in
            ShadowingExercise(
                targetText: item.japanese,
                reading: item.reading,
                translation: item.meaning,
                difficulty: difficulty,
                exerciseMode: mode,
                jlptLevel: level
            )
        }
    }
}
