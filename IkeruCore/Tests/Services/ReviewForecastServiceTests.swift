import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("ReviewForecastService")
@MainActor
struct ReviewForecastServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedCardsWithDueDates(
        container: ModelContainer,
        dueDates: [Date]
    ) throws {
        let context = container.mainContext
        for (i, dueDate) in dueDates.enumerated() {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: 10.0,
                    reps: 1,
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: dueDate
            )
            context.insert(card)
        }
        try context.save()
    }

    // MARK: - dueNow Tests

    @Test("dueNow returns count of cards currently due")
    func dueNowReturnsCurrentlyDue() async throws {
        let container = try makeContainer()
        let now = Date()
        try seedCardsWithDueDates(container: container, dueDates: [
            now.addingTimeInterval(-3600),   // 1 hour ago — due
            now.addingTimeInterval(-7200),   // 2 hours ago — due
            now.addingTimeInterval(3600),    // 1 hour from now — not due
            now.addingTimeInterval(86400)    // tomorrow — not due
        ])

        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let count = await service.dueNow()
        #expect(count == 2)
    }

    @Test("dueNow returns 0 when no cards are due")
    func dueNowReturnsZeroWhenNoneDue() async throws {
        let container = try makeContainer()
        let now = Date()
        try seedCardsWithDueDates(container: container, dueDates: [
            now.addingTimeInterval(3600),
            now.addingTimeInterval(86400)
        ])

        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let count = await service.dueNow()
        #expect(count == 0)
    }

    // MARK: - dueToday Tests

    @Test("dueToday returns cards due by end of today")
    func dueTodayReturnsTodayCards() async throws {
        let container = try makeContainer()
        let calendar = Calendar.current
        let now = Date()
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(86400)
        let tomorrow = endOfToday.addingTimeInterval(3600)

        try seedCardsWithDueDates(container: container, dueDates: [
            now.addingTimeInterval(-3600),  // past — due today
            now.addingTimeInterval(60),     // 1 minute from now — due today
            tomorrow                        // tomorrow — not due today
        ])

        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let count = await service.dueToday()
        #expect(count == 2)
    }

    // MARK: - forecast Tests

    @Test("forecast returns correct daily counts")
    func forecastReturnsDailyCounts() async throws {
        let container = try makeContainer()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        try seedCardsWithDueDates(container: container, dueDates: [
            today.addingTimeInterval(100),              // Today (just after midnight)
            today.addingTimeInterval(86400 + 100),      // Tomorrow
            today.addingTimeInterval(86400 + 200),      // Tomorrow
            today.addingTimeInterval(86400 * 2 + 100),  // Day after tomorrow
        ])

        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let forecast = await service.forecast(days: 3)

        #expect(forecast.count == 3)
        // Day 1 (today): 1 due
        #expect(forecast[0].dueCount == 1)
        // Day 2 (tomorrow): 2 due
        #expect(forecast[1].dueCount == 2)
        // Day 3: 1 due
        #expect(forecast[2].dueCount == 1)
    }

    @Test("forecast with no cards returns empty days")
    func forecastEmptyCards() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let forecast = await service.forecast(days: 5)

        #expect(forecast.count == 5)
        for day in forecast {
            #expect(day.dueCount == 0)
        }
    }

    @Test("forecast dates are consecutive starting from today")
    func forecastDatesConsecutive() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let forecast = await service.forecast(days: 7)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        #expect(forecast.count == 7)
        for (i, day) in forecast.enumerated() {
            let expected = calendar.date(byAdding: .day, value: i, to: today)!
            #expect(calendar.isDate(day.date, inSameDayAs: expected))
        }
    }
}
