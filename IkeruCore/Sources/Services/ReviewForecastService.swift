import Foundation
import Observation
import os

/// Provides review queue analytics and daily review forecasts.
/// Uses card due dates to project future review workload.
@Observable
public final class ReviewForecastService: @unchecked Sendable {

    private let cardRepository: CardRepository

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    /// Count of cards currently due for review (due date in the past).
    /// - Returns: Number of cards due right now.
    public func dueNow() async -> Int {
        let now = Date()
        let dueCards = await cardRepository.dueCards(before: now)
        Logger.planner.debug("Due now: \(dueCards.count) cards")
        return dueCards.count
    }

    /// Count of cards due by end of today.
    /// - Returns: Number of cards due before midnight tonight.
    public func dueToday() async -> Int {
        let calendar = Calendar.current
        let now = Date()
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(86400)

        let allCards = await cardRepository.allCards()
        let dueTodayCards = allCards.filter { card in
            card.dueDate < endOfToday && card.fsrsState.reps > 0
        }

        Logger.planner.debug("Due today: \(dueTodayCards.count) cards")
        return dueTodayCards.count
    }

    /// Produces a daily review forecast for the next N days.
    /// Each ForecastDay includes the date and how many cards are due on that date.
    /// - Parameter days: Number of days to forecast.
    /// - Returns: Array of ForecastDay entries, one per day starting from today.
    public func forecast(days: Int) async -> [ForecastDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let allCards = await cardRepository.allCards()

        // Only consider cards that have been reviewed at least once (have scheduling data)
        let scheduledCards = allCards.filter { $0.fsrsState.reps > 0 }

        var result: [ForecastDay] = []

        for dayOffset in 0..<days {
            let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            let dayEnd = calendar.date(byAdding: .day, value: dayOffset + 1, to: today)!

            let dueOnDay = scheduledCards.filter { card in
                card.dueDate >= dayStart && card.dueDate < dayEnd
            }.count

            result.append(ForecastDay(
                date: dayStart,
                dueCount: dueOnDay,
                newCount: 0 // New card scheduling is handled by PlannerService
            ))
        }

        Logger.planner.debug("Forecast computed for \(days) days: \(result.map(\.dueCount))")
        return result
    }
}
