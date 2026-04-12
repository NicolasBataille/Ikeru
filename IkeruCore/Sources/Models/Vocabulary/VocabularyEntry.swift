import Foundation
import SwiftData

/// A personal vocabulary entry saved by the learner.
/// Tracks FSRS scheduling state for spaced repetition drills
/// and links to encounter logs across the app.
@Model
public final class VocabularyEntry {

    /// Unique identifier for the entry.
    public var id: UUID

    /// The Japanese word (e.g. 勉強).
    public var word: String

    /// Hiragana reading (e.g. べんきょう).
    public var reading: String

    /// Translation in the user's language.
    public var meaning: String

    /// Raw value storage for JLPTLevel (used in SwiftData predicates).
    public var jlptLevelRawValue: String?

    /// Estimated JLPT level for this word.
    public var jlptLevel: JLPTLevel? {
        get {
            guard let raw = jlptLevelRawValue else { return nil }
            return JLPTLevel(rawValue: raw)
        }
        set { jlptLevelRawValue = newValue?.rawValue }
    }

    /// FSRS scheduling state.
    public var fsrsState: FSRSState

    /// Ease factor for scheduling (default 2.5).
    public var easeFactor: Double

    /// Current review interval in days.
    public var interval: Int

    /// Date when the entry is next due for review.
    public var dueDate: Date

    /// Number of times the entry has lapsed (been forgotten).
    public var lapseCount: Int

    /// Whether the user explicitly added this word to their dictionary.
    /// Words created by encounter pre-tracking have this set to false.
    public var isInDictionary: Bool = false

    /// Date when the entry was first added to the dictionary.
    public var createdAt: Date

    /// All encounter logs for this entry.
    @Relationship(deleteRule: .cascade, inverse: \VocabularyEncounter.entry)
    public var encounters: [VocabularyEncounter]?

    public init(
        word: String,
        reading: String,
        meaning: String,
        jlptLevel: JLPTLevel? = nil,
        isInDictionary: Bool = true,
        fsrsState: FSRSState = FSRSState(),
        easeFactor: Double = 2.5,
        interval: Int = 0,
        dueDate: Date = Date(),
        lapseCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.word = word
        self.reading = reading
        self.meaning = meaning
        self.jlptLevelRawValue = jlptLevel?.rawValue
        self.isInDictionary = isInDictionary
        self.fsrsState = fsrsState
        self.easeFactor = easeFactor
        self.interval = interval
        self.dueDate = dueDate
        self.lapseCount = lapseCount
        self.createdAt = createdAt
        self.encounters = []
    }
}
