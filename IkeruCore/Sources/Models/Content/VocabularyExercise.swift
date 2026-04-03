import Foundation

// MARK: - ExampleSentence

/// A bilingual example sentence with reading annotation.
public struct ExampleSentence: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// Japanese sentence text.
    public let japanese: String

    /// Hiragana reading of the Japanese sentence.
    public let reading: String

    /// English translation of the sentence.
    public let english: String

    public init(
        id: UUID = UUID(),
        japanese: String,
        reading: String,
        english: String
    ) {
        self.id = id
        self.japanese = japanese
        self.reading = reading
        self.english = english
    }
}

// MARK: - VocabularyExercise

/// An enriched vocabulary item used in vocabulary study exercises.
/// Extends the base `Vocabulary` model with part of speech and structured example sentences.
public struct VocabularyExercise: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// Japanese word (e.g., "食べる").
    public let word: String

    /// Hiragana reading (e.g., "たべる").
    public let reading: String

    /// English meaning.
    public let meaning: String

    /// Part of speech (e.g., "verb", "noun", "adjective").
    public let partOfSpeech: String

    /// JLPT level classification.
    public let jlptLevel: JLPTLevel

    /// Bilingual example sentences demonstrating usage.
    public let exampleSentences: [ExampleSentence]

    public init(
        id: UUID = UUID(),
        word: String,
        reading: String,
        meaning: String,
        partOfSpeech: String,
        jlptLevel: JLPTLevel,
        exampleSentences: [ExampleSentence]
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.meaning = meaning
        self.partOfSpeech = partOfSpeech
        self.jlptLevel = jlptLevel
        self.exampleSentences = exampleSentences
    }
}
