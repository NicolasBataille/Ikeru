import Foundation

// MARK: - ReadingPassage

/// A graded reading passage composed of sentences with annotated words.
/// Used for comprehensible input (i+1) reading exercises.
public struct ReadingPassage: Sendable, Identifiable, Equatable {

    /// Unique identifier for the passage.
    public let id: UUID

    /// Title of the reading passage.
    public let title: String

    /// Raw content of the passage (full text).
    public let content: String

    /// JLPT level this passage is graded at.
    public let jlptLevel: JLPTLevel

    /// Sentences that compose the passage, with word-level annotations.
    public let sentences: [PassageSentence]

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        jlptLevel: JLPTLevel,
        sentences: [PassageSentence]
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.jlptLevel = jlptLevel
        self.sentences = sentences
    }
}

// MARK: - PassageSentence

/// A single sentence within a reading passage, with Japanese text,
/// English translation, and word-level breakdown.
public struct PassageSentence: Sendable, Identifiable, Equatable {

    /// Unique identifier for the sentence.
    public let id: UUID

    /// The Japanese text of the sentence.
    public let japanese: String

    /// The English translation of the sentence.
    public let english: String

    /// Word-level breakdown with furigana and meaning annotations.
    public let words: [PassageWord]

    public init(
        id: UUID = UUID(),
        japanese: String,
        english: String,
        words: [PassageWord]
    ) {
        self.id = id
        self.japanese = japanese
        self.english = english
        self.words = words
    }
}

// MARK: - PassageWord

/// A single word within a passage sentence, annotated with reading,
/// meaning, and learner knowledge state for furigana display logic.
public struct PassageWord: Sendable, Identifiable, Equatable {

    /// Unique identifier for the word.
    public let id: UUID

    /// The word text as displayed (kanji or kana).
    public let text: String

    /// Furigana reading for the word (hiragana). Nil for pure kana words.
    public let reading: String?

    /// English meaning of the word.
    public let meaning: String

    /// Whether the learner already knows this word (determines furigana visibility).
    public let isKnown: Bool

    /// Whether the word contains kanji characters.
    public let containsKanji: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        reading: String? = nil,
        meaning: String,
        isKnown: Bool = false,
        containsKanji: Bool = false
    ) {
        self.id = id
        self.text = text
        self.reading = reading
        self.meaning = meaning
        self.isKnown = isKnown
        self.containsKanji = containsKanji
    }
}
