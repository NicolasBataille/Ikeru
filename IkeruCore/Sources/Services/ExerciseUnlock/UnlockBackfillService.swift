import Foundation

/// One-shot migration helper. Existing profiles created before the
/// learning-loop architecture landed have an empty
/// `RPGState.acknowledgedUnlocks`; without backfill, every threshold they
/// already cross would fire as "new practice unlocked" the first time the
/// app re-evaluates them. `backfill(previous:profile:unlockService:)`
/// unions the previously-acknowledged set with everything the unlock
/// service currently grants for the profile, so existing learners start
/// the new flow with a quiet inbox.
public enum UnlockBackfillService {

    /// Returns `previous ∪ unlockService.unlockedTypes(profile:)`. Pure;
    /// running it twice with the same arguments returns the same set.
    public static func backfill(
        previous: Set<ExerciseType>,
        profile: LearnerSnapshot,
        unlockService: any ExerciseUnlockService
    ) -> Set<ExerciseType> {
        previous.union(unlockService.unlockedTypes(profile: profile))
    }
}
