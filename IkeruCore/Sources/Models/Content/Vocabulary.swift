import Foundation

/// A vocabulary item with its reading, meaning, and related kanji.
/// This is a plain value type for static content from the SQLite bundle.
public struct Vocabulary: Sendable, Codable, Identifiable, Equatable {

    /// Unique identifier for the vocabulary item.
    public let id: Int

    /// The word in Japanese (may contain kanji).
    public let word: String

    /// Hiragana reading of the word.
    public let reading: String

    /// English meaning.
    public let meaning: String

    /// The primary kanji character this word relates to. Nil for kana-only words.
    public let kanjiCharacter: String?

    /// JLPT level classification.
    public let jlptLevel: JLPTLevel

    /// Example sentences using this word.
    public let exampleSentences: [String]

    public init(
        id: Int,
        word: String,
        reading: String,
        meaning: String,
        kanjiCharacter: String?,
        jlptLevel: JLPTLevel,
        exampleSentences: [String]
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.meaning = meaning
        self.kanjiCharacter = kanjiCharacter
        self.jlptLevel = jlptLevel
        self.exampleSentences = exampleSentences
    }
}
