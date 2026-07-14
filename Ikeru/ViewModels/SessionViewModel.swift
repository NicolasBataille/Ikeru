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
    case incorrect

    public var color: Color {
        switch self {
        case .correct: Color(hex: IkeruTheme.Colors.success)        // jade green
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

    /// Total cards graded `.good` or `.easy` this session. Used by the
    /// summary's recall % — *not* `consecutiveCorrect`, because that
    /// resets on any miss and made recall always read 0% the moment the
    /// user hit a single .hard or .again, even if every other card was
    /// correct.
    public private(set) var correctCount: Int = 0

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
    public private(set) var elapsedTime: TimeInterval = 0

    /// Whether the ContinuousClock timer is actively ticking.
    public private(set) var isTimerRunning: Bool = false

    /// Fires once when the active session crosses the (durationBudget − 60s)
    /// mark. Drives the "1 minute remaining" toast on `ActiveSessionView`.
    /// Reset to false on each new session.
    public private(set) var oneMinuteRemainingFired: Bool = false

    /// Formatted elapsed time string (MM:SS).
    public var elapsedTimeFormatted: String {
        formatTime(elapsedTime)
    }

    /// Estimated total session duration in seconds, computed from exercise list.
    public var estimatedTotalTime: TimeInterval {
        TimeInterval(sessionExercises.reduce(0) { $0 + $1.estimatedDurationSeconds })
    }

    /// Estimated remaining time in seconds.
    public var estimatedRemainingTime: TimeInterval {
        max(0, estimatedTotalTime - elapsedTime)
    }

    /// Formatted estimated remaining time string ("-MM:SS").
    public var estimatedRemainingTimeFormatted: String {
        "-" + formatTime(estimatedRemainingTime)
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

    /// Loot item dropped from the most recent review (drives LootDropView overlay).
    public private(set) var lastLootDrop: LootItem?

    /// Count of consecutive correct answers in this session (affects loot drop rate).
    public private(set) var consecutiveCorrect: Int = 0

    /// Total loot items earned this session.
    public private(set) var sessionLootCount: Int = 0

    /// Lootbox earned during this session (presented after session summary).
    public private(set) var earnedLootBox: LootBox?

    /// XP bonus awarded at session end for daily engagement / streak (nil if none).
    public private(set) var lastSessionBonus: SessionBonusService.Result?

    /// Mastery events detected during this session (graduation, burns, etc.).
    public private(set) var sessionMasteryEvents: [MasteryEvent] = []

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
    private var cardStartTime: Date = Date()
    private var timerTask: Task<Void, Never>?

    /// Accumulated active time from completed intervals (before the current
    /// timer run). Updated whenever the timer is paused mid-session so that
    /// background time is excluded from the session duration.
    private var baseElapsedTime: TimeInterval = 0

    /// Wall-clock anchor for the current timer run. Set whenever `startTimer()`
    /// begins a new interval so elapsed = base + (now − resume).
    private var timerResumeTime: Date = Date()

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
        lastLootDrop = nil
        consecutiveCorrect = 0
        correctCount = 0
        missedCardIDs = []
        sessionMode = .normal
        retryCounts = [:]
        newItemCountedIDs = []
        nonSRSGradedCardIDs = []
        sessionLootCount = 0
        earnedLootBox = nil
        lastSessionBonus = nil
        sessionMasteryEvents = []
        gradeSaveFailureCount = 0
        isPaused = false
        sessionStartTime = Date()
        cardStartTime = Date()
        isActive = true
        currentExerciseIndex = 0
        showAbandonConfirmation = false
        elapsedTime = 0
        baseElapsedTime = 0
        timerResumeTime = Date()
        endPolicy = nil
        oneMinuteRemainingFired = false
        ledger = SkillXPLedger()
        skillContribution = .zero
        vocabularyPool = []
    }

    /// Composes a session queue via the new `SessionPlanner` pipeline and
    /// starts the session. Builds a `LearnerSnapshot` from the live card
    /// pool, resolves unlocked exercise types, and asks the planner for a
    /// home-recommendation plan tuned to `defaultDurationMinutes`.
    @discardableResult
    public func startSession() async -> Bool {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let unlockedTypes = effectiveUnlockedTypes(profile: snapshot)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: defaultDurationMinutes,
            profile: snapshot,
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)

        // Extract CardDTOs from SRS review exercises for the swipeable queue.
        // Non-SRS exercises (variety / new content tiles) are still tracked
        // in `sessionExercises` so immersive mode can render them.
        let srsCards = plan.exercises.compactMap { exercise -> CardDTO? in
            if case .srsReview(let card) = exercise { return card }
            return nil
        }

        // Never start an empty session — it would drop the user straight into a
        // hollow "0 cards / 0% recall" summary that reads as failure. Guard at
        // the source so no timer / Live Activity spins up for nothing. The Home
        // CTA is also gated when nothing is composable.
        guard !srsCards.isEmpty else {
            Logger.ui.info("startSession: composed plan is empty — not starting")
            return false
        }

        sessionQueue = srsCards
        resetSessionState()
        estimatedCardCount = plan.exercises.count

        // Store full exercise list for immersive mode.
        sessionExercises = plan.exercises

        endPolicy = SessionEndPolicy(
            durationBudgetMinutes: defaultDurationMinutes,
            queueLength: plan.exercises.count
        )
        sessionJLPTLevel = snapshot.jlptLevel

        // Fetch the session-scoped vocabulary pool for the audio drills, at the
        // same level used for the XP multiplier. Fail-safe: no repository or an
        // empty level yields an empty pool (the drill container degrades).
        await loadVocabularyPool(level: sessionJLPTLevel)

        // Start timer
        startTimer()

        // Load persisted RPG state
        await loadRPGState()

        // Start Live Activity for Dynamic Island
        liveActivityManager.startActivity(totalExercises: plan.exercises.count)

        Logger.ui.info(
            "Session started via SessionPlanner: \(plan.exercises.count) exercises (\(srsCards.count) SRS), ~\(plan.estimatedDurationMinutes)min"
        )
        return true
    }

    /// Loads and maps the session vocabulary pool for the audio drills
    /// (Shadowing / Listening). No-op leaving an empty pool when no
    /// `ContentRepository` was injected (previews / tests) — never throws,
    /// never blocks the session start on a failed content read.
    private func loadVocabularyPool(level: JLPTLevel) async {
        guard let contentRepository else {
            vocabularyPool = []
            return
        }
        let rows = await contentRepository.vocabularyByLevel(level)
        vocabularyPool = VocabularyItemMapper.map(rows)
        Logger.ui.info(
            "session.vocabPool level=\(level.rawValue, privacy: .public) count=\(self.vocabularyPool.count, privacy: .public)"
        )
    }

    /// Composes a custom session from the Étude → Compose sheet. Same
    /// pipeline as `startSession()` but with `.studyCustom` as the planner
    /// source so the planner respects the user's chosen exercise types
    /// and JLPT levels rather than the home recommendation skeleton.
    public func startStudyCustomSession(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) async {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let unlockedTypes = effectiveUnlockedTypes(profile: snapshot)
        let inputs = SessionPlannerInputs(
            source: .studyCustom(types: types, jlptLevels: levels),
            durationMinutes: duration,
            profile: snapshot,
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)

        let srsCards = plan.exercises.compactMap { exercise -> CardDTO? in
            if case .srsReview(let card) = exercise { return card }
            return nil
        }

        sessionQueue = srsCards
        resetSessionState()
        estimatedCardCount = plan.exercises.count
        sessionExercises = plan.exercises

        endPolicy = SessionEndPolicy(
            durationBudgetMinutes: duration,
            queueLength: plan.exercises.count
        )
        // Custom sessions: use the highest selected JLPT level so the XP
        // multiplier matches the user's chosen difficulty rather than
        // their estimated level. Falls back to snapshot estimate if no
        // levels were selected (defensive — UI requires a selection).
        sessionJLPTLevel = levels.max() ?? snapshot.jlptLevel

        // Audio-drill pool at the session's difficulty (see startSession()).
        await loadVocabularyPool(level: sessionJLPTLevel)

        startTimer()
        await loadRPGState()
        liveActivityManager.startActivity(totalExercises: plan.exercises.count)

        Logger.ui.info(
            "Study custom session started: \(plan.exercises.count) exercises (\(srsCards.count) SRS), ~\(plan.estimatedDurationMinutes)min"
        )
    }

    /// Restarts the session with only the cards graded `.again` in the
    /// previous session. Drives the summary screen's "Review mistakes" CTA.
    /// No-op if the missed-set is empty (button should be hidden in that
    /// case, but the guard keeps callers safe).
    public func startReviewMistakes() async {
        let mistakeIDs = missedCardIDs
        guard !mistakeIDs.isEmpty else { return }
        let allCards = await cardRepository.allCards()
        let mistakes = allCards.filter { mistakeIDs.contains($0.id) }
        guard !mistakes.isEmpty else { return }

        sessionQueue = mistakes
        resetSessionState()
        sessionMode = .reviewMistakes
        estimatedCardCount = mistakes.count
        sessionExercises = mistakes.map { ExerciseItem.srsReview($0) }

        endPolicy = SessionEndPolicy(
            durationBudgetMinutes: defaultDurationMinutes,
            queueLength: mistakes.count
        )
        // Review-mistakes carries forward whatever level the prior session
        // ran at — the cards themselves haven't changed.
        // sessionJLPTLevel intentionally not reset here.

        startTimer()
        await loadRPGState()
        liveActivityManager.startActivity(totalExercises: mistakes.count)

        Logger.ui.info(
            "Review-mistakes session started: \(mistakes.count) cards"
        )
    }

    /// Computes a session preview without starting the session.
    /// Uses adaptive composition to provide detailed exercise breakdown.
    /// - Parameter config: Session configuration (time, mode, balances).
    public func loadSessionPreview(config: SessionConfig = SessionConfig()) async {
        let plan = await plannerService.composeAdaptiveSession(config: config)
        let totalExercises = plan.exercises.count
        let totalSeconds = plan.exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }

        var skillSplit: [SkillType: Double] = [:]
        if totalExercises > 0 {
            for (skill, count) in plan.exerciseBreakdown {
                skillSplit[skill] = Double(count) / Double(totalExercises)
            }
        }

        sessionPreview = SessionPreview(
            estimatedMinutes: plan.estimatedDurationMinutes,
            cardCount: totalExercises,
            exerciseBreakdown: plan.exerciseBreakdown,
            skillSplit: skillSplit
        )

        estimatedCardCount = totalExercises

        Logger.ui.info(
            "Session preview loaded: \(totalExercises) exercises, ~\(totalSeconds / 60) min"
        )
    }

    /// Starts an adaptive session using the provided config.
    /// Falls back to basic composition if adaptive session produces no exercises.
    /// - Parameter config: Session configuration for adaptive composition.
    public func startAdaptiveSession(config: SessionConfig) async {
        let plan = await plannerService.composeAdaptiveSession(config: config)

        if plan.exercises.isEmpty {
            // Fallback to basic composition
            await startSession()
            return
        }

        // Extract CardDTOs from SRS review exercises for the queue
        let srsCards = plan.exercises.compactMap { exercise -> CardDTO? in
            if case .srsReview(let card) = exercise { return card }
            return nil
        }

        sessionQueue = srsCards
        resetSessionState()
        estimatedCardCount = plan.exercises.count

        // Store full exercise list for immersive mode
        sessionExercises = plan.exercises

        // Start timer
        startTimer()

        await loadRPGState()

        // Start Live Activity for Dynamic Island
        liveActivityManager.startActivity(totalExercises: plan.exercises.count)

        Logger.ui.info(
            "Adaptive session started: \(srsCards.count) SRS cards, \(plan.supplementaryExerciseCount) supplementary"
        )
    }

    /// Grades the current card and advances to the next one.
    /// - Parameter grade: The grade to apply.
    public func gradeAndAdvance(grade: Grade) async {
        guard let card = currentCard else { return }

        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // Show feedback
        let isCorrect = grade == .good || grade == .easy
        feedbackState = isCorrect ? .correct : .incorrect

        // Track only .again grades as mistakes. A .hard grade means the recall
        // was slow but ultimately correct — counting it as a miss conflated
        // slow recall with failure and drilled cards the user actually knew.
        if grade == .again {
            missedCardIDs.insert(card.id)
            requeueFailedCard(card)
        }

        Logger.srs.debug(
            "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
        )

        // Persist grade via repository
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: responseTimeMs
        )

        // Surface persistence failures: a grade whose save failed may not count
        // toward scheduling. Single check right after the write; clear the
        // monitor so the same failure isn't re-surfaced on the next card.
        if cardRepository.saveErrorMonitor.lastSaveError != nil {
            cardRepository.saveErrorMonitor.clear()
            gradeSaveFailureCount += 1
        }

        // Award XP via ExerciseXP (per-type × JLPT-level multiplier),
        // delegating to RPGService for level-up bookkeeping. Flashcard
        // types still match `xpForGrade` totals (delegation in the rule
        // table), so kana-only N5 sessions award the same XP as before.
        let exerciseType = exerciseTypeForCurrentReview(card: card)
        let xpAmount = ExerciseXP.award(
            type: exerciseType,
            level: sessionJLPTLevel,
            grade: grade
        )
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
        let recordedType = exerciseType
        let recordedAmount = xpAmount
        Task { [ledger] in
            await ledger.record(xp: recordedAmount, exerciseType: recordedType)
            let snap = await ledger.snapshot()
            await MainActor.run { self.skillContribution = snap }
        }

        // 10% sampled telemetry — high-volume event, full coverage would
        // bloat the log. Sampling rate documented in the design doc.
        if Int.random(in: 0..<100) < 10 {
            Logger.ui.info(
                "xp.attributed type=\(exerciseType.rawValue, privacy: .public) level=\(self.sessionJLPTLevel.rawValue, privacy: .public) finalXP=\(xpAmount, privacy: .public)"
            )
        }

        // Persist RPG state
        await persistRPGState()

        // Check for level-up
        if result.didLevelUp {
            levelUpLevel = result.newLevel
        }

        // Track consecutive correct (affects display only — no longer feeds loot RNG)
        if isCorrect {
            consecutiveCorrect += 1
            correctCount += 1
        } else {
            consecutiveCorrect = 0
        }

        // Card-derived grade side-effects (mastery detection + loot drop,
        // first-review `newItemsLearned` counting, leech detection). Extracted
        // so the `.kanjiStudy` drill path in `completeCurrentExercise` runs the
        // SAME bookkeeping — a kanji card that becomes a leech or is newly
        // learned is detected regardless of which UI graded it. Called here at
        // the exact position (after the XP/RPG update — the RNG drop reads the
        // post-award `currentLevel` — and before either index advances) so SRS
        // behavior is byte-for-byte unchanged.
        await applyCardGradeSideEffects(preGradeCard: card, grade: grade)

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        // Update Live Activity with current progress
        let exerciseLabel = currentExercise.map { exerciseDisplayName($0) } ?? "Review"
        await liveActivityManager.updateActivity(
            elapsedSeconds: Int(elapsedTime),
            exerciseType: exerciseLabel,
            completedCount: reviewedCount,
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )

        // Advance exercise index to stay in sync
        advanceToNextExercise()

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(300))
        feedbackState = nil

        // Check for lootbox milestone (every 25 reviews in session)
        if LootBoxService.shouldAwardLootBox(reviewsInSession: reviewedCount) {
            let box = LootBoxService.generateLootBox(level: currentLevel)
            earnedLootBox = box
            await persistLootBox(box)
        }

        await finishSessionIfNeeded()
    }

    /// Card-derived grade side-effects shared by the SRS deck path
    /// (`gradeAndAdvance`) and the `.kanjiStudy` drill path
    /// (`completeCurrentExercise`). Both grade a real FSRS `CardDTO`, so both
    /// must run identical detection/counting:
    ///   1. mastery events (Phase 3) → forced loot drop at event rarity, taking
    ///      priority over the RNG drop; else the RNG loot drop;
    ///   2. first-review `newItemsLearned` counting (reps was 0), deduped so a
    ///      same-day re-queued new card isn't double-counted;
    ///   3. leech detection.
    ///
    /// Must be called AFTER the XP/RPG update (the RNG drop reads the post-award
    /// `currentLevel`) and BEFORE either index advances.
    ///
    /// NOTE: mistake tracking + same-day requeue (`missedCardIDs` /
    /// `requeueFailedCard`) are deliberately NOT here. `requeueFailedCard`
    /// re-inserts an `.srsReview(card)` into `sessionQueue`, which holds SRS
    /// payloads only; a `.kanjiStudy` card is intentionally never in that queue
    /// (the §4.1 index-decoupling invariant), so requeuing it would silently
    /// convert a handwriting drill into a deck review. That stays in the
    /// `.srsReview` deck path (`gradeAndAdvance`).
    private func applyCardGradeSideEffects(preGradeCard card: CardDTO, grade: Grade) async {
        // Mastery events: pre-grade card state → forced drops at event rarity.
        // Detected BEFORE RNG drop so they always take priority when both would
        // fire. Named mastery drops (e.g. "First Steps") are once-per-profile —
        // if the inventory already contains the drop, skip it. Otherwise the
        // same badge would re-appear every time a new card is graded Good/Easy.
        lastLootDrop = nil
        let masteryEvents = MasteryEventDetector.detect(preGradeCard: card, grade: grade)
        if let event = masteryEvents.first {
            let drop = LootDropService.generateMasteryDrop(for: event, learnerLevel: sessionJLPTLevel)
            let alreadyOwned = await inventoryContains(name: drop.name)
            if !alreadyOwned {
                lastLootDrop = drop
                sessionLootCount += 1
                sessionMasteryEvents.append(event)
                await persistLootDrop(drop)
                Logger.rpg.info("Mastery drop: \(event.displayName) → \(drop.name) (\(drop.rarity.displayName))")
            } else {
                Logger.rpg.info("Mastery drop skipped (\(drop.name) already in inventory)")
            }
        } else if LootDropService.shouldDropLoot(
            grade: grade,
            sessionLootCount: sessionLootCount
        ) {
            let drop = LootDropService.generateDrop(level: currentLevel)
            lastLootDrop = drop
            sessionLootCount += 1
            await persistLootDrop(drop)
        }

        // Track new items learned (first review = reps was 0). The set guard
        // keeps a same-day re-queued new card from counting twice.
        if card.fsrsState.reps == 0 && !newItemCountedIDs.contains(card.id) {
            newItemCountedIDs.insert(card.id)
            newItemsLearned += 1
        }

        // Check for leech detection after grading.
        if let leechEvent = LeechDetectionService.checkForLeech(
            card: card,
            grade: grade,
            threshold: CardRepository.leechThreshold
        ) {
            lastLeechEvent = leechEvent
        }
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
        // behavior (mistake tracking, same-day requeue, mastery / leech / loot
        // detection, new-item counting) is preserved exactly.
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
        if let card = gradeableCard {
            nonSRSGradedCardIDs.insert(card.id)
            Logger.srs.debug(
                "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
            )
            await cardRepository.gradeCard(
                cardId: card.id,
                grade: grade,
                responseTimeMs: responseTimeMs
            )
            if cardRepository.saveErrorMonitor.lastSaveError != nil {
                cardRepository.saveErrorMonitor.clear()
                gradeSaveFailureCount += 1
            }
        }

        // Award XP for the exercise kind (per-type × JLPT-level multiplier).
        // `grade` is forwarded for `.perGrade` kinds (e.g. kanjiStudy) and
        // ignored by the rule table for `.perCompletion` kinds.
        let resolvedType = exerciseType(for: exercise)
        let xpAmount = ExerciseXP.award(
            type: resolvedType,
            level: sessionJLPTLevel,
            grade: grade
        )
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

        // Record per-skill attribution into the session ledger; surfaces on
        // SessionSummaryView's four-winds row.
        let recordedType = resolvedType
        let recordedAmount = xpAmount
        Task { [ledger] in
            await ledger.record(xp: recordedAmount, exerciseType: recordedType)
            let snap = await ledger.snapshot()
            await MainActor.run { self.skillContribution = snap }
        }

        // Persist RPG state.
        await persistRPGState()

        // Check for level-up.
        if result.didLevelUp {
            levelUpLevel = result.newLevel
        }

        // Track consecutive / total correct (display only).
        let isCorrect = grade == .good || grade == .easy
        if isCorrect {
            consecutiveCorrect += 1
            correctCount += 1
        } else {
            consecutiveCorrect = 0
        }

        // The card-backed kinds (`.kanjiStudy`, `.writingPractice`) run the
        // shared card-grade side-effects: mastery / leech detection and
        // first-review counting, identical to the SRS deck path. Positioned after
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
        // zero-skip, the lootbox milestone, the Live Activity, and the abandon
        // label — so a non-SRS completion must bump it too.
        reviewedCount += 1
        cardStartTime = Date()

        // Update Live Activity with current progress (label = the just-completed
        // exercise, mirroring gradeAndAdvance's ordering).
        let exerciseLabel = currentExercise.map { exerciseDisplayName($0) } ?? "Review"
        await liveActivityManager.updateActivity(
            elapsedSeconds: Int(elapsedTime),
            exerciseType: exerciseLabel,
            completedCount: reviewedCount,
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )

        // Advance the exercise pointer (never the SRS queue pointer here).
        advanceToNextExercise()

        // Check for lootbox milestone (every 25 completions in session).
        if LootBoxService.shouldAwardLootBox(reviewsInSession: reviewedCount) {
            let box = LootBoxService.generateLootBox(level: currentLevel)
            earnedLootBox = box
            await persistLootBox(box)
        }

        await finishSessionIfNeeded()
    }

    // MARK: - Session Finalization

    /// Applies end-of-session effects: daily/streak bonus and pity-drop check.
    /// Runs once when the session's last card has been graded.
    private func finalizeSession() async {
        let now = Date()
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }

        // Pity timer — if no drop this session, bump counter and force a drop at threshold.
        if sessionLootCount == 0 {
            state.sessionsSinceLastDrop += 1
            if LootDropService.shouldForcePityDrop(sessionsSinceLastDrop: state.sessionsSinceLastDrop) {
                let drop = LootDropService.generateDrop(level: currentLevel)
                state.addLootItem(drop)
                lastLootDrop = drop
                sessionLootCount += 1
                state.sessionsSinceLastDrop = 0
                Logger.rpg.info("Pity drop awarded: \(drop.name) (\(drop.rarity.displayName))")
            }
        } else {
            state.sessionsSinceLastDrop = 0
        }

        // Session bonus (daily / streak).
        let bonus = SessionBonusService.evaluate(
            now: now,
            lastSessionDate: state.lastSessionDate,
            currentStreak: state.currentDailyStreak,
            longestStreak: state.longestDailyStreak
        )

        if bonus.bonusXP > 0 {
            totalXP += bonus.bonusXP
            xpEarned += bonus.bonusXP
            let newLevel = RPGConstants.levelForXP(totalXP)
            if newLevel > currentLevel {
                levelUpLevel = newLevel
                currentLevel = newLevel
            }
            state.xp = totalXP
            state.level = currentLevel
            Logger.rpg.info("Session bonus: +\(bonus.bonusXP) XP (streak=\(bonus.newDailyStreak), newDay=\(bonus.isNewDay))")
        }

        state.currentDailyStreak = bonus.newDailyStreak
        state.longestDailyStreak = bonus.newLongestStreak
        state.lastSessionDate = now
        state.totalSessionsCompleted += 1
        // `isNewDay` is true on any calendar-day change vs. the last session,
        // streak-continuity aside — exactly "a distinct active day". Feeds
        // DisplayModeAdvancedThresholdMonitor's `OR active days ≥ 30` path.
        if bonus.isNewDay {
            state.activeDaysCount += 1
        }

        do {
            try context.save()
        } catch {
            Logger.rpg.error("Failed to persist session finalization: \(error.localizedDescription)")
        }

        lastSessionBonus = bonus
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

    /// Clears the loot drop display (called by the overlay after animation).
    public func clearLootDrop() {
        lastLootDrop = nil
    }

    /// Clears the earned lootbox (called after opening or dismissing).
    public func clearLootBox() {
        earnedLootBox = nil
    }

    /// Pauses the current session.
    public func pauseSession() {
        isPaused = true
        // Fold the current active interval before stopping so background
        // time is not counted if the user leaves the app while paused.
        if isTimerRunning {
            baseElapsedTime += Date().timeIntervalSince(timerResumeTime)
            elapsedTime = baseElapsedTime
        }
        stopTimer()
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

        // If the user quits without reviewing a single card, skip the
        // summary entirely and go straight back to the home screen.
        if reviewedCount == 0 {
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
    /// that crossed its unlock threshold during the session.
    private func processNewlyUnlocked() async {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        let previous = state.acknowledgedUnlocks
        let delta = unlockService.newlyUnlocked(profile: snapshot, previous: previous)
        guard !delta.isEmpty else { return }
        for type in delta {
            let drop = LootItem(
                category: .badge,
                rarity: .rare,
                name: String(localized: "Loot.NewExerciseUnlocked"),
                iconName: "leaf.fill"
            )
            state.addLootItem(drop)
            Logger.rpg.info("unlock.granted type=\(type.rawValue, privacy: .public)")
        }
        state.acknowledgedUnlocks = previous.union(delta)
        try? context.save()
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

    /// Drives `elapsedTime` counting only active foreground time.
    ///
    /// Each timer run accumulates seconds from `timerResumeTime` (set when
    /// the interval starts) on top of `baseElapsedTime` (the sum of all
    /// previous completed intervals). When `suspendTimer()` is called (scene
    /// goes background or is paused), the delta is folded into `baseElapsedTime`
    /// and the task is cancelled. When `startTimer()` is called again,
    /// `timerResumeTime` is reset so only the new foreground interval counts.
    private func startTimer() {
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
    /// so background time is never counted. Called from scenePhase onChange
    /// in the session view when the scene becomes inactive or background.
    public func suspendTimer() {
        guard isTimerRunning else { return }
        baseElapsedTime += Date().timeIntervalSince(timerResumeTime)
        elapsedTime = baseElapsedTime
        stopTimer()
    }

    /// Resumes the timer from where it was suspended. Called from scenePhase
    /// onChange when the scene becomes active again.
    public func resumeTimer() {
        guard !isTimerRunning, isActive, !isPaused else { return }
        startTimer()
    }

    /// Maps the SRS card currently being graded to the matching
    /// `ExerciseType` Spec A enumerated. The session queue is built from
    /// FSRS cards, so we route by `CardType`. Kana cards live in a
    /// separate drill surface, so they are never observed here — the
    /// fallback returns `.kanaStudy` defensively to keep XP attribution
    /// reading-aligned in any unexpected case.
    private func exerciseTypeForCurrentReview(card: CardDTO) -> ExerciseType {
        switch card.type {
        case .kanji:      return .kanjiStudy
        case .vocabulary: return .vocabularyStudy
        case .grammar:    return .fillInBlank
        case .listening:  return .listeningSubtitled
        }
    }

    /// Maps ANY `ExerciseItem` kind to the matching `ExerciseType` for XP
    /// attribution via `ExerciseXP.award`. `.srsReview` routes by its card's
    /// `CardType` (same rule as `exerciseTypeForCurrentReview`); the non-SRS
    /// kinds map to their capability identifier. Used by
    /// `completeCurrentExercise` so drill exercises award XP for the right skill.
    private func exerciseType(for exercise: ExerciseItem) -> ExerciseType {
        switch exercise {
        case .srsReview(let card):  return exerciseTypeForCurrentReview(card: card)
        case .kanjiStudy:           return .kanjiStudy
        case .grammarExercise:      return .grammarExercise
        case .vocabularyStudy:      return .vocabularyStudy
        case .fillInBlank:          return .fillInBlank
        case .readingPassage:       return .readingPassage
        case .writingPractice:      return .writingPractice
        case .listeningExercise:    return .listeningSubtitled
        case .speakingExercise:     return .speakingPractice
        case .sentenceConstruction: return .sentenceConstruction
        }
    }

    /// Sets `oneMinuteRemainingFired` once when elapsed crosses the
    /// (budget − 60s) threshold. Idempotent — drives a single toast.
    private func checkOneMinuteRemaining() {
        guard !oneMinuteRemainingFired,
              let policy = endPolicy else { return }
        let threshold = policy.durationBudgetMinutes * 60 - 60
        if Int(elapsedTime) >= threshold {
            oneMinuteRemainingFired = true
        }
    }

    /// Stops the timer completely.
    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        isTimerRunning = false
    }

    /// Formats a time interval as "M:SS".
    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Exercise Display Name

    /// Returns a user-facing label for the given exercise type.
    private func exerciseDisplayName(_ exercise: ExerciseItem) -> String {
        switch exercise {
        case .srsReview: "Review"
        case .kanjiStudy: "Kanji"
        case .grammarExercise: "Grammar"
        case .vocabularyStudy: "Vocabulary"
        case .fillInBlank: "Fill in Blank"
        case .readingPassage: "Reading"
        case .writingPractice: "Writing"
        case .listeningExercise: "Listening"
        case .speakingExercise: "Speaking"
        case .sentenceConstruction: "Sentence"
        }
    }

    // MARK: - RPG State Persistence

    /// Fetches the active profile's RPGState, applies the given mutation, and saves.
    /// Use this for all mutations on the current-profile RPGState.
    private func withRPGState(_ body: (RPGState) throws -> Void) async {
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            Logger.rpg.error("No active profile when mutating RPG state")
            return
        }
        do {
            try body(state)
            try context.save()
        } catch {
            Logger.rpg.error("RPG state operation failed: \(error.localizedDescription)")
        }
    }

    /// Loads the active profile's RPG state, creating one if the profile lacks it.
    private func loadRPGState() async {
        let context = modelContainer.mainContext
        if let state = ActiveProfileResolver.fetchActiveRPGState(in: context) {
            totalXP = state.xp
            currentLevel = state.level
            Logger.rpg.debug("Loaded RPG state: xp=\(state.xp), level=\(state.level)")
        } else {
            totalXP = 0
            currentLevel = 1
            Logger.rpg.warning("No active profile — session starts with zero XP")
        }
    }

    /// Persists current RPG state to SwiftData.
    private func persistRPGState() async {
        await withRPGState { state in
            state.xp = totalXP
            state.level = currentLevel
            state.totalReviewsCompleted += 1
        }
    }

    /// Persists a loot drop to the RPG state inventory.
    private func persistLootDrop(_ item: LootItem) async {
        await withRPGState { state in
            state.addLootItem(item)
            Logger.rpg.info("Loot drop persisted: \(item.name) (\(item.rarity.displayName))")
        }
    }

    /// Returns true if the active profile's RPG inventory already contains a
    /// loot item with the given name. Used to dedup once-per-profile named
    /// mastery rewards like "First Steps" so they aren't re-awarded on every
    /// new card graded Good/Easy.
    private func inventoryContains(name: String) async -> Bool {
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            return false
        }
        return state.lootInventory.contains { $0.name == name }
    }

    /// Persists a lootbox to the RPG state.
    private func persistLootBox(_ box: LootBox) async {
        await withRPGState { state in
            state.addLootBox(box)
            Logger.rpg.info("Lootbox persisted: \(box.challengeType.displayName)")
        }
    }

    // MARK: - Learner Snapshot

    /// Builds a `LearnerSnapshot` from the current card pool + active
    /// profile state. Pure delegation to `LearnerSnapshotBuilder.build(...)`
    /// — no side effects beyond reading the active RPG state for the
    /// `lastSessionAt` timestamp.
    ///
    /// Feeds real skill balances (from `ProgressService`), grammar mastery
    /// (derived by the builder from `.grammar` cards) and listening accuracy /
    /// recall (from persisted `ExerciseOutcomeLog`s) into the snapshot — the last
    /// two unlock `.listeningUnsubtitled` / `.speakingPractice` (remediation 4.4).
    private func buildSnapshot(cards: [CardDTO]) async -> LearnerSnapshot {
        let now = Date()
        let progressService = ProgressService(cardRepository: cardRepository)
        let progress = await progressService.loadDashboardData(now: now)
        let jlptLevel = JLPTLevel(rawValue: progress.jlptEstimate.level.lowercased()) ?? .n5
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?
            .lastSessionDate
        let listeningAccuracy = await cardRepository.listeningAccuracyLast30()
        let listeningRecall = await cardRepository.listeningRecallLast30Days(now: now)
        return LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: jlptLevel,
            listeningAccuracyLast30: listeningAccuracy,
            listeningRecallLast30Days: listeningRecall,
            skillBalances: progress.skillBalance.asSkillBalances,
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession,
            now: now
        )
    }

    // MARK: - Effective Unlocks

    /// Effective unlocked set for session planning: the live threshold
    /// evaluation UNION the profile's already-acknowledged unlocks. Unlocks are
    /// one-way — once granted (recorded in `RPGState.acknowledgedUnlocks`), a
    /// stricter later mastery definition must never silently re-lock them.
    private func effectiveUnlockedTypes(profile snapshot: LearnerSnapshot) -> Set<ExerciseType> {
        let live = unlockService.unlockedTypes(profile: snapshot)
        let acknowledged = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?
            .acknowledgedUnlocks ?? []
        return live.union(acknowledged)
    }

    // MARK: - Same-Day Re-Queue

    /// Same-day intra-session re-queue: a card graded `.again` comes back later
    /// in the same session instead of disappearing until its next FSRS due date.
    /// Mistakes mode appends to the end (drill-until-done); normal sessions
    /// re-insert 3-5 positions later. Capped at `maxRetriesPerCard`.
    private func requeueFailedCard(_ card: CardDTO) {
        let retries = retryCounts[card.id, default: 0]
        guard retries < Self.maxRetriesPerCard else { return }
        retryCounts[card.id] = retries + 1
        if sessionMode == .reviewMistakes {
            // Append to both ends — the appended `.srsReview` is the last
            // card-backed exercise, so its queue slot is simply the current
            // queue length; correspondence is preserved.
            sessionQueue.append(card)
            sessionExercises.append(.srsReview(card))
        } else {
            let offset = Int.random(in: 3...5)
            let exerciseSlot = min(currentExerciseIndex + 1 + offset, sessionExercises.count)
            // Derive the SRS-queue slot FROM the exercise slot so the two arrays
            // stay in lockstep when non-SRS exercises interleave: `sessionQueue`
            // holds only `.srsReview` payloads, so the requeued card's queue
            // position is the number of `.srsReview` items preceding its
            // exercise-list slot. Computing an independent `currentIndex + offset`
            // (the old behavior) desyncs the two the moment a non-SRS item sits
            // between the pointers, making the deck grade the wrong card. In a
            // pure-SRS session every preceding item is `.srsReview`, so this
            // equals the old `currentIndex + 1 + offset` exactly.
            let queueSlot = sessionExercises[..<exerciseSlot].reduce(into: 0) { count, item in
                if case .srsReview = item { count += 1 }
            }
            sessionExercises.insert(.srsReview(card), at: exerciseSlot)
            sessionQueue.insert(card, at: queueSlot)
        }
        // The end policy captured the queue length at session start; grow it in
        // lockstep so the queue-exhaustion check doesn't fire before the
        // re-queued card is shown.
        if let policy = endPolicy {
            endPolicy = SessionEndPolicy(
                durationBudgetMinutes: policy.durationBudgetMinutes,
                queueLength: policy.queueLength + 1,
                graceWindowSeconds: policy.graceWindowSeconds
            )
        }
        Logger.srs.info(
            "Same-day requeue: \(card.front, privacy: .public) (retry \(retries + 1)/\(Self.maxRetriesPerCard, privacy: .public))"
        )
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
