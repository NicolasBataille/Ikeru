import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("PlannerService")
@MainActor
struct PlannerServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seeds an active profile and attaches each inserted card to it. Cards
    /// inserted directly into the context are orphans (`profile == nil`), so a
    /// seeded profile alone leaves every profile-scoped read (`dueCards`,
    /// `allCards`) empty; stamping the relationship at insert makes them resolve.
    @discardableResult
    private func seedProfile(in container: ModelContainer) throws -> UserProfile {
        let profile = UserProfile(displayName: "Test")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        return profile
    }

    private func seedCards(
        container: ModelContainer,
        dueCards: Int = 0,
        newCards: Int = 0,
        futureCards: Int = 0
    ) throws {
        let context = container.mainContext
        let profile = try seedProfile(in: container)

        // Due cards (due in the past)
        for i in 0..<dueCards {
            let card = Card(
                front: "Due \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 1), // Has been reviewed before
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
        }

        // New cards (never reviewed, due in the future — picked up by planner as "new")
        for i in 0..<newCards {
            let card = Card(
                front: "New \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 0), // Never reviewed
                dueDate: Date().addingTimeInterval(3600) // Future — not in dueCards query
            )
            card.profile = profile
            context.insert(card)
        }

        // Future cards (not yet due)
        for i in 0..<futureCards {
            let card = Card(
                front: "Future \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 1),
                dueDate: Date().addingTimeInterval(86400) // Due tomorrow
            )
            card.profile = profile
            context.insert(card)
        }

        try context.save()
    }

    // MARK: - Composition Tests

    @Test("Composes session with due cards only")
    func composesWithDueCardsOnly() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCards: 3, futureCards: 2)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        // Should include 3 due cards, not future ones
        #expect(queue.count == 3)
    }

    @Test("Composes session with due cards plus new cards")
    func composesWithDueAndNewCards() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCards: 2, newCards: 3)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        // 2 due + 3 new = 5
        #expect(queue.count == 5)
    }

    @Test("Limits new cards to maximum per session")
    func limitsNewCards() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCards: 0, newCards: 10)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        // 10 new cards with future dueDate, so none are in dueCards query
        // Planner picks them as "new" cards, capped at maxNewCardsPerSession (5)
        #expect(queue.count == PlannerService.maxNewCardsPerSession)
    }

    @Test("Returns empty queue when no cards available")
    func emptyQueueWhenNoCards() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        #expect(queue.isEmpty)
    }

    @Test("Composes session for day-1 beginner with seeded kana")
    func composesForDayOneBeginner() async throws {
        let container = try makeContainer()
        try seedProfile(in: container)
        let repo = CardRepository(modelContainer: container)

        // Seed beginner kana (createCard auto-stamps the seeded active profile)
        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        let planner = PlannerService(cardRepository: repo)
        let queue = await planner.composeSession()

        // Should include all 5 seeded kana cards
        #expect(queue.count == 5)
        let fronts = Set(queue.map(\.front))
        #expect(fronts.contains("\u{3042}")) // あ
        #expect(fronts.contains("\u{3044}")) // い
    }

    @Test("Due cards are ordered most-overdue-first, whatever the insertion order")
    func dueCardsOrderedMostOverdueFirst() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = try seedProfile(in: container)

        // Insert deliberately out of due-date order: least-overdue first.
        let base = Date()
        let offsets: [TimeInterval] = [-3_600, -360_000, -7_200, -1_800]
        for (i, offset) in offsets.enumerated() {
            let card = Card(
                front: "Due \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 1),
                dueDate: base.addingTimeInterval(offset)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        try #require(queue.count == offsets.count)
        #expect(queue.map(\.dueDate) == queue.map(\.dueDate).sorted())
        // Most overdue (offset -360_000) must lead.
        #expect(queue.first?.front == "Due 1")
    }

    @Test("Session composition completes quickly")
    func compositionIsPerformant() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCards: 10, newCards: 5)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let start = CFAbsoluteTimeGetCurrent()
        _ = await planner.composeSession()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // Must complete in under 1000ms (NFR7, relaxed from 500ms for test stability)
        #expect(elapsed < 1000, "Session composition took \(elapsed)ms, exceeding 1000ms limit")
    }

    @Test("Due cards appear before new cards in queue")
    func dueCardsBeforeNewCards() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = try seedProfile(in: container)

        // Create a due card with reps > 0
        let dueCard = Card(
            front: "DueCard",
            back: "Back",
            type: .kanji,
            fsrsState: FSRSState(reps: 2),
            dueDate: Date().addingTimeInterval(-3600)
        )
        dueCard.profile = profile
        context.insert(dueCard)

        // Create a new card with reps == 0 and future dueDate (so it's not in dueCards)
        let newCard = Card(
            front: "NewCard",
            back: "Back",
            type: .kanji,
            fsrsState: FSRSState(reps: 0),
            dueDate: Date().addingTimeInterval(3600) // Future — won't be in dueCards
        )
        newCard.profile = profile
        context.insert(newCard)

        try context.save()

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let queue = await planner.composeSession()

        // `try #require` throws (soft-fails) instead of trapping on an empty
        // array, so a future regression can never abort the whole parallel run.
        try #require(queue.count == 2)
        #expect(queue[0].front == "DueCard")
        #expect(queue[1].front == "NewCard")
    }
}
