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

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1).
    // `deletedAt` IS written in production: `VocabularyModelActor.deleteEntry`
    // tombstones the entry (and cascades to its `encounters`) instead of
    // hard-deleting it — see `SoftDeletable`, including why a re-added word
    // gets a NEW entry rather than reviving this one. `syncedAt` is written
    // by `SyncModelActor`. `updatedAt` is bumped by the tombstone but still
    // not by ordinary field mutations — the staleness gap declared in
    // `SyncModelActor` is unchanged.

    /// Local modification clock. Defaults to the Unix epoch at the property
    /// level so the `.lightweight` V3→V4 migration can backfill existing
    /// rows without a custom stage; the initializer below sets this to
    /// `Date()` explicitly for freshly created objects.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Tombstone. Non-nil means this row was locally deleted and awaits a
    /// sync push of the deletion.
    public var deletedAt: Date?

    /// Timestamp of the last confirmed push to the sync server. `nil` means
    /// never synced.
    public var syncedAt: Date?

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
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
