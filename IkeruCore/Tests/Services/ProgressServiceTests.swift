import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("ProgressService")
@MainActor
struct ProgressServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedMixedCards(container: ModelContainer) throws {
        let context = container.mainContext
        let now = Date()

        // Kanji cards: 3 mastered, 2 new
        for i in 0..<3 {
            let card = Card(
                front: "Kanji \(i)",
                back: "Meaning \(i)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: 10.0,
                    reps: 3,
                    lapses: 0,
                    lastReview: now.addingTimeInterval(-86400)
                ),
                dueDate: now.addingTimeInterval(-3600)
            )
            context.insert(card)
        }
        for i in 0..<2 {
            let card = Card(
                front: "Kanji New \(i)",
                back: "Meaning \(i)",
                type: .kanji,
                dueDate: now.addingTimeInterval(86400)
            )
            context.insert(card)
        }

        // Vocabulary cards: 2 mastered
        for i in 0..<2 {
            let card = Card(
                front: "Vocab \(i)",
                back: "Meaning \(i)",
                type: .vocabulary,
                fsrsState: FSRSState(
                    difficulty: 4.0,
                    stability: 8.0,
                    reps: 2,
                    lapses: 0,
                    lastReview: now.addingTimeInterval(-172800)
                ),
                dueDate: now.addingTimeInterval(3600)
            )
            context.insert(card)
        }

        // Grammar cards: 1 mastered, 1 new
        let grammarMastered = Card(
            front: "Grammar 0",
            back: "Usage",
            type: .grammar,
            fsrsState: FSRSState(
                difficulty: 5.0,
                stability: 5.0,
                reps: 1,
                lapses: 0,
                lastReview: now.addingTimeInterval(-86400)
            ),
            dueDate: now.addingTimeInterval(-1800)
        )
        context.insert(grammarMastered)

        let grammarNew = Card(
            front: "Grammar 1",
            back: "Usage",
            type: .grammar,
            dueDate: now.addingTimeInterval(86400 * 2)
        )
        context.insert(grammarNew)

        // Listening cards: 1 mastered
        let listeningCard = Card(
            front: "Listen 0",
            back: "Transcript",
            type: .listening,
            fsrsState: FSRSState(
                difficulty: 4.0,
                stability: 6.0,
                reps: 2,
                lapses: 0,
                lastReview: now.addingTimeInterval(-43200)
            ),
            dueDate: now.addingTimeInterval(7200)
        )
        context.insert(listeningCard)

        try context.save()
    }

    // MARK: - Dashboard Data Tests

    @Test("Loads dashboard data with correct structure")
    func loadsDashboardData() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData()

        #expect(data.dueNowCount > 0)
        #expect(data.forecast.count == 7)
        #expect(data.monthlySnapshots.count == 6)
    }

    @Test("Skill balance reflects mastery ratios")
    func skillBalanceReflectsMastery() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData()

        // Reading = (3 kanji + 2 vocab mastered) / (5 kanji + 2 vocab) = 5/7
        let expectedReading = 5.0 / 7.0
        #expect(abs(data.skillBalance.reading - expectedReading) < 0.01)

        // Writing (grammar) = 1 mastered / 2 total = 0.5
        #expect(abs(data.skillBalance.writing - 0.5) < 0.01)

        // Listening = 1 mastered / 1 total = 1.0
        #expect(abs(data.skillBalance.listening - 1.0) < 0.01)
    }

    @Test("JLPT estimate reflects mastered count")
    func jlptEstimateReflectsProgress() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData()

        // 7 mastered cards out of 100 for N5
        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteredCount == 7)
        #expect(data.jlptEstimate.totalRequired == 100)
        #expect(abs(data.jlptEstimate.masteryFraction - 0.07) < 0.01)
    }

    @Test("Empty card set returns zero progress")
    func emptyCardsReturnZeroProgress() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData()

        #expect(data.skillBalance.reading == 0)
        #expect(data.skillBalance.writing == 0)
        #expect(data.skillBalance.listening == 0)
        #expect(data.skillBalance.speaking == 0)
        #expect(data.jlptEstimate.masteredCount == 0)
        #expect(data.dueNowCount == 0)
        #expect(data.dueTodayCount == 0)
    }

    @Test("Forecast has correct day labels")
    func forecastHasCorrectLabels() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData()

        #expect(data.forecast.count == 7)
        #expect(data.forecast[0].dayLabel == "Today")
    }

    @Test("Dashboard loads within performance budget")
    func dashboardIsPerformant() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let start = CFAbsoluteTimeGetCurrent()
        _ = await service.loadDashboardData()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 1000, "Dashboard load took \(elapsed)ms, exceeding 1000ms budget")
    }
}
