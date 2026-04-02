import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - CardReviewViewModel

@MainActor
@Observable
public final class CardReviewViewModel {

    // MARK: - Published State

    /// The card currently being reviewed, or nil when queue is empty.
    public private(set) var currentCard: CardDTO?

    /// The next card in the queue (for peek/pre-load), or nil.
    public private(set) var nextCard: CardDTO?

    /// Number of cards remaining in the review queue.
    public private(set) var remainingCount: Int = 0

    /// Total cards in this session (for progress calculation).
    public private(set) var sessionTotal: Int = 0

    /// Progress fraction (0.0 to 1.0).
    public var sessionProgress: Double {
        guard sessionTotal > 0 else { return 0 }
        let completed = sessionTotal - remainingCount
        return Double(completed) / Double(sessionTotal)
    }

    /// Whether a feedback flash is currently showing.
    public private(set) var feedbackState: FeedbackState?

    /// Whether the review session is complete (no more cards).
    public var isSessionComplete: Bool {
        currentCard == nil && !isLoading
    }

    /// Whether cards are being loaded.
    public private(set) var isLoading = true

    // MARK: - Private State

    private var reviewQueue: [CardDTO] = []
    private var cardStartTime: Date = Date()
    private let cardRepository: CardRepository
    private var sessionStartTime: Date = Date()

    // MARK: - Init

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    // MARK: - Loading

    /// Load due cards from the repository and start the session.
    public func loadDueCards() async {
        isLoading = true
        let now = Date()
        let dueCards = await cardRepository.dueCards(before: now)

        reviewQueue = dueCards
        sessionTotal = dueCards.count
        sessionStartTime = now

        advanceToNextCard()
        isLoading = false

        Logger.srs.info("Review session started: \(dueCards.count) cards due")
    }

    // MARK: - Grading

    /// Grade the current card and advance to the next one.
    /// - Parameter grade: The grade to apply.
    public func gradeCard(grade: Grade) async {
        guard let card = currentCard else { return }

        // Compute response time
        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // Show feedback
        let isCorrect = grade == .good || grade == .easy
        feedbackState = isCorrect ? .correct : .incorrect

        Logger.srs.debug(
            "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
        )

        // Persist grade via repository (async, but non-blocking for UI)
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: responseTimeMs
        )

        // On "Again": re-queue card at the end of the session
        if grade == .again {
            reviewQueue.append(card)
            Logger.srs.debug("Re-queued card for later review: \(card.front)")
        }

        // Advance to next card immediately (pre-loaded nextCard makes this instant)
        advanceToNextCard()

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(300))
        feedbackState = nil
    }

    /// Grade from a swipe direction.
    public func gradeFromSwipe(direction: SwipeDirection) async {
        await gradeCard(grade: direction.grade)
    }

    // MARK: - Card Advancement

    /// Advance to the next card in the queue. Pre-loads nextCard for peek.
    private func advanceToNextCard() {
        if reviewQueue.isEmpty {
            currentCard = nil
            nextCard = nil
            remainingCount = 0
        } else {
            currentCard = reviewQueue.removeFirst()
            nextCard = reviewQueue.first
            remainingCount = reviewQueue.count + 1 // +1 for current card
        }
        cardStartTime = Date()
    }
}

// MARK: - FeedbackState

public enum FeedbackState: Sendable, Equatable {
    case correct
    case incorrect

    public var color: Color {
        switch self {
        case .correct: Color(hex: IkeruTheme.Colors.success) // jade green #4ECDC4
        case .incorrect: Color(hex: IkeruTheme.Colors.secondaryAccent) // vermillion #FF6B6B
        }
    }
}

// MARK: - Environment Key

private struct CardReviewViewModelKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: CardReviewViewModel? = nil
}

extension EnvironmentValues {
    public var cardReviewViewModel: CardReviewViewModel? {
        get { self[CardReviewViewModelKey.self] }
        set { self[CardReviewViewModelKey.self] = newValue }
    }
}
