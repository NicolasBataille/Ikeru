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
