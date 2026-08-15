import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - FeedbackState
//
// Shared correct/incorrect feedback state for exercise view models (vocabulary,
// sentence construction, session, exercise transitions). Re-homed here from the
// removed CardReviewViewModel, which previously housed this shared type.

public enum FeedbackState: Sendable, Equatable {
    case correct
    /// Recall succeeded but was slow (a `.hard` grade). Not a miss — `.hard`
    /// counts toward the recall %, same as `.correct` — but a full green
    /// "correct" flash would overstate how easy the recall actually was.
    case partial
    case incorrect

    public var color: Color {
        switch self {
        case .correct: Color(hex: IkeruTheme.Colors.success)        // jade green
        case .partial: Color(hex: IkeruTheme.Colors.warning)        // amber
        case .incorrect: Color(hex: IkeruTheme.Colors.secondaryAccent) // vermillion
        }
    }
}

// MARK: - SessionViewModel

@MainActor
@Observable
public final class SessionViewModel {

    // MARK: - Published State

    /// The ordered queue of cards for this session.
    public internal(set) var sessionQueue: [CardDTO] = []

    /// Index of the current card in the queue.
    public internal(set) var currentIndex: Int = 0

    /// Whether the session is actively running.
    public internal(set) var isActive: Bool = false

    /// Whether the session is paused.
    public internal(set) var isPaused: Bool = false

    /// When the session started.
    public internal(set) var sessionStartTime: Date = Date()

    /// Count of cards reviewed so far.
    public internal(set) var reviewedCount: Int = 0

    /// Total XP earned this session.
    public internal(set) var xpEarned: Int = 0

    /// Count of new items learned (first-time reviews).
    public internal(set) var newItemsLearned: Int = 0

    /// Cards graded `.again` during the current session — i.e. mistakes.
    /// Drives the "Review mistakes" CTA on the summary screen. Reset on
    /// every session start (including when re-starting in mistakes mode).
    public internal(set) var missedCardIDs: Set<UUID> = []

    /// Total cards graded `.good`, `.easy`, or `.hard` this session — i.e.
    /// every grade except `.again`, matching `missedCardIDs`' definition of
    /// a miss. `.hard` means the recall was slow but ultimately correct, so
    /// it counts as a pass here (see `gradeAndAdvance`); counting it as a
    /// failure would conflate slow recall with an actual miss. Used by the
    /// summary's recall % — *not* `consecutiveCorrect`, because that resets
    /// on any miss and made recall always read 0% the moment the user hit a
    /// single .hard or .again, even if every other card was correct.
    public internal(set) var correctCount: Int = 0

    /// Total REAL grading attempts this session — every `.again`/`.hard`/
    /// `.good`/`.easy` that actually reached `trackCorrectness`, whether the
    /// card passed or failed. Deliberately distinct from `reviewedCount`
    /// (which also counts ungraded new-card presentation passes, see
    /// `completeNewCardPresentation`): the summary's recall % must divide by
    /// attempts that could have failed, not by every step the learner saw,
    /// or an intro-heavy session (many presentations, zero of which can
    /// fail) reads as a worse recall % than it honestly was.
    public internal(set) var gradedAttemptCount: Int = 0

    /// Whether this session was launched via the "Review mistakes" CTA.
    /// In `.reviewMistakes` mode, a card graded `.again` is re-queued at
    /// the end of `sessionQueue` (up to `maxRetriesPerCard`) so the user
    /// actually drills the failures intra-session instead of waiting for
    /// the next summary screen to start a new session.
    public enum SessionMode: Sendable {
        case normal
        case reviewMistakes
    }
    public internal(set) var sessionMode: SessionMode = .normal

    /// How many times a single card has been re-queued during the
    /// current session. Capped at `maxRetriesPerCard` (declared alongside
    /// `requeueFailedCard` in `SessionViewModel+GradingFlow.swift`, the only
    /// place that reads it) so a stuck card can't loop forever. Written from
    /// this file (`resetSessionState`) and from that one, hence `internal`.
    var retryCounts: [UUID: Int] = [:]

    /// Card IDs already counted toward `newItemsLearned` this session.
    /// A same-day re-queued card is a stale pre-grade DTO (`reps == 0` for a
    /// brand-new card), so without this guard a retried new card would be
    /// double-counted on the summary screen.
    var newItemCountedIDs: Set<UUID> = []

    /// Card ids whose ungraded "presentation" pass hasn't been shown yet this
    /// session — populated at session start from
    /// `SessionComposer`/`NewCardPresentationScheduler`'s presentation
    /// schedule. A card's `.srsReview` occurrence renders as the ungraded
    /// presentation (see `isPresentingNewCard`) while its id is still in
    /// this set; the SAME card's delayed `.srsReview` occurrence a few
    /// exercises later renders as the normal graded touch-and-reveal test,
    /// because by then `completeNewCardPresentation` has removed it.
    ///
    /// 2026-08 pedagogy review, "erreur de conception #1": grading a
    /// touch-and-reveal test on a character the learner has never been
    /// shown produces a first FSRS note that's noise, not signal. The
    /// presentation pass removes that noise; the delayed test is the card's
    /// real first grade.
    var cardsNeedingPresentation: Set<UUID> = []

    /// Whether the CURRENT exercise is the ungraded presentation pass for a
    /// brand-new kana card rather than a normal graded touch-and-reveal
    /// test. Drives `ExerciseTransitionContainer`'s branch to the
    /// presentation view. See `cardsNeedingPresentation`.
    public var isPresentingNewCard: Bool {
        guard case .srsReview(let card) = currentExercise else { return false }
        return cardsNeedingPresentation.contains(card.id)
    }

    /// The planner's own duration estimate for the composed plan — read
    /// directly instead of re-summing `sessionExercises` flatly. A flat
    /// re-sum ignores `DefaultSessionPlanner`'s per-review maturity
    /// discount (`effectiveDurationSeconds`) and the extra time the new-card
    /// presentation pass adds, so it silently drifted from the plan's own
    /// honest estimate (SUIVI note, 2026-08 pedagogy P2 review). See
    /// `estimatedTotalTime`.
    var planEstimatedDurationMinutes: Int = 0

    /// Card IDs already FSRS-graded this session through the NON-SRS drill path
    /// (`completeCurrentExercise`). `.kanjiStudy` and `.writingPractice` are both
    /// backed by kanji cards drawn independently by the planner, so one session
    /// can surface both against the same character; this guard ensures a card is
    /// FSRS-graded at most once per session via that path (XP is still awarded
    /// for the second completion). The SRS deck path (`gradeAndAdvance`) is
    /// separate and unaffected, so legitimate same-day requeues still re-grade.
    var nonSRSGradedCardIDs: Set<UUID> = []

    /// Whether the session is complete (all exercises finished).
    ///
    /// Gated on the exercise list, NOT the SRS card queue. Once non-SRS
    /// exercises can interleave with `.srsReview` items, `currentIndex` (an
    /// SRS-only pointer into `sessionQueue`) and `currentExerciseIndex` no
    /// longer move in lockstep, and a non-SRS exercise scheduled after the last
    /// SRS card must still be presented rather than silently dropped. For a
    /// pure-SRS session the two pointers advance together, so this stays exactly
    /// equivalent to the previous `currentIndex >= sessionQueue.count`.
    public var isSessionComplete: Bool {
        isActive && currentExerciseIndex >= sessionExercises.count
    }

    /// Whether the session should end now — queue exhausted OR the
    /// time-budget end policy fired. Card flashcards always finish at a
    /// clean transition point, so `.completeAfterCurrent` and
    /// `.completeNow` collapse into a single "stop" decision here.
    public var shouldEndSession: Bool {
        if isSessionComplete { return true }
        guard let policy = endPolicy else { return false }
        let action = policy.evaluate(state: SessionEndState(
            elapsedSeconds: Int(elapsedTime),
            completedCount: reviewedCount,
            activeItemInFlight: false
        ))
        return action != .continueSession
    }

    /// The current card being reviewed, or nil if complete.
    public var currentCard: CardDTO? {
        guard currentIndex < sessionQueue.count else { return nil }
        return sessionQueue[currentIndex]
    }

    /// The next card for peek/pre-load, or nil.
    public var nextCard: CardDTO? {
        upcomingCards.first
    }

    /// The card two positions ahead, used to render a 3-deep deck peek stack.
    public var cardAfterNext: CardDTO? {
        upcomingCards.dropFirst().first
    }

    /// Upcoming cards after the current one. Up to 3 entries are exposed so
    /// the deck view can render a visual "stack" whose depth reflects how
    /// many reviews remain.
    public var upcomingCards: [CardDTO] {
        let start = currentIndex + 1
        let end = min(sessionQueue.count, start + 3)
        guard start < end else { return [] }
        return Array(sessionQueue[start..<end])
    }

    /// Progress fraction (0.0 to 1.0).
    public var sessionProgress: Double {
        guard !sessionQueue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(sessionQueue.count)
    }

    /// Elapsed session duration in seconds (driven by ContinuousClock timer).
    /// Forwarded from `timerCoordinator` (remediation 8.4 extraction) —
    /// SwiftUI observation still tracks this correctly through the computed
    /// property because Observation's access tracking registers against
    /// whichever object's registrar backs the property actually read, not
    /// the object the caller went through. See `SessionTimerCoordinator`.
    public var elapsedTime: TimeInterval { timerCoordinator.elapsedTime }

    /// Whether the ContinuousClock timer is actively ticking.
    public var isTimerRunning: Bool { timerCoordinator.isTimerRunning }

    /// Fires once when the active session crosses the (durationBudget − 60s)
    /// mark. Drives the "1 minute remaining" toast on `ActiveSessionView`.
    /// Reset to false on each new session.
    public var oneMinuteRemainingFired: Bool { timerCoordinator.oneMinuteRemainingFired }

    /// Formatted elapsed time string (MM:SS).
    public var elapsedTimeFormatted: String {
        SessionExerciseSupport.formatTime(elapsedTime)
    }

    /// Estimated total session duration in seconds — read from the planner's
    /// own estimate (`planEstimatedDurationMinutes`), not re-summed flatly
    /// from `sessionExercises`. See that property's doc comment.
    public var estimatedTotalTime: TimeInterval {
        TimeInterval(planEstimatedDurationMinutes * 60)
    }

    /// Estimated remaining time in seconds.
    public var estimatedRemainingTime: TimeInterval {
        max(0, estimatedTotalTime - elapsedTime)
    }

    /// Formatted estimated remaining time string ("-MM:SS").
    public var estimatedRemainingTimeFormatted: String {
        "-" + SessionExerciseSupport.formatTime(estimatedRemainingTime)
    }

    /// Estimated session card count for preview.
    public internal(set) var estimatedCardCount: Int = 0

    // MARK: - Immersive Session State

    /// The ordered list of exercises for the current session (adaptive or SRS-only).
    public internal(set) var sessionExercises: [ExerciseItem] = []

    /// Session-scoped vocabulary pool for the audio drills (Shadowing +
    /// word/meaning Listening). Fetched once at session start from the injected
    /// `ContentRepository` (level-scoped) and mapped via `VocabularyItemMapper`.
    /// The immersive drill container reads this as its content pool and builds
    /// each audio drill's view model lazily at render time — the composition-root
    /// pattern from blueprint §2 (no per-item payload threaded through
    /// `ExerciseItem`). Empty when no repository was injected or the level has no
    /// vocabulary; the container degrades gracefully in that case.
    public internal(set) var vocabularyPool: [VocabularyItem] = []

    /// The profile's desired retention, snapshotted at session start — feeds
    /// the per-card predicted intervals under the grade buttons so they match
    /// what `gradeCard` will actually schedule.
    public private(set) var desiredRetention: Double = 0.9

    /// Index of the current exercise in the sessionExercises array.
    public internal(set) var currentExerciseIndex: Int = 0

    /// The current exercise item, or nil if session is complete.
    public var currentExercise: ExerciseItem? {
        guard currentExerciseIndex < sessionExercises.count else { return nil }
        return sessionExercises[currentExerciseIndex]
    }

    /// Whether the abandon confirmation dialog should be shown.
    public var showAbandonConfirmation: Bool = false

    /// Triggers animation when exercise transitions occur.
    public private(set) var exerciseTransitionTrigger: Int = 0

    // MARK: - RPG State

    /// Current total XP (persisted across sessions via RPGState).
    public internal(set) var totalXP: Int = 0

    /// Current level (persisted across sessions via RPGState).
    public internal(set) var currentLevel: Int = 1

    /// XP gained from the last graded card (drives XPGainView overlay).
    public internal(set) var lastXPGained: Int?

    /// Level reached via level-up (drives LevelUpView overlay).
    public internal(set) var levelUpLevel: Int?

    // MARK: - Feedback

    /// Whether a feedback flash is currently showing.
    public internal(set) var feedbackState: FeedbackState?

    // MARK: - Adaptive Session State

    /// Preview of the upcoming session (exercise breakdown, estimated time, skill split).
    public internal(set) var sessionPreview: SessionPreview = .empty

    /// The most recent leech event detected during this session, if any.
    public internal(set) var lastLeechEvent: LeechEvent?

    /// Companion intervention content (message/mnemonic/quiz) for
    /// `lastLeechEvent`, sourced from the same-JLPT-level content bundle when
    /// available. Set alongside `lastLeechEvent` — nil until the first leech
    /// of the session fires, then holds the most recent one's intervention.
    public internal(set) var lastLeechIntervention: LeechIntervention?

    /// Count of consecutive correct answers in this session (display/Live
    /// Activity streak only — no longer feeds loot RNG since loot retirement).
    public internal(set) var consecutiveCorrect: Int = 0

    /// XP bonus awarded at session end for daily engagement / streak (nil if none).
    public internal(set) var lastSessionBonus: SessionBonusService.Result?

    /// Monotonic count of grading transactions whose persistence failed.
    /// Bumped in `gradeAndAdvance` when `CardSaveErrorMonitor` reports a
    /// failure right after the grade write; `ActiveSessionView` observes it
    /// to surface a "your review may not count" toast. The monitor is cleared
    /// once consumed so a failure is surfaced exactly once.
    public internal(set) var gradeSaveFailureCount: Int = 0

    // MARK: - Dependencies

    private let plannerService: PlannerService
    private let sessionPlanner: any SessionPlanner
    private let unlockService: any ExerciseUnlockService
    let cardRepository: CardRepository
    /// Read-only static-content facade (bundled SQLite). Optional so existing
    /// call sites (previews, tests) compile unchanged; `nil` yields an empty
    /// `vocabularyPool` and the audio drills degrade gracefully. Injected by
    /// `HomeView.initializeViewModels()` in production (blueprint 4.1 Step 0).
    let contentRepository: ContentRepository?
    private let modelContainer: ModelContainer
    /// Live Activity / Dynamic Island lifecycle, extracted off this class
    /// (P2 debt lot) — see `SessionLiveActivityCoordinator`. `internal` (not
    /// `private`) because `SessionViewModel+GradingFlow.swift` drives it too.
    let liveActivity = SessionLiveActivityCoordinator()
    /// Foreground-only elapsed-time bookkeeping, extracted off this class
    /// (remediation 8.4) — see `SessionTimerCoordinator`.
    let timerCoordinator = SessionTimerCoordinator()
    /// RPG XP/level persistence + finalization, extracted off this
    /// class (remediation 8.4) — see `SessionRPGPersistence`.
    let rpgPersistence: SessionRPGPersistence
    /// `SessionPlanner`-pipeline session composition, extracted off this
    /// class (remediation 8.4) — see `SessionComposer`.
    let sessionComposer: SessionComposer
    var cardStartTime: Date = Date()

    /// Policy that decides when an active session ends. Built when the
    /// session starts; nil between sessions. Drives both queue-exhaustion
    /// and time-budget-exhaustion exits.
    var endPolicy: SessionEndPolicy?

    /// JLPT level used to scale per-exercise XP awards via
    /// `ExerciseXP.multiplier(for:)`. Captured from the learner snapshot
    /// at session-start so every grade in the session uses a consistent
    /// difficulty multiplier. Defaults to N5.
    var sessionJLPTLevel: JLPTLevel = .n5

    /// Accumulates per-skill XP for the active session. Read-side via
    /// `skillContribution`; the actor itself is fresh per session.
    var ledger = SkillXPLedger()

    /// Per-skill XP earned in the active session. Drives the four-winds
    /// row on `SessionSummaryView`. Reset to `.zero` on session start;
    /// updated after every grade.
    public internal(set) var skillContribution: SessionSkillContribution = .zero

    /// User-tunable target session duration (minutes). Read from `@AppStorage`
    /// so changes in Settings reflect immediately without rebuilding the VM.
    @ObservationIgnored
    @AppStorage("ikeru.session.defaultDurationMinutes")
    var defaultDurationMinutes: Int = 15

    // MARK: - Init

    public init(
        plannerService: PlannerService,
        cardRepository: CardRepository,
        modelContainer: ModelContainer,
        sessionPlanner: any SessionPlanner = DefaultSessionPlanner(),
        unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService(),
        contentRepository: ContentRepository? = nil
    ) {
        self.plannerService = plannerService
        self.sessionPlanner = sessionPlanner
        self.unlockService = unlockService
        self.cardRepository = cardRepository
        self.contentRepository = contentRepository
        self.modelContainer = modelContainer
        self.rpgPersistence = SessionRPGPersistence(modelContainer: modelContainer)
        self.sessionComposer = SessionComposer(
            plannerService: plannerService,
            sessionPlanner: sessionPlanner,
            unlockService: unlockService,
            cardRepository: cardRepository,
            contentRepository: contentRepository,
            modelContainer: modelContainer
        )
    }

    // MARK: - Session Finalization
    //
    // `finalizeSession()` itself now lives in `SessionViewModel+GradingFlow.swift`
    // (P2 debt lot) alongside the rest of the end-of-session flow that calls it;
    // the methods below stay here since they're driven by the view layer
    // directly, not by the grading pipeline.

    /// Grade from a swipe direction.
    func gradeFromSwipe(direction: SwipeDirection) async {
        await gradeAndAdvance(grade: direction.grade)
    }

    /// Clears the last XP gained display (called by the overlay after animation).
    public func clearXPGain() {
        lastXPGained = nil
    }

    /// Clears the level-up display (called by the overlay after celebration).
    public func clearLevelUp() {
        levelUpLevel = nil
    }


    /// Pauses the current session.
    public func pauseSession() {
        isPaused = true
        // Fold the current active interval before stopping so background
        // time is not counted if the user leaves the app while paused.
        // `timerCoordinator.suspend()` is a no-op guarded on `isTimerRunning`
        // internally, then folds + stops — identical net effect to the
        // original inline fold followed by an unconditional `stopTimer()`.
        timerCoordinator.suspend()
        Logger.ui.debug("Session paused at card \(self.currentIndex + 1)/\(self.sessionQueue.count)")
    }

    /// Resumes the session from where it was paused.
    public func resumeSession() {
        isPaused = false
        cardStartTime = Date()
        startTimer()
        Logger.ui.debug("Session resumed at card \(self.currentIndex + 1)/\(self.sessionQueue.count)")
    }

    /// Ends the session early, preserving partial progress.
    ///
    /// If no cards were reviewed (the user abandoned immediately), the summary
    /// screen has nothing meaningful to display — skip it and return directly
    /// to the home screen via `dismissSession()`.
    ///
    /// `async` (GAP-10, 2026-08-16): the Live-Activity-end and
    /// newly-unlocked bookkeeping below used to run as two untracked,
    /// un-awaited `Task { }` blocks. Harmless in production — the app opens
    /// exactly one `ModelContainer` for its whole lifetime, so a detached
    /// task touching it a few milliseconds after this function returns is
    /// indistinguishable from touching it synchronously. But the app test
    /// target crashed the whole `xcodebuild test` runner: each test builds
    /// and discards its OWN in-memory `ModelContainer`, and these detached
    /// tasks routinely outlived the test that spawned them — still running
    /// (and fetching/saving `RPGState` through `SessionRPGPersistence`)
    /// once a LATER, unrelated test's container was current. SwiftData's
    /// process-global backing-data bookkeeping isn't safe against that:
    /// confirmed via `xcrun xcresulttool export diagnostics` crash reports
    /// and the simulator's unified log, all showing the identical fatal
    /// error `SwiftData/BackingData.swift:940: Never access a full future
    /// backing data`, with the accessed `PersistentIdentifier`'s Core Data
    /// store UUID never matching the store the crashing access expected —
    /// i.e. a stale reference from a different (already-gone) container.
    /// Making this `async` and awaiting both calls directly keeps them
    /// off the critical synchronous path that mutates `@Observable` state
    /// just below (SwiftUI still sees that state change immediately — the
    /// synchronous prefix of an `async` function runs eagerly, before its
    /// first suspension point) while ensuring the function genuinely
    /// doesn't return until the SwiftData work is done, so nothing is left
    /// running against a container the caller may be about to release.
    /// The one production call site (`ActiveSessionView`'s "End Session"
    /// button) now wraps this in `Task { await ... }` itself.
    public func endSession() async {
        Logger.ui.info(
            "Session ended early: \(self.reviewedCount)/\(self.sessionQueue.count) reviewed, \(self.xpEarned) XP"
        )

        // If the user quits without GRADING a single card, skip the summary
        // entirely and go straight back to the home screen. Checks
        // `gradedAttemptCount`, not `reviewedCount`: an abandoned session
        // that only showed ungraded new-card presentation passes (see
        // `completeNewCardPresentation`) has `reviewedCount > 0` but nothing
        // for the summary's CARDS/RECALL/NEW LEARNED/RE-LEARN stats to show
        // — the summary would render as an empty, failure-reading screen for
        // a session that, from the learner's perspective, did nothing wrong.
        if gradedAttemptCount == 0 {
            dismissSession()
            return
        }

        // Mark as complete by jumping to end of queue. Done before the
        // awaits below so the synchronous state change is observed by
        // SwiftUI immediately, matching the original fire-and-forget timing.
        currentIndex = sessionQueue.count
        currentExerciseIndex = sessionExercises.count
        isPaused = false
        showAbandonConfirmation = false
        stopTimer()

        // End Live Activity.
        await liveActivity.end(
            elapsedSeconds: Int(elapsedTime),
            completedCount: reviewedCount,
            // Exercise-list length, matching updateActivity / finishSessionIfNeeded.
            // On an abandoned mixed SRS + drill session, sessionQueue.count
            // (SRS-only) would under-report and make completedCount > totalCount.
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )

        await processNewlyUnlocked()
    }

    /// After the session ends, compute the new `LearnerSnapshot` and grant
    /// a one-time `Loot.NewExerciseUnlocked` badge for each `ExerciseType`
    /// that crossed its unlock threshold during the session. Delegates to
    /// `SessionRPGPersistence.processNewlyUnlocked` (remediation 8.4).
    private func processNewlyUnlocked() async {
        let cards = await cardRepository.allCards()
        let snapshot = await sessionComposer.buildSnapshot(cards: cards)
        await rpgPersistence.processNewlyUnlocked(snapshot: snapshot, unlockService: unlockService)
    }

    /// Dismisses the session completely (called after summary).
    public func dismissSession() {
        isActive = false
        isPaused = false
        sessionQueue = []
        sessionExercises = []
        currentIndex = 0
        currentExerciseIndex = 0
        showAbandonConfirmation = false
        stopTimer()
        Logger.ui.debug("Session dismissed")
    }

    // MARK: - Exercise Navigation

    /// Advances to the next exercise in the session.
    /// Called internally after grading; ends session if this was the last exercise.
    public func advanceToNextExercise() {
        let nextIndex = currentExerciseIndex + 1
        if nextIndex >= sessionExercises.count {
            currentExerciseIndex = sessionExercises.count
            Logger.ui.debug("Last exercise completed")
        } else {
            exerciseTransitionTrigger += 1
            currentExerciseIndex = nextIndex
            Logger.ui.debug(
                "Advanced to exercise \(nextIndex + 1)/\(self.sessionExercises.count)"
            )
        }
    }

    /// Requests abandon confirmation — shows the confirmation dialog.
    public func requestAbandon() {
        showAbandonConfirmation = true
    }

    /// Cancels the abandon request — dismisses the dialog and returns to pause.
    public func cancelAbandon() {
        showAbandonConfirmation = false
    }

    /// Progress description for the abandon dialog (e.g. "You've completed
    /// 3 of 8 exercises"). Uses an explicit format-string lookup so the
    /// catalog can carry placeholders rather than the interpolated form.
    public var abandonProgressDescription: String {
        String(
            format: String(localized: "Session.AbandonProgress"),
            reviewedCount,
            sessionExercises.count
        )
    }

    // MARK: - Timer

    /// Starts (or resumes) the foreground elapsed-time timer via
    /// `timerCoordinator`, first refreshing the one-minute-remaining
    /// threshold from the current `endPolicy`. `durationBudgetMinutes` never
    /// changes mid-session (only `queueLength` grows, on requeue), so
    /// recomputing here is equivalent to the original's per-tick `endPolicy`
    /// read inside `checkOneMinuteRemaining`.
    func startTimer() {
        if let policy = endPolicy {
            timerCoordinator.oneMinuteThresholdSeconds = policy.durationBudgetMinutes * 60 - 60
        }
        timerCoordinator.start()
    }

    /// Pauses the timer and folds the current interval so background time is
    /// never counted. Called from scenePhase onChange in the session view
    /// when the scene becomes inactive or background.
    public func suspendTimer() {
        timerCoordinator.suspend()
    }

    /// Resumes the timer from where it was suspended. Called from scenePhase
    /// onChange when the scene becomes active again.
    public func resumeTimer() {
        timerCoordinator.resumeIfEligible(isActive: isActive, isPaused: isPaused)
    }

    /// Stops the timer completely.
    func stopTimer() {
        timerCoordinator.stop()
    }

    // MARK: - RPG State Persistence

    /// Loads the active profile's RPG state, creating one if the profile lacks it.
    func loadRPGState() async {
        if let state = await rpgPersistence.loadState() {
            totalXP = state.xp
            currentLevel = state.level
        } else {
            totalXP = 0
            currentLevel = 1
        }
        // Piggybacks on the one await every session-start path shares:
        // snapshot the profile's retention so the grade buttons can show
        // per-card predicted intervals matching what grading will schedule.
        desiredRetention = await cardRepository.activeDesiredRetention()
    }

    // `persistRPGState()` was retired here: its only caller (`awardExerciseXP`)
    // moved to `SessionViewModel+GradingFlow.swift` (P2 debt lot) and now calls
    // `rpgPersistence.persistState(...)` directly — the 3-line wrapper had
    // nothing left to wrap.

}

// MARK: - Environment Key

private struct SessionViewModelKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: SessionViewModel? = nil
}

extension EnvironmentValues {
    public var sessionViewModel: SessionViewModel? {
        get { self[SessionViewModelKey.self] }
        set { self[SessionViewModelKey.self] = newValue }
    }
}
