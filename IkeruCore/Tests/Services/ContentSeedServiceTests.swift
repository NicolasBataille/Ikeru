import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("ContentSeedService")
struct ContentSeedServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seeds a UserProfile so profile-scoped reads (`allCards`, `dueCards`)
    /// resolve the cards `seedBeginnerKanaIfNeeded` creates via `createCard`.
    /// Without it, `fetchActiveProfile()` returns nil and those reads are empty.
    @MainActor
    private func seedProfile(in container: ModelContainer) throws {
        container.mainContext.insert(UserProfile(displayName: "Test"))
        try container.mainContext.save()
    }

    // MARK: - Seeding Tests

    @Test("Seeds 5 hiragana cards when no cards exist")
    func seedsFiveHiraganaCards() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        let seeded = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        #expect(seeded.count == 5)

        // Verify the characters match the expected set
        let fronts = Set(seeded.map(\.front))
        let expected: Set<String> = ["\u{3042}", "\u{3044}", "\u{3046}", "\u{3048}", "\u{304A}"]
        #expect(fronts == expected)

        // Verify romanizations
        let backs = Set(seeded.map(\.back))
        let expectedBacks: Set<String> = ["a", "i", "u", "e", "o"]
        #expect(backs == expectedBacks)

        // Verify card type — kana is `.vocabulary`, matching the production
        // seeder (`KanaCardRepository`), not `.kanji`.
        for card in seeded {
            #expect(card.type == .vocabulary)
        }
    }

    @Test("Skips seeding when cards already exist")
    func skipsWhenCardsExist() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        let seeded = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 3
        )

        #expect(seeded.isEmpty)
    }

    @Test("Seeded cards are persisted in repository")
    func seededCardsArePersisted() async throws {
        let container = try makeContainer()
        try await seedProfile(in: container)
        let repo = CardRepository(modelContainer: container)

        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        let allCards = await repo.allCards()
        #expect(allCards.count == 5)
    }

    @Test("Seeded cards are due immediately")
    func seededCardsAreDueImmediately() async throws {
        let container = try makeContainer()
        try await seedProfile(in: container)
        let repo = CardRepository(modelContainer: container)

        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        // Cards seeded with dueDate = Date(), so they should be due now or in the past
        let dueCards = await repo.dueCards(before: Date().addingTimeInterval(1))
        #expect(dueCards.count == 5)
    }

    @Test("Beginner hiragana constant has correct count")
    func beginnerHiraganaCount() {
        #expect(ContentSeedService.beginnerHiragana.count == 5)
    }
}
