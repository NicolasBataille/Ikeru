import Foundation
import Observation
import os

/// Composes study sessions by selecting and ordering cards.
/// Basic v1 logic: return all due cards + new cards (max 5 new per session).
@Observable
public final class PlannerService {

    /// Maximum number of new (unseen) cards to include per session.
    public static let maxNewCardsPerSession = 5

    private let cardRepository: CardRepository

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    /// Composes a session queue from available cards.
    /// - Returns: An ordered array of cards for the session (due cards first, then new cards).
    public func composeSession() async -> [CardDTO] {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Fetch due cards (cards whose dueDate has passed)
        let now = Date()
        let dueCards = await cardRepository.dueCards(before: now)

        // Fetch all cards to find new ones (cards that have never been reviewed)
        let allCards = await cardRepository.allCards()

        // New cards: those with reps == 0 and not already in the due list
        let dueCardIds = Set(dueCards.map(\.id))
        let newCards = allCards
            .filter { $0.fsrsState.reps == 0 && !dueCardIds.contains($0.id) }
            .prefix(Self.maxNewCardsPerSession)

        // Compose queue: due cards first, then new cards
        let queue = dueCards + Array(newCards)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.planner.info(
            "Session composed: \(dueCards.count) due + \(newCards.count) new = \(queue.count) total (\(elapsed, format: .fixed(precision: 1))ms)"
        )

        return queue
    }
}
