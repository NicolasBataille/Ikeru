import Foundation
import IkeruCore
import os

// MARK: - SessionViewModel+Lifecycle
//
// Session-start composition + reset: `resetSessionState()` and the four
// `start*`/`loadSessionPreview` entry points that drive it. Extracted from
// `SessionViewModel` (P2 debt lot, 2026-08) to bring the class body back
// under the repo's file-length guard, alongside the grading-flow split in
// `SessionViewModel+GradingFlow.swift` — same rationale, same "verbatim
// move" discipline: every method body below is unchanged from the original,
// only its file changed.
//
// Mechanical consequence: every stored property / dependency these methods
// WRITE (not just read — reads through a `public private(set)` getter were
// already reachable cross-file) had its access widened from `private`/
// `public private(set)` to `internal`/`public internal(set)` on the class
// body in `SessionViewModel.swift` — sessionMode, isActive, isPaused,
// sessionStartTime, planEstimatedDurationMinutes, vocabularyPool,
// estimatedCardCount, sessionPreview, sessionComposer, defaultDurationMinutes,
// timerCoordinator, plus the `startTimer()`/`loadRPGState()` methods these
// call. Compile-time-only; @testable already exposed internal members to the
// test target regardless of which file declared them.
extension SessionViewModel {

    /// Resets all per-session state to initial values.
    /// Called at the start of both basic and adaptive sessions.
    private func resetSessionState() {
        currentIndex = 0
        reviewedCount = 0
        xpEarned = 0
        newItemsLearned = 0
        lastXPGained = nil
        levelUpLevel = nil
        consecutiveCorrect = 0
        correctCount = 0
        gradedAttemptCount = 0
        missedCardIDs = []
        sessionMode = .normal
        retryCounts = [:]
        newItemCountedIDs = []
        nonSRSGradedCardIDs = []
        cardsNeedingPresentation = []
        planEstimatedDurationMinutes = 0
        lastSessionBonus = nil
        gradeSaveFailureCount = 0
        isPaused = false
        sessionStartTime = Date()
        cardStartTime = Date()
        isActive = true
        currentExerciseIndex = 0
        showAbandonConfirmation = false
        timerCoordinator.reset()
        endPolicy = nil
        ledger = SkillXPLedger()
        skillContribution = .zero
        vocabularyPool = []
    }

    /// Composes a session queue via the new `SessionPlanner` pipeline and
    /// starts the session. Composition (snapshot, unlock resolution, planner
    /// call, SRS-card extraction, vocab pool) lives in
    /// `SessionComposer.composeHomeRecommendation` (remediation 8.4
    /// extraction); this method applies the result and starts the
    /// timer/RPG-load/Live-Activity side effects exactly as before.
    ///
    /// Never starts an empty session — it would drop the user straight into a
    /// hollow "0 cards / 0% recall" summary that reads as failure. The
    /// composer returns nil in that case so no timer / Live Activity spins up
    /// for nothing. The Home CTA is also gated when nothing is composable.
    @discardableResult
    public func startSession() async -> Bool {
        guard let composed = await sessionComposer.composeHomeRecommendation(
            durationMinutes: defaultDurationMinutes
        ) else {
            Logger.ui.info("startSession: composed plan is empty — not starting")
            return false
        }

        sessionQueue = composed.sessionQueue
        resetSessionState()
        estimatedCardCount = composed.sessionExercises.count
        sessionExercises = composed.sessionExercises
        endPolicy = composed.endPolicy
        sessionJLPTLevel = composed.jlptLevel
        vocabularyPool = composed.vocabularyPool
        grammarClozes = composed.grammarClozes
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        startTimer()
        await loadRPGState()
        liveActivity.start(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Session started via SessionPlanner: \(composed.sessionExercises.count) exercises (\(composed.srsCardCount) SRS), ~\(composed.estimatedDurationMinutes)min"
        )
        return true
    }

    /// Starts the session a learner chose when nothing was due — the
    /// "approfondir" or "découvrir" offer from the Home proposal.
    ///
    /// Identical wiring to `startSession()` on purpose: once composed, a
    /// caught-up session IS an ordinary session, and giving it a parallel
    /// lifecycle would be two code paths to keep in step for no behavioural
    /// difference. Returns false when the chosen pool emptied between the
    /// proposal being shown and the tap — the caller must keep the proposal
    /// up rather than pretend something happened.
    @discardableResult
    public func startCaughtUpSession(
        offer: SessionPlannerInputs.CaughtUpOffer
    ) async -> Bool {
        guard let composed = await sessionComposer.composeCaughtUp(
            offer: offer,
            durationMinutes: defaultDurationMinutes
        ) else {
            Logger.ui.info(
                "startCaughtUpSession(\(offer.rawValue, privacy: .public)): nothing to compose — not starting"
            )
            return false
        }

        sessionQueue = composed.sessionQueue
        resetSessionState()
        estimatedCardCount = composed.sessionExercises.count
        sessionExercises = composed.sessionExercises
        endPolicy = composed.endPolicy
        sessionJLPTLevel = composed.jlptLevel
        vocabularyPool = composed.vocabularyPool
        grammarClozes = composed.grammarClozes
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        startTimer()
        await loadRPGState()
        liveActivity.start(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Caught-up session started (\(offer.rawValue, privacy: .public)): \(composed.sessionExercises.count) exercises"
        )
        return true
    }

    /// Composes a custom session from the Étude → Compose sheet. Same
    /// pipeline as `startSession()` but with `.studyCustom` as the planner
    /// source (see `SessionComposer.composeStudyCustom`) so the planner
    /// respects the user's chosen exercise types and JLPT levels rather than
    /// the home recommendation skeleton. Unlike `startSession()`, never
    /// guards on an empty queue (unchanged from the original).
    public func startStudyCustomSession(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) async {
        let composed = await sessionComposer.composeStudyCustom(
            types: types,
            levels: levels,
            duration: duration
        )

        sessionQueue = composed.sessionQueue
        resetSessionState()
        estimatedCardCount = composed.sessionExercises.count
        sessionExercises = composed.sessionExercises
        endPolicy = composed.endPolicy
        sessionJLPTLevel = composed.jlptLevel
        vocabularyPool = composed.vocabularyPool
        grammarClozes = composed.grammarClozes
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        startTimer()
        await loadRPGState()
        liveActivity.start(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Study custom session started: \(composed.sessionExercises.count) exercises (\(composed.srsCardCount) SRS), ~\(composed.estimatedDurationMinutes)min"
        )
    }

    /// Restarts the session with only the cards graded `.again` in the
    /// previous session. Drives the summary screen's "Review mistakes" CTA.
    /// No-op if the missed-set (or resolved card list) is empty — see
    /// `SessionComposer.composeReviewMistakes` for the guard.
    public func startReviewMistakes() async {
        guard let composed = await sessionComposer.composeReviewMistakes(
            missedCardIDs: missedCardIDs
        ) else { return }

        sessionQueue = composed.sessionQueue
        resetSessionState()
        sessionMode = .reviewMistakes
        estimatedCardCount = composed.sessionExercises.count
        sessionExercises = composed.sessionExercises
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        endPolicy = SessionEndPolicy(
            durationBudgetMinutes: defaultDurationMinutes,
            queueLength: composed.sessionExercises.count
        )
        // Review-mistakes carries forward whatever level the prior session
        // ran at — the cards themselves haven't changed.
        // sessionJLPTLevel intentionally not reset here.

        startTimer()
        await loadRPGState()
        liveActivity.start(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Review-mistakes session started: \(composed.sessionExercises.count) cards"
        )
    }
}
