import Foundation
import IkeruCore

// MARK: - SessionRequeuePlanner
//
// Pure computation for the same-day intra-session re-queue: a card graded
// `.again` comes back later in the same session instead of disappearing
// until its next FSRS due date. Extracted from
// `SessionViewModel.requeueFailedCard` (remediation 8.4) — the arithmetic is
// a verbatim move; the caller applies the result onto its own `@Observable`
// state (`sessionQueue`, `sessionExercises`, `retryCounts`, `endPolicy`).
enum SessionRequeuePlanner {

    struct Result {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        let retryCount: Int
        let endPolicy: SessionEndPolicy?
    }

    /// Mistakes mode appends to the end (drill-until-done); normal sessions
    /// re-insert 3-5 positions later. Returns nil once `currentRetryCount`
    /// has reached `maxRetries` — the caller no-ops in that case, matching
    /// the original's early-return guard.
    static func requeue(
        card: CardDTO,
        currentRetryCount: Int,
        maxRetries: Int,
        sessionMode: SessionViewModel.SessionMode,
        currentExerciseIndex: Int,
        sessionQueue: [CardDTO],
        sessionExercises: [ExerciseItem],
        endPolicy: SessionEndPolicy?
    ) -> Result? {
        guard currentRetryCount < maxRetries else { return nil }

        var queue = sessionQueue
        var exercises = sessionExercises

        if sessionMode == .reviewMistakes {
            // Append to both ends — the appended `.srsReview` is the last
            // card-backed exercise, so its queue slot is simply the current
            // queue length; correspondence is preserved.
            queue.append(card)
            exercises.append(.srsReview(card))
        } else {
            let offset = Int.random(in: 3...5)
            let exerciseSlot = min(currentExerciseIndex + 1 + offset, exercises.count)
            // Derive the SRS-queue slot FROM the exercise slot so the two arrays
            // stay in lockstep when non-SRS exercises interleave: `sessionQueue`
            // holds only `.srsReview` payloads, so the requeued card's queue
            // position is the number of `.srsReview` items preceding its
            // exercise-list slot. Computing an independent `currentIndex + offset`
            // (the old behavior) desyncs the two the moment a non-SRS item sits
            // between the pointers, making the deck grade the wrong card. In a
            // pure-SRS session every preceding item is `.srsReview`, so this
            // equals the old `currentIndex + 1 + offset` exactly.
            let queueSlot = exercises[..<exerciseSlot].reduce(into: 0) { count, item in
                if case .srsReview = item { count += 1 }
            }
            exercises.insert(.srsReview(card), at: exerciseSlot)
            queue.insert(card, at: queueSlot)
        }

        // The end policy captured the queue length at session start; grow it in
        // lockstep so the queue-exhaustion check doesn't fire before the
        // re-queued card is shown.
        let updatedPolicy = endPolicy.map {
            SessionEndPolicy(
                durationBudgetMinutes: $0.durationBudgetMinutes,
                queueLength: $0.queueLength + 1,
                graceWindowSeconds: $0.graceWindowSeconds
            )
        }

        return Result(
            sessionQueue: queue,
            sessionExercises: exercises,
            retryCount: currentRetryCount + 1,
            endPolicy: updatedPolicy
        )
    }
}
