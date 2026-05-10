import Foundation
import SwiftData

/// A single "term of the day" picked for a learner.
///
/// One row per calendar day (normalised to start-of-day in the local
/// calendar). The term's content (word, reading, meaning, description,
/// pronunciation hint) is captured at selection time so that the
/// presentation is stable even if the underlying catalog changes later.
@Model
public final class DailyTerm {

    /// Stable identifier for this row.
    public var id: UUID

    /// Day this term was scheduled for, normalised to local start-of-day.
    @Attribute(.unique)
    public var date: Date

    /// The Japanese word or expression (e.g. 木漏れ日).
    public var word: String

    /// Hiragana reading of the word (e.g. こもれび).
    public var reading: String

    /// Romaji or pronunciation hint (e.g. ko-mo-re-bi).
    public var pronunciation: String

    /// English (or learner-language) meaning of the word.
    public var meaning: String

    /// A friendly, date-aware description of the term.
    public var caption: String

    /// Raw value storage for JLPTLevel.
    public var jlptLevelRawValue: String?

    /// Estimated JLPT level for the term, if known.
    public var jlptLevel: JLPTLevel? {
        get {
            guard let raw = jlptLevelRawValue else { return nil }
            return JLPTLevel(rawValue: raw)
        }
        set { jlptLevelRawValue = newValue?.rawValue }
    }

    /// Date the user opened the reveal popup for this term. Nil if missed.
    public var revealedAt: Date?

    /// Whether the user added this term to their personal dictionary.
    public var addedToDictionary: Bool

    /// Date the term row was created.
    public var createdAt: Date

    public init(
        date: Date,
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        caption: String,
        jlptLevel: JLPTLevel? = nil,
        revealedAt: Date? = nil,
        addedToDictionary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.date = date
        self.word = word
        self.reading = reading
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.caption = caption
        self.jlptLevelRawValue = jlptLevel?.rawValue
        self.revealedAt = revealedAt
        self.addedToDictionary = addedToDictionary
        self.createdAt = createdAt
    }
}
