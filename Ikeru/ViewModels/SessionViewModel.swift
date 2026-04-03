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

    /// Elapsed session duration in seconds (legacy computed property for compatibility).
    public var elapsedSeconds: TimeInterval {
        elapsedTime
    }

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

    /// Review forecast for upcoming days (displayed on home screen).
    public private(set) var reviewForecast: [ForecastDay] = []

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
    private let reviewForecastService: ReviewForecastService
    private weak var companionViewModel: CompanionChatViewModel?
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
        self.reviewForecastService = ReviewForecastService(cardRepository: cardRepository)
    }

    /// Connects the companion chat view model for leech intervention notifications.
    public func setCompanionViewModel(_ companion: CompanionChatViewModel) {
        self.companionViewModel = companion
    }

    // MARK: - Session Lifecycle

    /// Composes a session queue via PlannerService and starts the session.
    public func startSession() async {
        let queue = await plannerService.composeSession()
        sessionQueue = queue
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
        estimatedCardCount = queue.count

        // Build exercise list from cards (each card is an SRS review)
        sessionExercises = queue.map { .srsReview($0) }
        currentExerciseIndex = 0
        showAbandonConfirmation = false

        // Start timer
        elapsedTime = 0
        startTimer()

        // Load persisted RPG state
        await loadRPGState()

        Logger.ui.info("Session started with \(queue.count) cards")
    }

    /// Loads an estimate of the upcoming session card count (for home screen preview).
    public func loadSessionEstimate() async {
        let queue = await plannerService.composeSession()
        estimatedCardCount = queue.count
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

    /// Loads the review forecast for display on the home screen.
    /// - Parameter days: Number of days to forecast (default 7).
    public func loadReviewForecast(days: Int = 7) async {
        reviewForecast = await reviewForecastService.forecast(days: days)
        Logger.ui.debug("Review forecast loaded: \(self.reviewForecast.count) days")
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
        estimatedCardCount = plan.exercises.count

        // Store full exercise list for immersive mode
        sessionExercises = plan.exercises
        currentExerciseIndex = 0
        showAbandonConfirmation = false

        // Start timer
        elapsedTime = 0
        startTimer()

        await loadRPGState()

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
            if let companion = companionViewModel {
                await companion.handleLeechDetected(card: card)
            }
        }

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

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
            Logger.ui.info(
                "Session complete: \(self.reviewedCount) reviewed, \(self.xpEarned) XP earned"
            )
        }
    }

    /// Grade from a swipe direction.
    public func gradeFromSwipe(direction: SwipeDirection) async {
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
        pauseTimer()
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

    /// Pauses the timer by cancelling the task.
    private func pauseTimer() {
        timerTask?.cancel()
        timerTask = nil
        isTimerRunning = false
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

    // MARK: - RPG State Persistence

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
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        do {
            let results = try context.fetch(descriptor)
            if let state = results.first {
                state.xp = totalXP
                state.level = currentLevel
                state.totalReviewsCompleted += 1
                try context.save()
            }
        } catch {
            Logger.rpg.error("Failed to persist RPG state: \(error.localizedDescription)")
        }
    }

    /// Persists a loot drop to the RPG state inventory.
    private func persistLootDrop(_ item: LootItem) async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        do {
            let results = try context.fetch(descriptor)
            if let state = results.first {
                state.addLootItem(item)
                try context.save()
                Logger.rpg.info("Loot drop persisted: \(item.name) (\(item.rarity.displayName))")
            }
        } catch {
            Logger.rpg.error("Failed to persist loot drop: \(error.localizedDescription)")
        }
    }

    /// Persists a lootbox to the RPG state.
    private func persistLootBox(_ box: LootBox) async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        do {
            let results = try context.fetch(descriptor)
            if let state = results.first {
                state.addLootBox(box)
                try context.save()
                Logger.rpg.info("Lootbox persisted: \(box.challengeType.displayName)")
            }
        } catch {
            Logger.rpg.error("Failed to persist lootbox: \(error.localizedDescription)")
        }
    }

    /// Loads RPG state for display (used by home screen).
    public func loadRPGStateForDisplay() async {
        await loadRPGState()
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
