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

    // MARK: - seed(groups:) deterministic ordering

    @Test("curriculumSorted orders base before dakuten before yōon")
    func curriculumSortedOrdersBySectionTier() {
        // Deliberately fed out of curriculum order (a yōon character first,
        // then a dakuten one, then a base one) to prove the sort — not the
        // input order — decides the result.
        let hJa = KanaGroup.hJ.characters.first { $0.character == "じゃ" }!
        let hGa = KanaGroup.hG.characters.first { $0.character == "が" }!
        let hA = KanaGroup.hVowels.characters.first { $0.character == "あ" }!

        let sorted = KanaCardRepository.curriculumSorted([hJa, hGa, hA])
        #expect(sorted.map(\.character) == ["あ", "が", "じゃ"])
    }

    @Test("curriculumSorted keeps hiragana before katakana within a tier")
    func curriculumSortedKeepsHiraganaBeforeKatakanaWithinTier() {
        let kA = KanaGroup.kVowels.characters.first { $0.character == "ア" }!
        let hA = KanaGroup.hVowels.characters.first { $0.character == "あ" }!

        let sorted = KanaCardRepository.curriculumSorted([kA, hA])
        #expect(sorted.map(\.character) == ["あ", "ア"])
    }

    @Test("curriculumSorted is deterministic across repeated calls on a shuffled input")
    func curriculumSortedIsDeterministic() {
        let all = KanaGroup.allCases.flatMap { $0.characters }
        let shuffled = all.shuffled()

        let first = KanaCardRepository.curriculumSorted(shuffled).map(\.character)
        let second = KanaCardRepository.curriculumSorted(shuffled.shuffled()).map(\.character)

        #expect(first == second)
    }

    @Test("seed(groups:) staggering follows curriculum order deterministically across two repositories")
    func seedStaggeringOrderIsDeterministic() async throws {
        // Seed with EVERY group (208 characters, well above the 50/day
        // stagger cap) so which characters land due "today" vs. later
        // directly exposes creation order. Two independent repositories
        // seeded with the SAME Set<KanaGroup> — whose iteration order is
        // process-hash-seeded and therefore not under test control — must
        // still land the same characters in the "due today" batch.
        let allGroups = Set(KanaGroup.allCases)
        let allCharacters = allGroups.flatMap { $0.characters }
        let firstFifty = KanaCardRepository.curriculumSorted(allCharacters).prefix(50)
        let expectedFirstBatch = Set(firstFifty.map(\.character))
        // Sanity: the expected first batch is entirely base-section kana. 92
        // base characters (46 hiragana + 46 katakana) is MORE than 50, so
        // the batch never reaches dakuten — it's the first 50 of the 92,
        // i.e. all 46 hiragana base plus the first 4 katakana base (ア..エ).
        #expect(expectedFirstBatch.count == 50)
        #expect(firstFifty.allSatisfy { $0.group.section == .base })
        #expect(expectedFirstBatch.contains("あ"))
        #expect(expectedFirstBatch.contains("ア"))
        #expect(!expectedFirstBatch.contains("が"))

        let (repoA, _) = try await makeRepo()
        await repoA.seed(groups: allGroups)
        let dueTodayA = Set(
            (await repoA.dueCardsForGroups(allGroups, now: Date())).map(\.front)
        )

        let (repoB, _) = try await makeRepo()
        await repoB.seed(groups: allGroups)
        let dueTodayB = Set(
            (await repoB.dueCardsForGroups(allGroups, now: Date())).map(\.front)
        )

        #expect(dueTodayA == expectedFirstBatch)
        #expect(dueTodayB == expectedFirstBatch)
        #expect(dueTodayA == dueTodayB)
    }

    // MARK: - Fresh-user purge safety invariant

    /// Pins the Core-visible half of the "fresh user" purge-safety invariant
    /// task #42 calls out: a brand-new install seeds `ContentSeedService.
    /// beginnerHiragana` (5 vowels) before the learner has ever opened the
    /// kana selector, and `KanaPoolViewModel`'s default `selectedGroups`
    /// (`[.hVowels]`, app target — see
    /// `Ikeru/ViewModels/Learning/KanaPoolViewModel.swift`) must cover those
    /// 5 characters, or the very first `loadMasteries()` call would purge a
    /// new user's amorçage cards as "outside the selection" before they've
    /// touched anything.
    ///
    /// This test can only pin the `ContentSeedService` side of that
    /// relationship — `beginnerHiragana`'s characters are exactly
    /// `KanaGroup.hVowels`'s characters — because it lives in `IkeruCore`.
    /// The other half (`KanaPoolViewModel`'s default `selectedGroups`
    /// literally being `[.hVowels]`) lives in the `Ikeru` app target, is out
    /// of this task's perimeter, and — per the app-target test gotchas
    /// (`IkeruTests` needs explicit pbxproj registration) — isn't something
    /// this pass can add a test for either. Verified by reading that file
    /// instead: `self.selectedGroups = Self.loadPersistedSelection() ??
    /// [.hVowels]` (line 91 at the time of writing). If that literal or
    /// `beginnerHiragana`'s character set ever drifts from `.hVowels`, this
    /// test catches the `ContentSeedService` side, but a drift on the
    /// `KanaPoolViewModel` side would go undetected by IkeruCore's test
    /// suite.
    @Test("Fresh-user safety: beginnerHiragana's characters are exactly the .hVowels group")
    func beginnerHiraganaMatchesDefaultSelectedGroup() {
        let beginnerCharacters = Set(ContentSeedService.beginnerHiragana.map(\.character))
        let hVowelsCharacters = Set(KanaGroup.hVowels.characters.map(\.character))
        #expect(beginnerCharacters == hVowelsCharacters)

        // Romaji must agree too — ContentSeedService writes `back` as
        // `kana.romanization`, and `CardDTO.purgeableKanaGroup` requires an
        // exact match against the catalog's romaji. If these ever diverged,
        // ContentSeedService-seeded cards would stop resolving via
        // `purgeableKanaGroup` (a safe direction — they'd become
        // unpurgeable rather than wrongly purged — but it would silently
        // defeat item 35's orphan cleanup for beginner cards).
        let beginnerRomaji = Dictionary(
            uniqueKeysWithValues: ContentSeedService.beginnerHiragana.map { ($0.character, $0.romanization) }
        )
        for character in KanaGroup.hVowels.characters {
            #expect(beginnerRomaji[character.character] == character.romaji)
        }
    }

    // MARK: - purgeUnstartedCards(notIn:)

    @Test("purgeUnstartedCards removes reps == 0 cards outside the kept groups")
    func purgeRemovesOrphanedUnstartedCards() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seed(groups: [.hVowels, .hG])

        let removed = await repo.purgeUnstartedCards(notIn: [.hVowels])
        #expect(removed == 5) // .hG's 5 cards

        let remaining = await repo.allKanaCards()
        #expect(remaining.count == 5)
        #expect(Set(remaining.map(\.front)) == Set(["あ", "い", "う", "え", "お"]))
    }

    @Test("purgeUnstartedCards never removes a card with reps > 0, even outside the kept groups")
    func purgeNeverTouchesStartedCards() async throws {
        let (repo, cardRepo) = try await makeRepo()
        await repo.seed(groups: [.hVowels, .hG])

        // Simulate the learner having reviewed one of the now-deselected
        // .hG cards before it was dropped from the selection.
        let hGCards = await repo.cardsForGroups([.hG])
        let reviewed = try #require(hGCards.first { $0.front == "が" })
        await cardRepo.gradeCard(cardId: reviewed.id, grade: .good, responseTimeMs: 1000)

        let removed = await repo.purgeUnstartedCards(notIn: [.hVowels])
        #expect(removed == 4) // the other 4 .hG cards, not the reviewed one

        let remaining = await repo.allKanaCards()
        #expect(remaining.contains { $0.front == "が" })
        #expect(remaining.count == 5 + 1) // .hVowels (5) + the reviewed が
    }

    @Test("purgeUnstartedCards is idempotent — a second call is a no-op")
    func purgeIsIdempotent() async throws {
        let (repo, _) = try await makeRepo()
        await repo.seed(groups: [.hVowels, .hG])

        let firstPass = await repo.purgeUnstartedCards(notIn: [.hVowels])
        #expect(firstPass == 5)

        let secondPass = await repo.purgeUnstartedCards(notIn: [.hVowels])
        #expect(secondPass == 0)

        let remaining = await repo.allKanaCards()
        #expect(remaining.count == 5)
    }

    @Test("purgeUnstartedCards only considers kana cards")
    func purgeIgnoresNonKanaCards() async throws {
        let (repo, cardRepo) = try await makeRepo()
        await repo.seed(groups: [.hVowels])
        _ = await cardRepo.createCard(front: "犬", back: "dog", type: .vocabulary, dueDate: Date())

        // Keep no groups at all — if non-kana cards were considered, this
        // would try (and fail) to classify "犬" as orphaned kana.
        let removed = await repo.purgeUnstartedCards(notIn: [])
        #expect(removed == 5)

        let remainingAll = await cardRepo.allCards()
        #expect(remainingAll.contains { $0.front == "犬" })
    }

    @Test(
        "purgeUnstartedCards never deletes a .vocabulary card whose front happens to be a kana-shaped real word — a genuine kana card at the same front is still purged"
    )
    func purgeDiscriminatesKanaShapedVocabWordFromRealKanaCard() async throws {
        // え is both a KanaGroup base vowel AND a real Japanese word
        // ("picture/image"). Before this fix, KanaCardRepository.
        // purgeUnstartedCards resolved purge-eligibility via `kanaGroup`,
        // which matches on `front` alone — so this vocabulary card (type
        // .vocabulary, front "え", back the meaning "image", never
        // reviewed) would misclassify as an orphaned kana card and be
        // deleted the moment .hVowels is not in `keepGroups`. That is
        // exactly the collision task #42 flags: this test fails against
        // that implementation (it deleted the vocab card) and must pass
        // against the fix, which additionally requires an exact
        // `back == romaji` match (`CardDTO.purgeableKanaGroup`) before a
        // card is purge-eligible.
        let (repo, cardRepo) = try await makeRepo()
        let vocabCard = await cardRepo.createCard(front: "え", back: "image", type: .vocabulary, dueDate: Date())

        // Keep NO groups — the strongest possible pressure to purge: if the
        // vocab word's front-catalog match alone were enough, it would be
        // removed here.
        let removed = await repo.purgeUnstartedCards(notIn: [])
        #expect(removed == 0)

        let remaining = await cardRepo.allCards()
        #expect(remaining.contains { $0.id == vocabCard.id }, "the kana-shaped vocabulary card must survive")

        // Positive control: a genuine kana card at the SAME front, seeded
        // the normal way (back == romaji), is still purged when its group
        // is dropped — proving the fix didn't just make everything
        // unpurgeable. Uses a fresh repository so the two "え" fronts never
        // collide as duplicates within one store.
        let (controlRepo, controlCardRepo) = try await makeRepo()
        await controlRepo.seed(groups: [.hVowels])
        let controlRemoved = await controlRepo.purgeUnstartedCards(notIn: [])
        #expect(controlRemoved == 5)
        let controlRemaining = await controlCardRepo.allCards()
        #expect(!controlRemaining.contains { $0.front == "え" })
    }
}
