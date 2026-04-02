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

    /// Elapsed session duration in seconds.
    public var elapsedSeconds: TimeInterval {
        guard isActive else { return 0 }
        return Date().timeIntervalSince(sessionStartTime)
    }

    /// Formatted elapsed time string (MM:SS).
    public var elapsedTimeFormatted: String {
        let total = Int(elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Estimated session card count for preview.
    public private(set) var estimatedCardCount: Int = 0

    // MARK: - Feedback

    /// Whether a feedback flash is currently showing.
    public private(set) var feedbackState: FeedbackState?

    // MARK: - Dependencies

    private let plannerService: PlannerService
    private let cardRepository: CardRepository
    private var cardStartTime: Date = Date()

    // MARK: - Init

    public init(plannerService: PlannerService, cardRepository: CardRepository) {
        self.plannerService = plannerService
        self.cardRepository = cardRepository
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
        isPaused = false
        sessionStartTime = Date()
        cardStartTime = Date()
        isActive = true
        estimatedCardCount = queue.count

        Logger.ui.info("Session started with \(queue.count) cards")
    }

    /// Loads an estimate of the upcoming session card count (for home screen preview).
    public func loadSessionEstimate() async {
        let queue = await plannerService.composeSession()
        estimatedCardCount = queue.count
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

        // Calculate XP
        let cardXP: Int
        switch grade {
        case .easy:
            cardXP = 10
        case .good:
            cardXP = 10
        case .hard:
            cardXP = 5
        case .again:
            cardXP = 5
        }
        xpEarned += cardXP

        // Track new items learned (first review = reps was 0)
        if card.fsrsState.reps == 0 {
            newItemsLearned += 1
        }

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(300))
        feedbackState = nil

        if isSessionComplete {
            Logger.ui.info(
                "Session complete: \(self.reviewedCount) reviewed, \(self.xpEarned) XP earned"
            )
        }
    }

    /// Grade from a swipe direction.
    public func gradeFromSwipe(direction: SwipeDirection) async {
        await gradeAndAdvance(grade: direction.grade)
    }

    /// Pauses the current session.
    public func pauseSession() {
        isPaused = true
        Logger.ui.debug("Session paused at card \(self.currentIndex + 1)/\(self.sessionQueue.count)")
    }

    /// Resumes the session from where it was paused.
    public func resumeSession() {
        isPaused = false
        cardStartTime = Date()
        Logger.ui.debug("Session resumed at card \(self.currentIndex + 1)/\(self.sessionQueue.count)")
    }

    /// Ends the session early, preserving partial progress.
    public func endSession() {
        Logger.ui.info(
            "Session ended early: \(self.reviewedCount)/\(self.sessionQueue.count) reviewed, \(self.xpEarned) XP"
        )
        // Mark as complete by jumping to end of queue
        currentIndex = sessionQueue.count
        isPaused = false
    }

    /// Dismisses the session completely (called after summary).
    public func dismissSession() {
        isActive = false
        isPaused = false
        sessionQueue = []
        currentIndex = 0
        Logger.ui.debug("Session dismissed")
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
