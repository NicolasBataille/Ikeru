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
    public private(set) var sessionQueue: [CardDTO] = []

    /// Index of the current card in the queue.
    public private(set) var currentIndex: Int = 0

    /// Whether the session is actively running.
    public private(set) var isActive: Bool = false

    /// Whether the session is paused.
    public private(set) var isPaused: Bool = false

    /// When the session started.
    public private(set) var sessionStartTime: Date = Date()

    /// Count of cards reviewed so far.
    public private(set) var reviewedCount: Int = 0

    /// Total XP earned this session.
    public private(set) var xpEarned: Int = 0

    /// Count of new items learned (first-time reviews).
    public private(set) var newItemsLearned: Int = 0

    /// Cards graded `.again` during the current session — i.e. mistakes.
    /// Drives the "Review mistakes" CTA on the summary screen. Reset on
    /// every session start (including when re-starting in mistakes mode).
    public private(set) var missedCardIDs: Set<UUID> = []

    /// Total cards graded `.good`, `.easy`, or `.hard` this session — i.e.
    /// every grade except `.again`, matching `missedCardIDs`' definition of
    /// a miss. `.hard` means the recall was slow but ultimately correct, so
    /// it counts as a pass here (see `gradeAndAdvance`); counting it as a
    /// failure would conflate slow recall with an actual miss. Used by the
    /// summary's recall % — *not* `consecutiveCorrect`, because that resets
    /// on any miss and made recall always read 0% the moment the user hit a
    /// single .hard or .again, even if every other card was correct.
    public private(set) var correctCount: Int = 0

    /// Total REAL grading attempts this session — every `.again`/`.hard`/
    /// `.good`/`.easy` that actually reached `trackCorrectness`, whether the
    /// card passed or failed. Deliberately distinct from `reviewedCount`
    /// (which also counts ungraded new-card presentation passes, see
    /// `completeNewCardPresentation`): the summary's recall % must divide by
    /// attempts that could have failed, not by every step the learner saw,
    /// or an intro-heavy session (many presentations, zero of which can
    /// fail) reads as a worse recall % than it honestly was.
    public private(set) var gradedAttemptCount: Int = 0

    /// Whether this session was launched via the "Review mistakes" CTA.
    /// In `.reviewMistakes` mode, a card graded `.again` is re-queued at
    /// the end of `sessionQueue` (up to `maxRetriesPerCard`) so the user
    /// actually drills the failures intra-session instead of waiting for
    /// the next summary screen to start a new session.
    public enum SessionMode: Sendable {
        case normal
        case reviewMistakes
    }
    public private(set) var sessionMode: SessionMode = .normal

    /// How many times a single card has been re-queued during the
    /// current session. Capped at `maxRetriesPerCard` so a stuck card
    /// can't loop forever.
    private var retryCounts: [UUID: Int] = [:]
    private static let maxRetriesPerCard = 2

    /// Card IDs already counted toward `newItemsLearned` this session.
    /// A same-day re-queued card is a stale pre-grade DTO (`reps == 0` for a
    /// brand-new card), so without this guard a retried new card would be
    /// double-counted on the summary screen.
    private var newItemCountedIDs: Set<UUID> = []

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
    private var cardsNeedingPresentation: Set<UUID> = []

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
    private var planEstimatedDurationMinutes: Int = 0

    /// Card IDs already FSRS-graded this session through the NON-SRS drill path
    /// (`completeCurrentExercise`). `.kanjiStudy` and `.writingPractice` are both
    /// backed by kanji cards drawn independently by the planner, so one session
    /// can surface both against the same character; this guard ensures a card is
    /// FSRS-graded at most once per session via that path (XP is still awarded
    /// for the second completion). The SRS deck path (`gradeAndAdvance`) is
    /// separate and unaffected, so legitimate same-day requeues still re-grade.
    private var nonSRSGradedCardIDs: Set<UUID> = []

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
    public private(set) var estimatedCardCount: Int = 0

    // MARK: - Immersive Session State

    /// The ordered list of exercises for the current session (adaptive or SRS-only).
    public private(set) var sessionExercises: [ExerciseItem] = []

    /// Session-scoped vocabulary pool for the audio drills (Shadowing +
    /// word/meaning Listening). Fetched once at session start from the injected
    /// `ContentRepository` (level-scoped) and mapped via `VocabularyItemMapper`.
    /// The immersive drill container reads this as its content pool and builds
    /// each audio drill's view model lazily at render time — the composition-root
    /// pattern from blueprint §2 (no per-item payload threaded through
    /// `ExerciseItem`). Empty when no repository was injected or the level has no
    /// vocabulary; the container degrades gracefully in that case.
    public private(set) var vocabularyPool: [VocabularyItem] = []

    /// The profile's desired retention, snapshotted at session start — feeds
    /// the per-card predicted intervals under the grade buttons so they match
    /// what `gradeCard` will actually schedule.
    public private(set) var desiredRetention: Double = 0.9

    /// Index of the current exercise in the sessionExercises array.
    public private(set) var currentExerciseIndex: Int = 0

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
    public private(set) var totalXP: Int = 0

    /// Current level (persisted across sessions via RPGState).
    public private(set) var currentLevel: Int = 1

    /// XP gained from the last graded card (drives XPGainView overlay).
    public private(set) var lastXPGained: Int?

    /// Level reached via level-up (drives LevelUpView overlay).
    public private(set) var levelUpLevel: Int?

    // MARK: - Feedback

    /// Whether a feedback flash is currently showing.
    public private(set) var feedbackState: FeedbackState?

    // MARK: - Adaptive Session State

    /// Preview of the upcoming session (exercise breakdown, estimated time, skill split).
    public private(set) var sessionPreview: SessionPreview = .empty

    /// The most recent leech event detected during this session, if any.
    public private(set) var lastLeechEvent: LeechEvent?

    /// Companion intervention content (message/mnemonic/quiz) for
    /// `lastLeechEvent`, sourced from the same-JLPT-level content bundle when
    /// available. Set alongside `lastLeechEvent` — nil until the first leech
    /// of the session fires, then holds the most recent one's intervention.
    public private(set) var lastLeechIntervention: LeechIntervention?

    /// Count of consecutive correct answers in this session (display/Live
    /// Activity streak only — no longer feeds loot RNG since loot retirement).
    public private(set) var consecutiveCorrect: Int = 0

    /// XP bonus awarded at session end for daily engagement / streak (nil if none).
    public private(set) var lastSessionBonus: SessionBonusService.Result?

    /// Monotonic count of grading transactions whose persistence failed.
    /// Bumped in `gradeAndAdvance` when `CardSaveErrorMonitor` reports a
    /// failure right after the grade write; `ActiveSessionView` observes it
    /// to surface a "your review may not count" toast. The monitor is cleared
    /// once consumed so a failure is surfaced exactly once.
    public private(set) var gradeSaveFailureCount: Int = 0

    // MARK: - Dependencies

    private let plannerService: PlannerService
    private let sessionPlanner: any SessionPlanner
    private let unlockService: any ExerciseUnlockService
    private let cardRepository: CardRepository
    /// Read-only static-content facade (bundled SQLite). Optional so existing
    /// call sites (previews, tests) compile unchanged; `nil` yields an empty
    /// `vocabularyPool` and the audio drills degrade gracefully. Injected by
    /// `HomeView.initializeViewModels()` in production (blueprint 4.1 Step 0).
    private let contentRepository: ContentRepository?
    private let modelContainer: ModelContainer
    private let liveActivityManager = LiveActivityManager()
    /// Foreground-only elapsed-time bookkeeping, extracted off this class
    /// (remediation 8.4) — see `SessionTimerCoordinator`.
    private let timerCoordinator = SessionTimerCoordinator()
    /// RPG XP/level persistence + finalization, extracted off this
    /// class (remediation 8.4) — see `SessionRPGPersistence`.
    private let rpgPersistence: SessionRPGPersistence
    /// `SessionPlanner`-pipeline session composition, extracted off this
    /// class (remediation 8.4) — see `SessionComposer`.
    private let sessionComposer: SessionComposer
    private var cardStartTime: Date = Date()

    /// Policy that decides when an active session ends. Built when the
    /// session starts; nil between sessions. Drives both queue-exhaustion
    /// and time-budget-exhaustion exits.
    private var endPolicy: SessionEndPolicy?

    /// JLPT level used to scale per-exercise XP awards via
    /// `ExerciseXP.multiplier(for:)`. Captured from the learner snapshot
    /// at session-start so every grade in the session uses a consistent
    /// difficulty multiplier. Defaults to N5.
    private var sessionJLPTLevel: JLPTLevel = .n5

    /// Accumulates per-skill XP for the active session. Read-side via
    /// `skillContribution`; the actor itself is fresh per session.
    private var ledger = SkillXPLedger()

    /// Per-skill XP earned in the active session. Drives the four-winds
    /// row on `SessionSummaryView`. Reset to `.zero` on session start;
    /// updated after every grade.
    public private(set) var skillContribution: SessionSkillContribution = .zero

    /// User-tunable target session duration (minutes). Read from `@AppStorage`
    /// so changes in Settings reflect immediately without rebuilding the VM.
    @ObservationIgnored
    @AppStorage("ikeru.session.defaultDurationMinutes")
    private var defaultDurationMinutes: Int = 15

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

    // MARK: - Session Lifecycle

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
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        startTimer()
        await loadRPGState()
        liveActivityManager.startActivity(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Session started via SessionPlanner: \(composed.sessionExercises.count) exercises (\(composed.srsCardCount) SRS), ~\(composed.estimatedDurationMinutes)min"
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
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        startTimer()
        await loadRPGState()
        liveActivityManager.startActivity(totalExercises: composed.sessionExercises.count)

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
        liveActivityManager.startActivity(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Review-mistakes session started: \(composed.sessionExercises.count) cards"
        )
    }

    /// Computes a session preview without starting the session.
    /// Uses adaptive composition to provide detailed exercise breakdown.
    /// - Parameter config: Session configuration (time, mode, balances).
    public func loadSessionPreview(config: SessionConfig = SessionConfig()) async {
        let result = await sessionComposer.composePreview(config: config)
        sessionPreview = result.preview
        estimatedCardCount = result.totalExercises

        Logger.ui.info(
            "Session preview loaded: \(result.totalExercises) exercises, ~\(result.totalSeconds / 60) min"
        )
    }

    /// Starts an adaptive session using the provided config.
    /// Falls back to basic composition if adaptive session produces no exercises.
    /// - Parameter config: Session configuration for adaptive composition.
    public func startAdaptiveSession(config: SessionConfig) async {
        guard let composed = await sessionComposer.composeAdaptive(config: config) else {
            // Fallback to basic composition
            await startSession()
            return
        }

        sessionQueue = composed.sessionQueue
        resetSessionState()
        estimatedCardCount = composed.sessionExercises.count

        // Store full exercise list for immersive mode
        sessionExercises = composed.sessionExercises
        cardsNeedingPresentation = composed.cardsNeedingPresentation
        planEstimatedDurationMinutes = composed.estimatedDurationMinutes

        // Start timer
        startTimer()

        await loadRPGState()

        // Start Live Activity for Dynamic Island
        liveActivityManager.startActivity(totalExercises: composed.sessionExercises.count)

        Logger.ui.info(
            "Adaptive session started: \(composed.srsCardCount) SRS cards, \(composed.supplementaryExerciseCount) supplementary"
        )
    }

    /// Grades the current card and advances to the next one.
    /// - Parameter grade: The grade to apply.
    public func gradeAndAdvance(grade: Grade) async {
        guard let card = currentCard else { return }

        // Defensive: the production UI never reaches this path while
        // presenting a new-card intro — `ExerciseTransitionContainer`
        // branches to `NewCardPresentationView` (no grade buttons, no swipe
        // gesture) whenever `isPresentingNewCard` is true. This guard exists
        // so any OTHER caller (a future UI path, a test driving the view
        // model directly) can't accidentally write a real FSRS grade for an
        // ungraded intro — it silently routes to the correct "acknowledge,
        // don't grade" behavior instead.
        if isPresentingNewCard {
            await completeNewCardPresentation()
            return
        }

        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // Recall succeeded whenever the grade wasn't `.again` — `.hard` means
        // slow-but-correct, so it counts as a pass for the recall % (see
        // `correctCount`), consistent with `missedCardIDs` below only
        // treating `.again` as a miss.
        let isRecallSuccess = grade != .again

        // Show feedback. `.hard` gets its own `.partial` treatment: it's not
        // the full "correct" green (the recall was slow), but it's not the
        // "incorrect" red of an actual miss either.
        let newFeedbackState: FeedbackState = switch grade {
        case .again: .incorrect
        case .hard: .partial
        case .good, .easy: .correct
        }
        feedbackState = newFeedbackState

        // Track only .again grades as mistakes. A .hard grade means the recall
        // was slow but ultimately correct — counting it as a miss conflated
        // slow recall with failure and drilled cards the user actually knew.
        if grade == .again {
            missedCardIDs.insert(card.id)
            requeueFailedCard(card)
        }

        // Hoisted above the grade write (pure function of `card`, no side
        // effects) so the SAME resolved type feeds both the persisted
        // ReviewLog.exerciseType (provenance, learner-telemetry lot 1) and
        // the XP award below — one source of truth, not two computations
        // that could drift apart.
        let exerciseType = SessionExerciseSupport.exerciseTypeForCurrentReview(card: card)

        await gradeCardAndCheckSaveErrors(
            card: card,
            grade: grade,
            responseTimeMs: responseTimeMs,
            exerciseType: exerciseType
        )

        // Award XP via ExerciseXP (per-type × JLPT-level multiplier),
        // delegating to RPGService for level-up bookkeeping. Flashcard
        // types still match `xpForGrade` totals (delegation in the rule
        // table), so kana-only N5 sessions award the same XP as before.
        await awardExerciseXP(type: exerciseType, grade: grade, sampledTelemetry: true)

        // Track consecutive correct (display / Live Activity streak only).
        trackCorrectness(isCorrect: isRecallSuccess)

        // Card-derived grade side-effects (first-review `newItemsLearned`
        // counting, leech detection). Extracted so the `.kanjiStudy` drill
        // path in `completeCurrentExercise` runs the SAME bookkeeping — a
        // kanji card that becomes a leech or is newly learned is detected
        // regardless of which UI graded it. Called here at the exact
        // position (after the XP/RPG update, before either index advances)
        // so SRS behavior is byte-for-byte unchanged.
        await applyCardGradeSideEffects(preGradeCard: card, grade: grade)

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        // Update Live Activity with current progress
        await reportLiveActivityProgress()

        // Advance exercise index to stay in sync
        advanceToNextExercise()

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(300))
        feedbackState = nil

        await finishSessionIfNeeded()
    }

    /// Where every `ReviewLog` written by this view model came from. The main
    /// SRS session runs only on iPhone today — no Watch call site persists a
    /// `ReviewLog` yet — so this is the one constant value for the whole file.
    /// See `ReviewLog.surface`.
    private static let reviewSurface = "iphone.session"

    /// Persists a card's FSRS grade and surfaces persistence failures. Shared
    /// by the SRS deck path (`gradeAndAdvance`, always grades `currentCard`)
    /// and the non-SRS drill path (`completeCurrentExercise`, conditionally
    /// grades its `gradeableCard`) — both write the identical FSRS grade +
    /// save-error-monitor check. A grade whose save failed may not count
    /// toward scheduling; this checks once right after the write and clears
    /// the monitor so the same failure isn't re-surfaced on the next card.
    ///
    /// `answeredValue` is never passed here — every grade reaching this layer
    /// came from a self-graded Again/Hard/Good/Easy button, not a choice-format
    /// exercise, so there is no "chosen value" to log (stays `nil` on the
    /// persisted `ReviewLog`). Choice-format session exercises exist elsewhere
    /// (e.g. vocabulary recall options) but their chosen answers aren't
    /// plumbed to this layer yet — out of this lot's scope, not an oversight.
    private func gradeCardAndCheckSaveErrors(
        card: CardDTO,
        grade: Grade,
        responseTimeMs: Int,
        exerciseType: ExerciseType
    ) async {
        Logger.srs.debug(
            "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
        )
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: responseTimeMs,
            exerciseType: exerciseType.rawValue,
            surface: Self.reviewSurface
        )
        if cardRepository.saveErrorMonitor.lastSaveError != nil {
            cardRepository.saveErrorMonitor.clear()
            gradeSaveFailureCount += 1
        }
    }

    /// Updates the display-only correctness streak. Shared by `gradeAndAdvance`
    /// and `completeCurrentExercise` — both apply the identical increment/reset.
    private func trackCorrectness(isCorrect: Bool) {
        gradedAttemptCount += 1
        if isCorrect {
            consecutiveCorrect += 1
            correctCount += 1
        } else {
            consecutiveCorrect = 0
        }
    }

    /// Reports current progress to the Live Activity / Dynamic Island.
    /// Shared by `gradeAndAdvance` and `completeCurrentExercise` — both read
    /// `currentExercise` for the label at the exact same point (after
    /// `reviewedCount`/index bookkeeping, before the exercise pointer
    /// advances), so both see the just-completed exercise, matching the
    /// original per-call-site computation exactly.
    private func reportLiveActivityProgress() async {
        let exerciseLabel = currentExercise.map { SessionExerciseSupport.exerciseDisplayName($0) } ?? "Review"
        await liveActivityManager.updateActivity(
            elapsedSeconds: Int(elapsedTime),
            exerciseType: exerciseLabel,
            completedCount: reviewedCount,
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )
    }

    /// XP-award bookkeeping shared by the SRS deck path (`gradeAndAdvance`)
    /// and the non-SRS drill path (`completeCurrentExercise`): computes the
    /// per-type × JLPT-level XP via `ExerciseXP.award`, delegates to
    /// `RPGService` for level-up bookkeeping, records per-skill attribution
    /// into the session ledger, persists RPG state, and sets `levelUpLevel`
    /// on level-up. `sampledTelemetry` gates the 10%-sampled `xp.attributed`
    /// log line, which only `gradeAndAdvance` originally emitted (the SRS
    /// deck path is the high-volume event the sampling comment refers to).
    @discardableResult
    private func awardExerciseXP(type: ExerciseType, grade: Grade, sampledTelemetry: Bool) async -> Int {
        let xpAmount = ExerciseXP.award(type: type, level: sessionJLPTLevel, grade: grade)
        let result = RPGService.awardXP(
            amount: xpAmount,
            currentXP: totalXP,
            currentLevel: currentLevel,
            totalReviews: reviewedCount
        )

        totalXP = result.newXP
        currentLevel = result.newLevel
        xpEarned += result.xpAwarded
        lastXPGained = result.xpAwarded

        // Record per-skill attribution into the session ledger; surfaces
        // on SessionSummaryView's four-winds row.
        Task { [ledger] in
            await ledger.record(xp: xpAmount, exerciseType: type)
            let snap = await ledger.snapshot()
            await MainActor.run { self.skillContribution = snap }
        }

        // 10% sampled telemetry — high-volume event, full coverage would
        // bloat the log. Sampling rate documented in the design doc.
        if sampledTelemetry, Int.random(in: 0..<100) < 10 {
            Logger.ui.info(
                "xp.attributed type=\(type.rawValue, privacy: .public) level=\(self.sessionJLPTLevel.rawValue, privacy: .public) finalXP=\(xpAmount, privacy: .public)"
            )
        }

        // Persist RPG state
        await persistRPGState()

        // Check for level-up
        if result.didLevelUp {
            levelUpLevel = result.newLevel
        }

        return xpAmount
    }

    /// Ends and finalizes the session when it should stop — exercise-list
    /// exhaustion OR the time-budget policy firing. Shared by `gradeAndAdvance`
    /// (SRS deck path) and `completeCurrentExercise` (non-SRS drill path) so both
    /// routes finalize identically. No-op until `shouldEndSession` is true.
    private func finishSessionIfNeeded() async {
        guard shouldEndSession else { return }
        stopTimer()
        await finalizeSession()
        await liveActivityManager.endActivity(
            elapsedSeconds: Int(elapsedTime),
            completedCount: reviewedCount,
            // Total is the exercise-list length, matching `updateActivity`
            // (which already reports `sessionExercises.count`). With mixed
            // SRS + drill sessions now reachable, `sessionQueue.count` (SRS-only)
            // would under-report the denominator on the ending Live Activity.
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )
        // Force BOTH pointers past their ends so views that observe
        // `isSessionComplete` (computed: currentExerciseIndex >=
        // sessionExercises.count) route to the summary even when the time
        // budget — not exercise-list exhaustion — fired the end. The two guards
        // are independent because the SRS queue and the exercise list can now
        // differ in length; draining only one would leave the session neither
        // complete nor advancing.
        let queueDrained = reviewedCount >= sessionQueue.count
        if currentIndex < sessionQueue.count {
            currentIndex = sessionQueue.count
        }
        if currentExerciseIndex < sessionExercises.count {
            currentExerciseIndex = sessionExercises.count
        }
        let budgetMinutes = self.endPolicy?.durationBudgetMinutes ?? 0
        let queueLength = self.sessionQueue.count
        if queueDrained {
            Logger.ui.info(
                "session.ended.queue durationMinutes=\(budgetMinutes, privacy: .public) elapsedSeconds=\(Int(self.elapsedTime), privacy: .public) completedCount=\(self.reviewedCount, privacy: .public) queueLength=\(queueLength, privacy: .public) xpEarned=\(self.xpEarned, privacy: .public)"
            )
        } else {
            Logger.ui.info(
                "session.ended.budget durationMinutes=\(budgetMinutes, privacy: .public) elapsedSeconds=\(Int(self.elapsedTime), privacy: .public) completedCount=\(self.reviewedCount, privacy: .public) queueLength=\(queueLength, privacy: .public) xpEarned=\(self.xpEarned, privacy: .public)"
            )
        }
    }

    /// Single completion entry point for a NON-SRS exercise (kanji study,
    /// writing, sentence construction, listening, …) surfaced by the immersive
    /// drill container. SRS flashcards keep grading through `gradeAndAdvance`;
    /// this method exists so a non-card exercise can be completed without
    /// corrupting the SRS card-queue pointer.
    ///
    /// Index discipline (the core of the 4.1 decoupling):
    /// - `currentExerciseIndex` ALWAYS advances — every exercise is consumed.
    /// - `currentIndex` (the `sessionQueue` pointer) advances ONLY for
    ///   `.srsReview`. `sessionQueue` is built from `.srsReview` payloads alone,
    ///   so a `.kanjiStudy` card is never in it; advancing the queue pointer for
    ///   it would over-run the queue and mis-grade the next real review.
    ///   Invariant held: `currentIndex` == number of completed `.srsReview`
    ///   items == index into `sessionQueue`.
    /// - `.kanjiStudy` and `.writingPractice` each write a real FSRS grade
    ///   against their backing `CardDTO` (the 4.4 hook) but do NOT touch
    ///   `currentIndex`; every other non-SRS kind is XP-only.
    ///
    /// Reachable in production: `DefaultSessionPlanner` schedules the wired
    /// non-SRS drills (`.kanjiStudy`, `.writingPractice`, `.sentenceConstruction`,
    /// listening / shadowing / vocabulary) via its `isLive` allowlist. It is also
    /// exercised by the decoupling regression tests.
    public func completeCurrentExercise(grade: Grade) async {
        guard let exercise = currentExercise else { return }

        // SRS reviews grade through the deck path so their full card-centric
        // behavior (mistake tracking, same-day requeue, leech detection,
        // new-item counting) is preserved exactly.
        if case .srsReview = exercise {
            await gradeAndAdvance(grade: grade)
            return
        }

        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // `.kanjiStudy` and `.writingPractice` both carry a real, gradeable
        // card, so write their FSRS grade WITHOUT advancing `currentIndex`
        // (their cards are not in `sessionQueue`). Every other non-SRS kind is
        // XP-only (no backing card). XP is still awarded below for all kinds.
        //
        // `nonSRSGradedCardIDs` de-dupes: if this same card was already graded
        // through this path earlier in the session (kanjiStudy + writingPractice
        // can both target it), skip the second FSRS write + side-effects so one
        // character isn't counted as two independent reviews. XP still accrues.
        let gradeableCard: CardDTO?
        switch exercise {
        case .kanjiStudy(let card), .writingPractice(let card):
            gradeableCard = nonSRSGradedCardIDs.contains(card.id) ? nil : card
        default:
            gradeableCard = nil
        }
        // Hoisted above the grade write — see `gradeAndAdvance`'s identical
        // reasoning for why the resolved type feeds both the persisted
        // ReviewLog.exerciseType and the XP award below from one computation.
        let resolvedType = SessionExerciseSupport.exerciseType(for: exercise)
        if let card = gradeableCard {
            nonSRSGradedCardIDs.insert(card.id)
            await gradeCardAndCheckSaveErrors(
                card: card,
                grade: grade,
                responseTimeMs: responseTimeMs,
                exerciseType: resolvedType
            )
        }

        // Award XP for the exercise kind (per-type × JLPT-level multiplier).
        // `grade` is forwarded for `.perGrade` kinds (e.g. kanjiStudy) and
        // ignored by the rule table for `.perCompletion` kinds.
        await awardExerciseXP(type: resolvedType, grade: grade, sampledTelemetry: false)

        // Track consecutive / total correct (display only). `.hard` counts as
        // a pass here too — see `correctCount`'s doc comment / `gradeAndAdvance`
        // for why: it's slow-but-correct recall, not a miss.
        trackCorrectness(isCorrect: grade != .again)

        // The card-backed kinds (`.kanjiStudy`, `.writingPractice`) run the
        // shared card-grade side-effects: leech detection and first-review
        // counting, identical to the SRS deck path. Positioned after
        // the XP/RPG update (parity with `gradeAndAdvance`) and before the
        // exercise pointer advances. Every other non-SRS kind is XP-only.
        if let card = gradeableCard {
            await applyCardGradeSideEffects(preGradeCard: card, grade: grade)
        }

        // Persist pool-based output outcomes (listening / shadowing) — these have
        // no backing FSRS card, so their accuracy is recorded here instead. It
        // feeds `LearnerSnapshot.listeningAccuracyLast30` / `listeningRecallLast30Days`
        // (which unlock `.listeningUnsubtitled` / `.speakingPractice`) and the
        // speaking axis of `SkillBalanceSnapshot` (remediation 4.4). A skip via
        // DrillUnavailableView arrives as `.again` → 0.0, which conservatively
        // (never falsely) keeps the gates locked.
        switch exercise {
        case .listeningExercise, .speakingExercise:
            let accuracy = ExerciseOutcomeAccuracy.from(grade: grade, skill: exercise.skill)
            await cardRepository.recordExerciseOutcome(skill: exercise.skill, accuracy: accuracy)
        default:
            break
        }

        // `reviewedCount` counts completed exercises (not just SRS cards): it
        // gates the time-budget policy's `completedCount`, the endSession
        // zero-skip, the Live Activity, and the abandon label — so a non-SRS
        // completion must bump it too.
        reviewedCount += 1
        cardStartTime = Date()

        // Update Live Activity with current progress (label = the just-completed
        // exercise, mirroring gradeAndAdvance's ordering).
        await reportLiveActivityProgress()

        // Advance the exercise pointer (never the SRS queue pointer here).
        advanceToNextExercise()

        await finishSessionIfNeeded()
    }

    /// Acknowledges the ungraded new-card presentation pass (see
    /// `isPresentingNewCard`/`cardsNeedingPresentation`) and advances past
    /// it. Deliberately does NOT write any FSRS grade and does NOT touch
    /// `correctCount` / `missedCardIDs` / `newItemsLearned` /
    /// `gradedAttemptCount` — those are earned by this SAME card's delayed
    /// `.srsReview` occurrence a few exercises later, which still routes
    /// through the untouched `gradeAndAdvance` and is the card's real first
    /// FSRS grade (`effects.isNewItem` fires there, not here).
    ///
    /// `currentIndex` still advances: this occurrence IS one of
    /// `sessionQueue`'s `.srsReview` slots (see `NewCardPresentationScheduler`
    /// in `SessionComposer.swift`), so the queue/exercise pointers stay in
    /// lockstep exactly as they do for a graded card — see
    /// `isSessionComplete`'s doc comment on that invariant.
    ///
    /// `reviewedCount` DOES advance: it took real session time and gates
    /// the time-budget policy's `completedCount`
    /// (`SessionEndPolicy.queueLength` was sized to include this occurrence
    /// — see `SessionComposer`), the Live Activity, and the abandon-dialog
    /// label. It is intentionally NOT the denominator `SessionSummaryView`
    /// uses for recall % — see `gradedAttemptCount`.
    public func completeNewCardPresentation() async {
        guard case .srsReview(let card) = currentExercise else { return }
        cardsNeedingPresentation.remove(card.id)

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        await reportLiveActivityProgress()
        advanceToNextExercise()

        await finishSessionIfNeeded()
    }

    // MARK: - Session Finalization

    /// Applies end-of-session effects: daily/streak bonus.
    /// Runs once when the session's last card has been graded. Persistence +
    /// bonus computation live in `SessionRPGPersistence.finalize`
    /// (remediation 8.4 extraction); this wrapper applies the result onto
    /// `@Observable` state with the exact same conditionals as the original
    /// inline implementation (e.g. `totalXP`/`currentLevel`/`levelUpLevel`
    /// only change when `bonusXPAwarded > 0`, matching the original's
    /// `if bonus.bonusXP > 0` gate).
    private func finalizeSession() async {
        guard let result = await rpgPersistence.finalize(
            currentXP: totalXP,
            currentLevel: currentLevel
        ) else { return }

        if result.bonusXPAwarded > 0 {
            totalXP = result.updatedTotalXP
            xpEarned += result.bonusXPAwarded
            if result.didLevelUp {
                levelUpLevel = result.updatedLevel
                currentLevel = result.updatedLevel
            }
        }

        lastSessionBonus = result.bonus
    }

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
    public func endSession() {
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

        // End Live Activity
        Task {
            await liveActivityManager.endActivity(
                elapsedSeconds: Int(elapsedTime),
                completedCount: reviewedCount,
                // Exercise-list length, matching updateActivity / finishSessionIfNeeded.
                // On an abandoned mixed SRS + drill session, sessionQueue.count
                // (SRS-only) would under-report and make completedCount > totalCount.
                totalCount: sessionExercises.count,
                xpEarned: xpEarned,
                streakCount: consecutiveCorrect
            )
        }

        // Mark as complete by jumping to end of queue
        currentIndex = sessionQueue.count
        currentExerciseIndex = sessionExercises.count
        isPaused = false
        showAbandonConfirmation = false
        stopTimer()

        Task { await processNewlyUnlocked() }
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
    private func startTimer() {
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
    private func stopTimer() {
        timerCoordinator.stop()
    }

    // MARK: - RPG State Persistence

    /// Loads the active profile's RPG state, creating one if the profile lacks it.
    private func loadRPGState() async {
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

    /// Persists current RPG state to SwiftData.
    private func persistRPGState() async {
        await rpgPersistence.persistState(xp: totalXP, level: currentLevel)
    }

    // MARK: - Same-Day Re-Queue

    /// Same-day intra-session re-queue: a card graded `.again` comes back later
    /// in the same session instead of disappearing until its next FSRS due date.
    /// Mistakes mode appends to the end (drill-until-done); normal sessions
    /// re-insert 3-5 positions later. Capped at `maxRetriesPerCard`.
    private func requeueFailedCard(_ card: CardDTO) {
        let retries = retryCounts[card.id, default: 0]
        guard let result = SessionRequeuePlanner.requeue(
            card: card,
            currentRetryCount: retries,
            maxRetries: Self.maxRetriesPerCard,
            sessionMode: sessionMode,
            currentExerciseIndex: currentExerciseIndex,
            sessionQueue: sessionQueue,
            sessionExercises: sessionExercises,
            endPolicy: endPolicy
        ) else { return }

        retryCounts[card.id] = result.retryCount
        sessionQueue = result.sessionQueue
        sessionExercises = result.sessionExercises
        endPolicy = result.endPolicy

        Logger.srs.info(
            "Same-day requeue: \(card.front, privacy: .public) (retry \(result.retryCount)/\(Self.maxRetriesPerCard, privacy: .public))"
        )
    }

}

// MARK: - Card-Grade Side Effects (extracted to keep the class body under type_body_length)
extension SessionViewModel {
    /// Card-derived grade side-effects shared by the SRS deck path
    /// (`gradeAndAdvance`) and the `.kanjiStudy` drill path
    /// (`completeCurrentExercise`). Detection/persistence logic lives in
    /// `SessionRPGPersistence.applyCardGradeSideEffects` (remediation 8.4
    /// extraction); this wrapper applies the result onto `@Observable` state.
    ///
    /// Must be called AFTER the XP/RPG update and BEFORE either index advances.
    ///
    /// NOTE: mistake tracking + same-day requeue (`missedCardIDs` /
    /// `requeueFailedCard`) are deliberately NOT here — that stays in the
    /// `.srsReview` deck path (`gradeAndAdvance`).
    private func applyCardGradeSideEffects(preGradeCard card: CardDTO, grade: Grade) async {
        let effects = await rpgPersistence.applyCardGradeSideEffects(
            preGradeCard: card,
            grade: grade,
            alreadyCountedNewItem: newItemCountedIDs.contains(card.id),
            contentRepository: contentRepository
        )
        if effects.isNewItem {
            newItemCountedIDs.insert(card.id)
            newItemsLearned += 1
        }
        if let leechEvent = effects.leechEvent {
            lastLeechEvent = leechEvent
            lastLeechIntervention = effects.intervention
        }
    }
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
