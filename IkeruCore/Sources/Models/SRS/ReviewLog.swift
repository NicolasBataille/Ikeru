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
    /// session), `"iphone.drill"` (kana drill flashcard/quiz), or `"watch"`.
    /// Nothing writes `"watch"` yet — no Watch call site persists a
    /// `ReviewLog` today — so it is reserved, not currently observed.
    public var surface: String?

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
    }
}
