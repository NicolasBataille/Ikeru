import Foundation

// MARK: - SessionTimerCoordinator
//
// Owns the ContinuousClock-driven elapsed-time bookkeeping for an active
// session: foreground-only elapsed time, the running/suspended flag, and the
// one-minute-remaining toast trigger. Extracted from `SessionViewModel`
// (remediation 8.4) so the god object no longer carries the timer's interval
// arithmetic inline — behavior is unchanged, this is a straight move.
//
// `@Observable` so `SessionViewModel`'s forwarding computed properties
// (`elapsedTime`, `isTimerRunning`, `oneMinuteRemainingFired`) keep publishing
// changes to observers: SwiftUI's Observation tracking registers access
// against whichever object's registrar backs the property that was actually
// read, not the object the caller happened to go through — so a view reading
// `sessionViewModel.elapsedTime` (a computed property that reads
// `timerCoordinator.elapsedTime`) still re-renders when the coordinator
// mutates that property, exactly as it did when the value was stored directly
// on `SessionViewModel`.
@MainActor
@Observable
final class SessionTimerCoordinator {

    /// Elapsed session duration in seconds (driven by ContinuousClock timer).
    private(set) var elapsedTime: TimeInterval = 0

    /// Whether the ContinuousClock timer is actively ticking.
    private(set) var isTimerRunning: Bool = false

    /// Fires once when the active session crosses the (durationBudget − 60s)
    /// mark. Drives the "1 minute remaining" toast on `ActiveSessionView`.
    /// Reset to false on each new session.
    private(set) var oneMinuteRemainingFired: Bool = false

    /// Elapsed-seconds threshold at which `oneMinuteRemainingFired` should
    /// flip to true. Set by the owner from its `SessionEndPolicy` whenever a
    /// session (re)starts; nil disables the check (mirrors the original
    /// `guard let policy = endPolicy else { return }`).
    var oneMinuteThresholdSeconds: Int?

    /// Accumulated active time from completed intervals (before the current
    /// timer run). Updated whenever the timer is paused mid-session so that
    /// background time is excluded from the session duration.
    private var baseElapsedTime: TimeInterval = 0

    /// Wall-clock anchor for the current timer run. Set whenever `start()`
    /// begins a new interval so elapsed = base + (now − resume).
    private var timerResumeTime: Date = Date()

    private var timerTask: Task<Void, Never>?

    /// Resets all bookkeeping to initial values. Called at the start of
    /// every new session (basic, adaptive, study-custom, review-mistakes).
    ///
    /// Note: the leading `stop()` is a defensive addition from the 8.4
    /// extraction — the pre-split `resetSessionState()` reset the raw fields
    /// without stopping the timer (which is always already stopped on every
    /// reachable path). Not a pure verbatim move; behavior is unchanged.
    func reset() {
        stop()
        elapsedTime = 0
        baseElapsedTime = 0
        timerResumeTime = Date()
        oneMinuteRemainingFired = false
        oneMinuteThresholdSeconds = nil
    }

    /// Drives `elapsedTime` counting only active foreground time.
    ///
    /// Each timer run accumulates seconds from `timerResumeTime` (set when
    /// the interval starts) on top of `baseElapsedTime` (the sum of all
    /// previous completed intervals). When `suspend()` is called (scene
    /// goes background or is paused), the delta is folded into `baseElapsedTime`
    /// and the task is cancelled. When `start()` is called again,
    /// `timerResumeTime` is reset so only the new foreground interval counts.
    func start() {
        guard !isTimerRunning else { return }
        isTimerRunning = true
        timerResumeTime = Date()
        timerTask = Task { @MainActor in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.elapsedTime = self.baseElapsedTime
                    + Date().timeIntervalSince(self.timerResumeTime)
                self.checkOneMinuteRemaining()
            }
        }
    }

    /// Pauses the timer and folds the current interval into `baseElapsedTime`
    /// so background time is never counted. Used both for explicit pause
    /// (`SessionViewModel.pauseSession()`) and scene-phase suspension
    /// (`SessionViewModel.suspendTimer()`) — both call sites want identical
    /// fold-then-stop behavior.
    func suspend() {
        guard isTimerRunning else { return }
        baseElapsedTime += Date().timeIntervalSince(timerResumeTime)
        elapsedTime = baseElapsedTime
        stop()
    }

    /// Resumes the timer only if it isn't already running and the session is
    /// active and not paused. Mirrors the original `resumeTimer()` guard.
    func resumeIfEligible(isActive: Bool, isPaused: Bool) {
        guard !isTimerRunning, isActive, !isPaused else { return }
        start()
    }

    /// Stops the timer completely.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        isTimerRunning = false
    }

    /// Sets `oneMinuteRemainingFired` once when elapsed crosses
    /// `oneMinuteThresholdSeconds`. Idempotent — drives a single toast.
    private func checkOneMinuteRemaining() {
        guard !oneMinuteRemainingFired, let threshold = oneMinuteThresholdSeconds else { return }
        if Int(elapsedTime) >= threshold {
            oneMinuteRemainingFired = true
        }
    }
}
