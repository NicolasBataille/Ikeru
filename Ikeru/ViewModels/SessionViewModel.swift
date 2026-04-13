import SwiftUI
import SwiftData
import IkeruCore
import os

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

    /// Whether the session is complete (all cards reviewed).
    public var isSessionComplete: Bool {
        isActive && currentIndex >= sessionQueue.count
    }

    /// The current card being reviewed, or nil if complete.
    public var currentCard: CardDTO? {
        guard currentIndex < sessionQueue.count else { return nil }
        return sessionQueue[currentIndex]
    }

    /// The next card for peek/pre-load, or nil.
    public var nextCard: CardDTO? {
        let nextIndex = currentIndex + 1
        guard nextIndex < sessionQueue.count else { return nil }
        return sessionQueue[nextIndex]
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

    // MARK: - Dependencies

    private let plannerService: PlannerService
    private let cardRepository: CardRepository
    private let modelContainer: ModelContainer
    private let liveActivityManager = LiveActivityManager()
    private var cardStartTime: Date = Date()
    private var timerTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        plannerService: PlannerService,
        cardRepository: CardRepository,
        modelContainer: ModelContainer
    ) {
        self.plannerService = plannerService
        self.cardRepository = cardRepository
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
        sessionLootCount = 0
        earnedLootBox = nil
        isPaused = false
        sessionStartTime = Date()
        cardStartTime = Date()
        isActive = true
        currentExerciseIndex = 0
        showAbandonConfirmation = false
        elapsedTime = 0
    }

    /// Composes a session queue via PlannerService and starts the session.
    public func startSession() async {
        let queue = await plannerService.composeSession()
        sessionQueue = queue
        resetSessionState()
        estimatedCardCount = queue.count

        // Build exercise list from cards (each card is an SRS review)
        sessionExercises = queue.map { .srsReview($0) }

        // Start timer
        startTimer()

        // Load persisted RPG state
        await loadRPGState()

        // Start Live Activity for Dynamic Island
        liveActivityManager.startActivity(totalExercises: queue.count)

        Logger.ui.info("Session started with \(queue.count) cards")
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

        Logger.srs.debug(
            "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
        )

        // Persist grade via repository
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: responseTimeMs
        )

        // Award XP via RPGService (pure function)
        let result = RPGService.awardXP(
            grade: grade,
            currentXP: totalXP,
            currentLevel: currentLevel,
            totalReviews: reviewedCount
        )

        totalXP = result.newXP
        currentLevel = result.newLevel
        xpEarned += result.xpAwarded
        lastXPGained = result.xpAwarded

        // Persist RPG state
        await persistRPGState()

        // Check for level-up
        if result.didLevelUp {
            levelUpLevel = result.newLevel
        }

        // Track consecutive correct for loot drop probability
        if isCorrect {
            consecutiveCorrect += 1
        } else {
            consecutiveCorrect = 0
        }

        // Check for loot drop
        lastLootDrop = nil
        if LootDropService.shouldDropLoot(
            grade: grade,
            consecutiveCorrect: consecutiveCorrect
        ) {
            let drop = LootDropService.generateDrop(level: currentLevel)
            lastLootDrop = drop
            sessionLootCount += 1
            await persistLootDrop(drop)
        }

        // Track new items learned (first review = reps was 0)
        if card.fsrsState.reps == 0 {
            newItemsLearned += 1
        }

        // Check for leech detection after grading
        if let leechEvent = LeechDetectionService.checkForLeech(
            card: card,
            grade: grade,
            threshold: CardRepository.leechThreshold
        ) {
            lastLeechEvent = leechEvent
        }

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

        if isSessionComplete {
            stopTimer()
            await liveActivityManager.endActivity(
                elapsedSeconds: Int(elapsedTime),
                completedCount: reviewedCount,
                totalCount: sessionQueue.count,
                xpEarned: xpEarned,
                streakCount: consecutiveCorrect
            )
            Logger.ui.info(
                "Session complete: \(self.reviewedCount) reviewed, \(self.xpEarned) XP earned"
            )
        }
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
    public func endSession() {
        Logger.ui.info(
            "Session ended early: \(self.reviewedCount)/\(self.sessionQueue.count) reviewed, \(self.xpEarned) XP"
        )

        // End Live Activity
        Task {
            await liveActivityManager.endActivity(
                elapsedSeconds: Int(elapsedTime),
                completedCount: reviewedCount,
                totalCount: sessionQueue.count,
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

    /// Progress description for the abandon dialog (e.g., "You've completed 3 of 8 exercises").
    public var abandonProgressDescription: String {
        "You've completed \(reviewedCount) of \(sessionExercises.count) exercises"
    }

    // MARK: - Timer

    /// Starts the ContinuousClock-based timer that increments elapsedTime every second.
    private func startTimer() {
        guard !isTimerRunning else { return }
        isTimerRunning = true
        timerTask = Task { @MainActor in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.elapsedTime += 1
            }
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

    /// Fetches the existing RPGState, applies the given mutation, and saves.
    /// Use this for all mutations on an already-created RPGState row.
    private func withRPGState(_ body: (RPGState) throws -> Void) async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        do {
            let results = try context.fetch(descriptor)
            if let state = results.first {
                try body(state)
                try context.save()
            }
        } catch {
            Logger.rpg.error("RPG state operation failed: \(error.localizedDescription)")
        }
    }

    /// Loads RPGState from SwiftData, creating one if none exists.
    private func loadRPGState() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        do {
            let results = try context.fetch(descriptor)
            if let state = results.first {
                totalXP = state.xp
                currentLevel = state.level
                Logger.rpg.debug("Loaded RPG state: xp=\(state.xp), level=\(state.level)")
            } else {
                let newState = RPGState()
                context.insert(newState)
                try context.save()
                totalXP = 0
                currentLevel = 1
                Logger.rpg.info("Created initial RPG state")
            }
        } catch {
            Logger.rpg.error("Failed to load RPG state: \(error.localizedDescription)")
            totalXP = 0
            currentLevel = 1
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

    /// Persists a lootbox to the RPG state.
    private func persistLootBox(_ box: LootBox) async {
        await withRPGState { state in
            state.addLootBox(box)
            Logger.rpg.info("Lootbox persisted: \(box.challengeType.displayName)")
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
