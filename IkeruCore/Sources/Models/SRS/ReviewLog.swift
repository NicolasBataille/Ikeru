import Foundation
import SwiftData

/// A log entry recording a single review event for a card.
/// Tracks the grade given, response time, and timestamp.
///
/// Three fields — `answeredValue`, `exerciseType`, `surface` — were added in
/// `IkeruSchemaV3` (learner-telemetry lot 1, see
/// `docs/design-specs/2026-08-10-learner-telemetry-design.md` §3.1/3.2) so a
/// confusion pair (e.g. "expected シ, answered ツ") and the format/surface a
/// grade came from are no longer discarded. All three are optional — the
/// V2→V3 migration stage stays a `.lightweight` addition, and a self-graded
/// flashcard genuinely has no `answeredValue` to record.
@Model
public final class ReviewLog {

    /// Unique identifier for this review log entry
    public var id: UUID

    /// Timestamp when the review occurred
    public var timestamp: Date

    /// The card that was reviewed
    public var card: Card?

    /// Raw value storage for Grade (used in SwiftData predicates).
    public var gradeRawValue: Int

    /// The grade given during this review
    public var grade: Grade {
        get { Grade(rawValue: gradeRawValue) ?? .good }
        set { gradeRawValue = newValue.rawValue }
    }

    /// Response time in milliseconds
    public var responseTimeMs: Int

    /// The value the learner actually chose or produced, for any exercise
    /// format that offers a choice — `nil` for a self-graded flashcard (there
    /// is nothing to record; the learner graded their own recall).
    ///
    /// For the kana quiz this is the wrong-answer **character** (e.g. ツ when
    /// シ was expected), not the romaji option label — the character is what
    /// makes a confusion pair analyzable (シ vs ツ). Set on both correct and
    /// incorrect answers, so a stretch of correct answers is visible too, not
    /// just misses. Callers that can't resolve a character back from the
    /// chosen option fall back to the raw option string rather than dropping
    /// the datum — so this field's script isn't guaranteed uniform across
    /// rows (kana character vs. romaji) and a consumer must not assume one.
    public var answeredValue: String?

    /// Free-form identifier for the exercise format this grade came from —
    /// e.g. an `ExerciseType.rawValue` for the main session ("kanjiStudy",
    /// "vocabularyStudy", ...), or "kana.flashcard" / "kana.quiz" for the
    /// kana drill surface (which predates `ExerciseType` and grades kana
    /// cards outside the session's exercise pipeline). Deliberately not
    /// backed by a single shared enum: the two call sites describe genuinely
    /// different vocabularies (pedagogical skill vs. UI interaction shape),
    /// and forcing one taxonomy on both would lose information. A consumer
    /// (e.g. the telemetry export) must document the value space per prefix.
    public var exerciseType: String?

    /// Where the review was graded from: `"iphone.session"` (main SRS
    /// session), `"iphone.drill"` (kana drill flashcard/quiz), or `"watch"`
    /// (the Watch kana quiz — `WatchConnectivityManager.processWatchQuizBatch`
    /// grades each answer through the same `CardRepository.gradeCard` path
    /// as the other two surfaces, since chantier #46 / commit f020439; this
    /// doc comment used to claim nothing wrote `"watch"`, which stopped
    /// being true as of that commit — corrected 2026-08 while investigating
    /// GAP-13).
    public var surface: String?

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). `ReviewLog`
    // is append-only per spec §3 (conflict-free by construction), but it
    // still needs `updatedAt`/`syncedAt` to drive the push delta —
    // `deletedAt` is NOT decorative: a review log is tombstoned when its card
    // is (`CardModelActor.deleteCard`, or a profile deletion cascading
    // through its cards), so the deleted card's history stops counting
    // locally and stops being replayable by merge rule 2 elsewhere. That is
    // also why `SyncModelActor.pushDirtyReviewLogs` selects on `isDirty`
    // rather than `syncedAt == nil` — see the note there.

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
        card: Card,
        grade: Grade,
        responseTimeMs: Int,
        timestamp: Date = Date(),
        answeredValue: String? = nil,
        exerciseType: String? = nil,
        surface: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.card = card
        self.gradeRawValue = grade.rawValue
        self.responseTimeMs = responseTimeMs
        self.answeredValue = answeredValue
        self.exerciseType = exerciseType
        self.surface = surface
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
