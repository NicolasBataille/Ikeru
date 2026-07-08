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

    /// Seeds a UserProfile so `CardRepository.activeProfileCards()` resolves
    /// the inserted cards. Without this the model actor's
    /// `fetchActiveProfile()` falls back to nil and returns an empty pool.
    private func seedActiveProfile(in context: ModelContext) -> UserProfile {
        let profile = UserProfile(displayName: "Test")
        context.insert(profile)
        return profile
    }

    /// A deterministic mid-month reference date so month-window assertions
    /// never straddle a month boundary regardless of when the test runs.
    private func midMonthNow() throws -> Date {
        let components = DateComponents(year: 2026, month: 6, day: 15, hour: 12)
        return try #require(Calendar.current.date(from: components))
    }

    @discardableResult
    private func seedMixedCards(
        container: ModelContainer,
        now: Date
    ) throws -> UserProfile {
        let context = container.mainContext
        let profile = seedActiveProfile(in: context)

        func insert(_ card: Card) {
            card.profile = profile
            context.insert(card)
        }

        // Kanji cards: 3 mastered, 2 new
        for i in 0..<3 {
            insert(Card(
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
            ))
        }
        for i in 0..<2 {
            insert(Card(
                front: "Kanji New \(i)",
                back: "Meaning \(i)",
                type: .kanji,
                dueDate: now.addingTimeInterval(86400)
            ))
        }

        // Vocabulary cards: 2 mastered
        for i in 0..<2 {
            insert(Card(
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
            ))
        }

        // Grammar cards: 1 mastered, 1 new
        insert(Card(
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
        ))
        insert(Card(
            front: "Grammar 1",
            back: "Usage",
            type: .grammar,
            dueDate: now.addingTimeInterval(86400 * 2)
        ))

        // Listening cards: 1 mastered
        insert(Card(
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
        ))

        try context.save()
        return profile
    }

    // MARK: - Dashboard Data Tests

    @Test("Loads dashboard data with correct structure")
    func loadsDashboardData() async throws {
        let container = try makeContainer()
        let now = try midMonthNow()
        try seedMixedCards(container: container, now: now)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData(now: now)

        #expect(data.dueNowCount > 0)
        #expect(data.forecast.count == 7)
        #expect(data.monthlySnapshots.count == 6)
    }

    @Test("Skill balance reflects mastery ratios")
    func skillBalanceReflectsMastery() async throws {
        let container = try makeContainer()
        let now = try midMonthNow()
        try seedMixedCards(container: container, now: now)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData(now: now)

        // Reading = (3 kanji + 2 vocab mastered) / (5 kanji + 2 vocab) = 5/7
        let expectedReading = 5.0 / 7.0
        #expect(abs(data.skillBalance.reading - expectedReading) < 0.01)

        // Writing (grammar) = 1 mastered / 2 total = 0.5
        #expect(abs(data.skillBalance.writing - 0.5) < 0.01)

        // Listening = 1 mastered / 1 total = 1.0
        #expect(abs(data.skillBalance.listening - 1.0) < 0.01)
    }

    @Test("Speaking score is 0 (no real speaking signal) even with reviewed cards")
    func speakingScoreIsHonestZero() async throws {
        let container = try makeContainer()
        let now = try midMonthNow()
        try seedMixedCards(container: container, now: now)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData(now: now)

        // The legacy ease-factor proxy rendered a constant ~0.71 for any
        // reviewed pool (easeFactor is never mutated from its 2.5 default).
        // With no speaking signal available, the service must report 0.
        #expect(data.skillBalance.speaking == 0)
    }

    @Test("JLPT estimate excludes untagged cards (post readiness-formula rebuild)")
    func jlptEstimateReflectsProgress() async throws {
        let container = try makeContainer()
        let now = try midMonthNow()
        try seedMixedCards(container: container, now: now)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let data = await service.loadDashboardData(now: now)

        // All seeded cards are untagged (jlptLevel == nil), so none count
        // toward the per-level pool.
        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteredCount == 0)
        #expect(data.jlptEstimate.totalRequired == 100)
        #expect(data.jlptEstimate.masteryFraction == 0)
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

    // MARK: - Monthly Accuracy (from ReviewLog grades)

    @Test("Monthly accuracy derives from review log grades")
    func monthlyAccuracyFromReviewLogs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = try midMonthNow()
        let profile = seedActiveProfile(in: context)

        let card = Card(front: "語", back: "word", type: .vocabulary, dueDate: now)
        card.profile = profile
        context.insert(card)

        // This month: 3 successes + 1 failure (again) → 0.75. `.hard`
        // counts as a success — slow but correct; only `.again` is a
        // mistake (consistent with SessionViewModel's mistake tracking).
        let recent = now.addingTimeInterval(-86400) // yesterday, same month
        for grade in [Grade.good, .easy, .hard, .again] {
            let log = ReviewLog(
                card: card,
                grade: grade,
                responseTimeMs: 1200,
                timestamp: recent
            )
            context.insert(log)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData(now: now)

        let currentMonth = try #require(data.monthlySnapshots.last)
        #expect(abs(currentMonth.accuracy - 0.75) < 0.001)

        // Months without logs report 0 (no data), not a constant proxy.
        for snapshot in data.monthlySnapshots.dropLast() {
            #expect(snapshot.accuracy == 0)
        }
    }

    @Test("Review logs land in the snapshot of their own month")
    func previousMonthLogsCountInPreviousSnapshot() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = try midMonthNow()
        let calendar = Calendar.current
        let profile = seedActiveProfile(in: context)

        let card = Card(front: "語", back: "word", type: .vocabulary, dueDate: now)
        card.profile = profile
        context.insert(card)

        // Previous month: 1 success + 1 failure → 0.5.
        let previousMonth = try #require(
            calendar.date(byAdding: .month, value: -1, to: now)
        )
        for grade in [Grade.good, .again] {
            let log = ReviewLog(
                card: card,
                grade: grade,
                responseTimeMs: 900,
                timestamp: previousMonth
            )
            context.insert(log)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData(now: now)

        #expect(data.monthlySnapshots.count == 6)
        // Snapshots are oldest-first; index 4 is last month, index 5 is now.
        #expect(abs(data.monthlySnapshots[4].accuracy - 0.5) < 0.001)
        #expect(data.monthlySnapshots[5].accuracy == 0)
    }

    @Test("Accuracy ignores card ease factor (regression: constant proxy)")
    func accuracyIgnoresEaseFactor() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = try midMonthNow()
        let profile = seedActiveProfile(in: context)

        // Cards reviewed this month (reps > 0, default easeFactor 2.5) but
        // with NO review logs. The legacy ease-factor proxy reported a
        // constant ~0.71 here; grade-based accuracy must report 0.
        for i in 0..<5 {
            let card = Card(
                front: "Card \(i)",
                back: "Meaning \(i)",
                type: .vocabulary,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: 10.0,
                    reps: 2,
                    lapses: 0,
                    lastReview: now.addingTimeInterval(-3600)
                ),
                dueDate: now.addingTimeInterval(86400)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData(now: now)

        let currentMonth = try #require(data.monthlySnapshots.last)
        #expect(currentMonth.accuracy == 0)
    }

    @Test("Dashboard loads within performance budget")
    func dashboardIsPerformant() async throws {
        let container = try makeContainer()
        let now = try midMonthNow()
        try seedMixedCards(container: container, now: now)
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)

        let start = CFAbsoluteTimeGetCurrent()
        _ = await service.loadDashboardData(now: now)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 1000, "Dashboard load took \(elapsed)ms, exceeding 1000ms budget")
    }
}
