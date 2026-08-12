import Testing
import Foundation
import SwiftData
@testable import IkeruCore

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Seeds a UserProfile so `CardModelActor.activeProfileCards()` resolves the
/// cards `createCard` stamps. Without a profile, `fetchActiveProfile()` returns
/// nil, `createCard` orphans each card, and every profile-scoped read
/// (`allKanaCards`, `cardsForGroups`, …) comes back empty. Mirror of
/// `CardRepositoryTests.seedActiveProfile`.
@MainActor
private func makeRepo() throws -> (KanaCardRepository, CardRepository) {
    let container = try makeTestContainer()
    container.mainContext.insert(UserProfile(displayName: "Test"))
    try container.mainContext.save()
    let cardRepo = CardRepository(modelContainer: container)
    return (KanaCardRepository(cardRepository: cardRepo), cardRepo)
}

@Suite("KanaCardRepository")
struct KanaCardRepositoryTests {

    @Test("seedIfNeeded creates a card per base kana")
    func seedCreatesAllBaseCards() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let all = await repo.allKanaCards()
        #expect(all.count == KanaGroup.allBaseCharacters.count)
    }

    @Test("seedIfNeeded seeds every base kana as CardType .vocabulary, not .kanji")
    func seedCreatesVocabularyTypedCards() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let all = await repo.allKanaCards()
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.type == .vocabulary })
    }

    @Test("seedIfNeeded is idempotent")
    func seedIsIdempotent() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let firstCount = await repo.allKanaCards().count
        await repo.seedIfNeeded()
        let secondCount = await repo.allKanaCards().count
        #expect(firstCount == secondCount)
        #expect(secondCount == KanaGroup.allBaseCharacters.count)
    }

    @Test("cardsForGroups([.hVowels]) returns exactly 5 cards")
    func cardsForSingleGroup() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let cards = await repo.cardsForGroups([.hVowels])
        #expect(cards.count == 5)
        let fronts = Set(cards.map { $0.front })
        #expect(fronts == Set(["あ", "い", "う", "え", "お"]))
    }

    @Test("cardsForGroups([.hVowels, .hK]) returns 10 cards")
    func cardsForTwoGroups() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let cards = await repo.cardsForGroups([.hVowels, .hK])
        #expect(cards.count == 10)
    }

    @Test("dueCardsForGroups returns freshly seeded cards as due")
    func dueCardsForFreshSeed() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        // Use a date slightly in the future to guarantee seeded dueDates <= now.
        let future = Date().addingTimeInterval(1)
        let due = await repo.dueCardsForGroups([.hVowels], now: future)
        #expect(due.count == 5)
    }

    @Test("mastery(for: .hVowels) returns 5 cards all .new after seeding")
    func masteryForSingleGroup() async throws {
        let (repo, _) = try await makeRepo()
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
        let (repo, _) = try await makeRepo()
        await repo.seedIfNeeded()
        let result = await repo.mastery(for: [.hVowels, .hK])
        #expect(result.count == 2)
        #expect(result[.hVowels]?.totalCards == 5)
        #expect(result[.hK]?.totalCards == 5)
    }

    // MARK: - seed(groups:) staggering

    /// All dakuten + yōon groups across both scripts: 116 characters, matching
    /// the exact figure that alarmed the pedagogical review (an existing
    /// tester's stale persisted selection of these groups, once they went from
    /// empty placeholders to real content, would seed 116 cards all due at
    /// once).
    private static let allExtendedGroups: Set<KanaGroup> = Set(
        KanaGroup.allCases.filter { $0.section != .base }
    )

    @Test("seed(groups:) for a small selection stays entirely due today")
    func seedSmallSelectionIsNotStaggered() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seed(groups: [.hVowels, .hK])
        let due = await repo.dueCardsForGroups([.hVowels, .hK], now: Date())
        #expect(due.count == 10)
    }

    @Test("seed(groups:) for all dakuten/yōon groups does not create a wall of 116 same-second due cards")
    func seedLargeSelectionIsStaggeredNotAWall() async throws {
        let (repo, _) = try await makeRepo()
        #expect(Self.allExtendedGroups.reduce(0) { $0 + $1.characters.count } == 116)

        await repo.seed(groups: Self.allExtendedGroups)
        let all = await repo.cardsForGroups(Self.allExtendedGroups)
        #expect(all.count == 116)

        let dueNow = await repo.dueCardsForGroups(Self.allExtendedGroups, now: Date())
        #expect(dueNow.count < all.count)
        #expect(dueNow.count > 0)

        // Everything still becomes due eventually — nothing is lost, only delayed.
        let farFuture = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let dueEventually = await repo.dueCardsForGroups(Self.allExtendedGroups, now: farFuture)
        #expect(dueEventually.count == 116)
    }

    @Test("staggeredDueDates keeps small batches entirely at 'now'")
    func staggeredDueDatesSmallBatchIsImmediate() {
        let now = Date()
        let dates = KanaCardRepository.staggeredDueDates(count: 10, from: now)
        #expect(dates.count == 10)
        #expect(dates.allSatisfy { $0 == now })
    }

    @Test("staggeredDueDates spreads a 116-card batch across multiple days")
    func staggeredDueDatesLargeBatchSpreadsAcrossDays() {
        let now = Date()
        let dates = KanaCardRepository.staggeredDueDates(count: 116, from: now)
        #expect(dates.count == 116)

        let distinctDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        // 116 cards with a cap of 50/day spans 3 distinct days (50 + 50 + 16).
        #expect(distinctDays.count == 3)
        #expect(dates.filter { $0 == now }.count == 50)
    }
}
