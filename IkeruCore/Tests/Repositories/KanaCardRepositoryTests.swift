import Testing
import Foundation
import SwiftData
@testable import IkeruCore

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeRepo() throws -> (KanaCardRepository, CardRepository) {
    let container = try makeTestContainer()
    let cardRepo = CardRepository(modelContainer: container)
    return (KanaCardRepository(cardRepository: cardRepo), cardRepo)
}

@Suite("KanaCardRepository")
struct KanaCardRepositoryTests {

    @Test("seedIfNeeded creates a card per base kana")
    func seedCreatesAllBaseCards() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let all = await repo.allKanaCards()
        #expect(all.count == KanaGroup.allBaseCharacters.count)
    }

    @Test("seedIfNeeded is idempotent")
    func seedIsIdempotent() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let firstCount = await repo.allKanaCards().count
        await repo.seedIfNeeded()
        let secondCount = await repo.allKanaCards().count
        #expect(firstCount == secondCount)
        #expect(secondCount == KanaGroup.allBaseCharacters.count)
    }

    @Test("cardsForGroups([.hVowels]) returns exactly 5 cards")
    func cardsForSingleGroup() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let cards = await repo.cardsForGroups([.hVowels])
        #expect(cards.count == 5)
        let fronts = Set(cards.map { $0.front })
        #expect(fronts == Set(["あ", "い", "う", "え", "お"]))
    }

    @Test("cardsForGroups([.hVowels, .hK]) returns 10 cards")
    func cardsForTwoGroups() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let cards = await repo.cardsForGroups([.hVowels, .hK])
        #expect(cards.count == 10)
    }

    @Test("dueCardsForGroups returns freshly seeded cards as due")
    func dueCardsForFreshSeed() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        // Use a date slightly in the future to guarantee seeded dueDates <= now.
        let future = Date().addingTimeInterval(1)
        let due = await repo.dueCardsForGroups([.hVowels], now: future)
        #expect(due.count == 5)
    }

    @Test("mastery(for: .hVowels) returns 5 cards all .new after seeding")
    func masteryForSingleGroup() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let mastery = await repo.mastery(for: .hVowels)
        #expect(mastery.totalCards == 5)
        #expect(mastery.levelDistribution[.new] == 5)
        #expect(mastery.levelDistribution[.learning] == 0)
        #expect(mastery.levelDistribution[.familiar] == 0)
        #expect(mastery.levelDistribution[.mastered] == 0)
        #expect(mastery.levelDistribution[.anchored] == 0)
    }

    @Test("mastery(for: Set) returns an entry for each requested group")
    func masteryForMultipleGroups() async throws {
        let (repo, _) = try makeRepo()
        await repo.seedIfNeeded()
        let result = await repo.mastery(for: [.hVowels, .hK])
        #expect(result.count == 2)
        #expect(result[.hVowels]?.totalCards == 5)
        #expect(result[.hK]?.totalCards == 5)
    }
}
