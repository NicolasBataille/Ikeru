import Foundation
import IkeruCore

// MARK: - SessionLiveActivityCoordinator
//
// Thin wrapper around `LiveActivityManager` owning the per-progress-tick
// exercise-label computation that `SessionViewModel.reportLiveActivityProgress`
// used to do inline. Extracted from `SessionViewModel` (P2 debt lot) so the
// grading/completion flow doesn't have to carry the Live Activity's
// call-shape alongside FSRS grading — this type holds no session state of
// its own beyond the manager instance, it's a pure pass-through.
//
// Not `@Observable` — like `SessionRPGPersistence`, this type holds no
// published UI state; `SessionViewModel` owns all `@Observable` fields.
@MainActor
final class SessionLiveActivityCoordinator {

    private let manager = LiveActivityManager()

    /// Starts a Live Activity for a study session. Verbatim forward of
    /// `LiveActivityManager.startActivity`.
    func start(totalExercises: Int) {
        manager.startActivity(totalExercises: totalExercises)
    }

    /// Reports current progress. `currentExercise` drives the display label
    /// exactly as the original inline computation did: nil (session already
    /// advanced past the last exercise) falls back to "Review".
    func reportProgress(
        elapsedSeconds: Int,
        currentExercise: ExerciseItem?,
        completedCount: Int,
        totalCount: Int,
        xpEarned: Int,
        streakCount: Int
    ) async {
        let exerciseLabel = currentExercise.map { SessionExerciseSupport.exerciseDisplayName($0) } ?? "Review"
        await manager.updateActivity(
            elapsedSeconds: elapsedSeconds,
            exerciseType: exerciseLabel,
            completedCount: completedCount,
            totalCount: totalCount,
            xpEarned: xpEarned,
            streakCount: streakCount
        )
    }

    /// Ends the Live Activity with a final state summary. Verbatim forward of
    /// `LiveActivityManager.endActivity`.
    func end(
        elapsedSeconds: Int,
        completedCount: Int,
        totalCount: Int,
        xpEarned: Int,
        streakCount: Int
    ) async {
        await manager.endActivity(
            elapsedSeconds: elapsedSeconds,
            completedCount: completedCount,
            totalCount: totalCount,
            xpEarned: xpEarned,
            streakCount: streakCount
        )
    }
}
