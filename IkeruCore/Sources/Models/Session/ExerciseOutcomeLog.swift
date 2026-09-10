import Foundation
import SwiftData

/// A persisted outcome of a pool-based output exercise (listening / shadowing)
/// that has NO backing FSRS `Card` — its vocabulary lives only in the read-only
/// content DB. Recorded per completion so listening accuracy + recall can feed
/// `LearnerSnapshot` (which unlocks `.listeningUnsubtitled` / `.speakingPractice`)
/// and the speaking axis of `SkillBalanceSnapshot`.
///
/// Scoped by a scalar `profileID` (NOT a SwiftData relationship) on purpose:
/// introducing this entity is then a purely additive schema change — the
/// existing `UserProfile` (a V1 model) gains no inverse relationship and stays
/// byte-identical on disk, so the V1→V2 migration is lightweight-safe. See
/// `IkeruSchemaV2`.
@Model
public final class ExerciseOutcomeLog {

    /// Unique identifier for this outcome entry.
    public var id: UUID

    /// When the exercise was completed.
    public var timestamp: Date

    /// `SkillType.rawValue` — the skill this outcome measured (listening / speaking).
    /// Stored as a raw string so it is usable in `#Predicate` fetches.
    public var skillRawValue: String

    /// Accuracy in 0.0–1.0. Binary drills (listening pass/fail) record 1.0 / 0.0;
    /// graded drills (shadowing) record a Grade-banded value. See
    /// `ExerciseOutcomeAccuracy`.
    public var accuracy: Double

    /// The owning profile's id (the active profile at record time). Scalar
    /// scoping — no relationship — keeps the V2 migration additive.
    public var profileID: UUID

    /// Typed accessor over `skillRawValue`. Mirrors `ReviewLog.grade`.
    public var skill: SkillType {
        get { SkillType(rawValue: skillRawValue) ?? .listening }
        set { skillRawValue = newValue.rawValue }
    }

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1).
    // `ExerciseOutcomeLog` is append-only per spec §3 (conflict-free by
    // construction), but it still needs `updatedAt`/`syncedAt` to drive the
    // push delta. `deletedAt` is NOT decorative: outcome logs are tombstoned
    // when their profile is deleted (`ProfileViewModel.deleteProfile` — they
    // are scoped by a scalar `profileID` and never cascaded by SwiftData),
    // which is why `SyncModelActor.pushDirtyExerciseOutcomeLogs` selects on
    // `isDirty` rather than `syncedAt == nil` — see the note there.

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
        skill: SkillType,
        accuracy: Double,
        profileID: UUID,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.skillRawValue = skill.rawValue
        self.accuracy = accuracy
        self.profileID = profileID
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}

// MARK: - Grade → accuracy mapping

/// Pure mapping from a completed drill's `Grade` to a persisted 0–1 accuracy.
/// Kept standalone so it is unit-testable without a view or store.
///
/// Listening drills are binary (`DrillGradeMapping.listening` emits only
/// `.good`/`.again`), so a correct answer is a clean 1.0. Shadowing collapses a
/// real 0–1 pronunciation score into four `Grade` bands upstream
/// (`DrillGradeMapping.shadowing`); we can only recover a band-representative
/// value here, which is sufficient for the soft speaking-balance signal.
public enum ExerciseOutcomeAccuracy {

    public static func from(grade: Grade, skill: SkillType) -> Double {
        switch skill {
        case .listening:
            // Binary: only .good (correct) or .again (incorrect) occur.
            return grade == .again ? 0.0 : 1.0
        case .speaking:
            // Band representatives for the four shadowing accuracy bands
            // (<0.4 → again, 0.4–0.7 → hard, 0.7–0.9 → good, ≥0.9 → easy).
            switch grade {
            case .again: return 0.2
            case .hard:  return 0.5
            case .good:  return 0.8
            case .easy:  return 0.95
            }
        case .reading, .writing:
            // No current consumer; a neutral banded fallback.
            switch grade {
            case .again: return 0.0
            case .hard:  return 0.33
            case .good:  return 0.75
            case .easy:  return 1.0
            }
        }
    }
}
