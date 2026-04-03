import Foundation
import ActivityKit
import IkeruCore
import os

// MARK: - LiveActivityManager

/// Manages the session Live Activity lifecycle.
/// Starts an activity when a session begins, updates it as exercises complete,
/// and ends it when the session finishes.
@MainActor
final class LiveActivityManager {

    private var currentActivity: Activity<SessionActivityAttributes>?

    // MARK: - Start

    /// Starts a Live Activity for a study session.
    /// - Parameter totalExercises: Total number of exercises in the session.
    func startActivity(totalExercises: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.ui.info("Live Activities not enabled — skipping")
            return
        }

        let attributes = SessionActivityAttributes()
        let initialState = SessionActivityAttributes.ContentState(
            elapsedSeconds: 0,
            exerciseType: "Starting...",
            completedCount: 0,
            totalCount: totalExercises,
            xpEarned: 0,
            streakCount: 0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            Logger.ui.info("Live Activity started: \(activity.id)")
        } catch {
            Logger.ui.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update

    /// Updates the Live Activity with current session state.
    func updateActivity(
        elapsedSeconds: Int,
        exerciseType: String,
        completedCount: Int,
        totalCount: Int,
        xpEarned: Int,
        streakCount: Int
    ) {
        guard let activity = currentActivity else { return }

        let state = SessionActivityAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            exerciseType: exerciseType,
            completedCount: completedCount,
            totalCount: totalCount,
            xpEarned: xpEarned,
            streakCount: streakCount
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// Ends the Live Activity with a final state summary.
    func endActivity(
        elapsedSeconds: Int,
        completedCount: Int,
        totalCount: Int,
        xpEarned: Int
    ) {
        guard let activity = currentActivity else { return }

        let finalState = SessionActivityAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            exerciseType: "Complete!",
            completedCount: completedCount,
            totalCount: totalCount,
            xpEarned: xpEarned,
            streakCount: 0
        )

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 30) // Dismiss after 30 seconds
            )
            currentActivity = nil
            Logger.ui.info("Live Activity ended")
        }
    }
}
