import Foundation
import SwiftData

/// A learning card representing a single item to study (kanji, vocabulary, grammar, or listening).
/// Uses SwiftData @Model for persistence with FSRS scheduling state.
@Model
public final class Card {

    /// Unique identifier for the card
    public var id: UUID

    /// The front face content (question/prompt)
    public var front: String

    /// The back face content (answer)
    public var back: String

    /// Raw value storage for CardType (used in SwiftData predicates).
    public var typeRawValue: String

    /// The type of learning material this card represents.
    public var type: CardType {
        get { CardType(rawValue: typeRawValue) ?? .kanji }
        set { typeRawValue = newValue.rawValue }
    }

    /// FSRS scheduling state stored as a Codable struct
    public var fsrsState: FSRSState

    /// Ease factor for scheduling (default 2.5)
    public var easeFactor: Double

    /// Current review interval in days
    public var interval: Int

    /// Date when the card is next due for review
    public var dueDate: Date

    /// Number of times the card has lapsed (been forgotten)
    public var lapseCount: Int

    /// Whether this card is flagged as a leech (frequently forgotten)
    public var leechFlag: Bool

    /// Raw value storage for the optional JLPT level (used for SwiftData
    /// migration-safe encoding). `nil` for legacy/untagged cards.
    public var jlptLevelRawValue: String?

    /// Optional JLPT level tag — `.n5` through `.n1`, or `nil` if not
    /// tagged. Computed from `jlptLevelRawValue` so SwiftData can persist
    /// the value as a plain optional String, mirroring the `typeRawValue`
    /// pattern used elsewhere in this model.
    public var jlptLevel: JLPTLevel? {
        get {
            guard let raw = jlptLevelRawValue else { return nil }
            return JLPTLevel(rawValue: raw)
        }
        set { jlptLevelRawValue = newValue?.rawValue }
    }

    /// The user profile that owns this card
    public var profile: UserProfile?

    /// All review logs for this card
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    public var reviewLogs: [ReviewLog]?

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). Nothing
    // reads or writes these yet — no repository bumps `updatedAt` on
    // mutation, nothing sets `deletedAt`, nothing sets `syncedAt`. That
    // wiring is a later lot; this lot only adds the columns.

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
        front: String,
        back: String,
        type: CardType,
        fsrsState: FSRSState = FSRSState(),
        easeFactor: Double = 2.5,
        interval: Int = 0,
        dueDate: Date = Date(),
        lapseCount: Int = 0,
        leechFlag: Bool = false,
        jlptLevel: JLPTLevel? = nil
    ) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.typeRawValue = type.rawValue
        self.fsrsState = fsrsState
        self.easeFactor = easeFactor
        self.interval = interval
        self.dueDate = dueDate
        self.lapseCount = lapseCount
        self.leechFlag = leechFlag
        self.jlptLevelRawValue = jlptLevel?.rawValue
        self.reviewLogs = []
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
