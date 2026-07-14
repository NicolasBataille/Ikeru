import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Helper to create an in-memory ModelContainer for testing.
private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Seeds a UserProfile so `CardModelActor.activeProfileCards()` resolves the
/// inserted cards (same pattern as `ProgressServiceTests.seedActiveProfile`).
/// Without a profile, `fetchActiveProfile()` returns nil and every
/// profile-scoped query (`allCards`, `dueCards`, `cards(byType:)`,
/// `leechCards`) comes back empty. No UserDefaults key is written: when the
/// persisted active-profile id is missing or stale, the model actor falls
/// back to the oldest profile in the store, so each in-memory container
/// resolves its own seeded profile without cross-test pollution (and there
/// is nothing to clean up afterwards).
@MainActor
private func seedActiveProfile(in container: ModelContainer) throws {
    let context = container.mainContext
    context.insert(UserProfile(displayName: "Test"))
    try context.save()
}

@Suite("CardRepository")
struct CardRepositoryTests {

    // MARK: - CRUD Operations

    @Test("Create a card and retrieve it by ID")
    func createAndRead() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(
            front: "日",
            back: "day/sun",
            type: .kanji
        )

        let fetched = await repository.card(by: card.id)
        #expect(fetched != nil)
        #expect(fetched?.front == "日")
        #expect(fetched?.back == "day/sun")
        #expect(fetched?.type == .kanji)
    }

    @Test("Create multiple cards and list all")
    func createMultipleAndListAll() async throws {
        let container = try makeTestContainer()
        try await seedActiveProfile(in: container)
        let repository = CardRepository(modelContainer: container)

        _ = await repository.createCard(front: "日", back: "day", type: .kanji)
        _ = await repository.createCard(front: "月", back: "moon", type: .kanji)
        _ = await repository.createCard(front: "食べる", back: "to eat", type: .vocabulary)

        let all = await repository.allCards()
        #expect(all.count == 3)
    }

    @Test("Delete a card removes it from storage")
    func deleteCard() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "日", back: "day", type: .kanji)
        let cardId = card.id

        await repository.deleteCard(by: cardId)

        let fetched = await repository.card(by: cardId)
        #expect(fetched == nil)
    }

    // MARK: - Query Operations

    @Test("Query due cards returns only cards due before given date")
    func dueCards() async throws {
        let container = try makeTestContainer()
        try await seedActiveProfile(in: container)
        let repository = CardRepository(modelContainer: container)

        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let tomorrow = now.addingTimeInterval(86400)

        _ = await repository.createCard(front: "過去", back: "past", type: .kanji, dueDate: yesterday)
        _ = await repository.createCard(front: "未来", back: "future", type: .kanji, dueDate: tomorrow)

        let dueCards = await repository.dueCards(before: now)
        #expect(dueCards.count == 1)
        #expect(dueCards.first?.front == "過去")
    }

    @Test("Sorted due cards are ordered by dueDate ascending (most overdue first)")
    func dueCardsSortedByDueDate() async throws {
        let container = try makeTestContainer()
        try await seedActiveProfile(in: container)
        let repository = CardRepository(modelContainer: container)

        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400)
        let threeDaysAgo = now.addingTimeInterval(-3 * 86400)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86400)
        let tomorrow = now.addingTimeInterval(86400)

        // Insert in shuffled order to make the sort observable
        _ = await repository.createCard(front: "一", back: "one", type: .kanji, dueDate: oneDayAgo)
        _ = await repository.createCard(front: "三", back: "three", type: .kanji, dueDate: threeDaysAgo)
        _ = await repository.createCard(front: "二", back: "two", type: .kanji, dueDate: twoDaysAgo)
        _ = await repository.createCard(front: "未来", back: "future", type: .kanji, dueDate: tomorrow)

        let sorted = await repository.dueCardsSortedByDueDate(before: now)
        #expect(sorted.count == 3)
        #expect(sorted.map(\.front) == ["三", "二", "一"])

        // Sanity: same set as the unsorted variant
        let unsorted = await repository.dueCards(before: now)
        #expect(Set(unsorted.map(\.id)) == Set(sorted.map(\.id)))
    }

    @Test("Query cards by type returns correct subset")
    func cardsByType() async throws {
        let container = try makeTestContainer()
        try await seedActiveProfile(in: container)
        let repository = CardRepository(modelContainer: container)

        _ = await repository.createCard(front: "日", back: "day", type: .kanji)
        _ = await repository.createCard(front: "月", back: "moon", type: .kanji)
        _ = await repository.createCard(front: "食べる", back: "to eat", type: .vocabulary)
        _ = await repository.createCard(front: "は particle", back: "topic marker", type: .grammar)

        let kanjiCards = await repository.cards(byType: .kanji)
        #expect(kanjiCards.count == 2)

        let vocabCards = await repository.cards(byType: .vocabulary)
        #expect(vocabCards.count == 1)

        let grammarCards = await repository.cards(byType: .grammar)
        #expect(grammarCards.count == 1)

        let listeningCards = await repository.cards(byType: .listening)
        #expect(listeningCards.count == 0)
    }

    @Test("Query leech cards returns only flagged cards")
    func leechCards() async throws {
        let container = try makeTestContainer()
        try await seedActiveProfile(in: container)
        let repository = CardRepository(modelContainer: container)

        _ = await repository.createCard(front: "日", back: "day", type: .kanji)
        _ = await repository.createCard(front: "難", back: "difficult", type: .kanji, leechFlag: true)
        _ = await repository.createCard(front: "複雑", back: "complex", type: .vocabulary, leechFlag: true)

        let leeches = await repository.leechCards()
        #expect(leeches.count == 2)
    }

    // MARK: - Grade Card (Atomic Operation)

    @Test("Grade card updates FSRSState and creates ReviewLog atomically")
    func gradeCardAtomic() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "日", back: "day", type: .kanji)
        let cardId = card.id

        await repository.gradeCard(cardId: cardId, grade: .good, responseTimeMs: 1200)

        let updated = await repository.card(by: cardId)
        #expect(updated != nil)
        #expect(updated?.fsrsState.reps == 1)
        #expect(updated?.fsrsState.lastReview != nil)
        #expect((updated?.fsrsState.stability ?? 0) > 0)

        let logs = await repository.reviewLogs(for: cardId)
        #expect(logs.count == 1)
        #expect(logs.first?.grade == .good)
        #expect(logs.first?.responseTimeMs == 1200)
    }

    @Test("Grade card with Again increments lapse count")
    func gradeCardAgainIncreasesLapses() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "日", back: "day", type: .kanji)
        let cardId = card.id

        await repository.gradeCard(cardId: cardId, grade: .again, responseTimeMs: 5000)

        let updated = await repository.card(by: cardId)
        #expect(updated?.lapseCount == 1)
        #expect(updated?.fsrsState.lapses == 1)
    }

    @Test("Multiple reviews create multiple ReviewLog entries")
    func multipleReviews() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "日", back: "day", type: .kanji)
        let cardId = card.id

        await repository.gradeCard(cardId: cardId, grade: .good, responseTimeMs: 1000)
        await repository.gradeCard(cardId: cardId, grade: .easy, responseTimeMs: 800)
        await repository.gradeCard(cardId: cardId, grade: .hard, responseTimeMs: 2000)

        let logs = await repository.reviewLogs(for: cardId)
        #expect(logs.count == 3)

        let updated = await repository.card(by: cardId)
        #expect(updated?.fsrsState.reps == 3)
    }

    // MARK: - Leech Detection

    @Test("Card becomes leech after exceeding lapse threshold")
    func leechDetection() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "難", back: "difficult", type: .kanji)
        let cardId = card.id

        // Grade "again" multiple times to trigger leech
        for _ in 0..<8 {
            await repository.gradeCard(cardId: cardId, grade: .again, responseTimeMs: 5000)
        }

        let updated = await repository.card(by: cardId)
        #expect(updated?.leechFlag == true)
    }

    // MARK: - JLPT Level Round-Trip

    @Test("New card defaults to nil JLPT level")
    func jlptLevelDefaultsNil() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "本", back: "book", type: .vocabulary)
        let fetched = await repository.card(by: card.id)
        #expect(fetched?.jlptLevel == nil)
    }

    @Test("setJLPTLevel persists tag and round-trips through DTO")
    func jlptLevelPersistsAndRoundTrips() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "本", back: "book", type: .vocabulary)
        await repository.setJLPTLevel(.n5, for: card.id)

        let fetched = await repository.card(by: card.id)
        #expect(fetched?.jlptLevel == .n5)
    }

    @Test("setJLPTLevel can clear tag back to nil")
    func jlptLevelClearable() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "本", back: "book", type: .vocabulary)
        await repository.setJLPTLevel(.n4, for: card.id)
        await repository.setJLPTLevel(nil, for: card.id)

        let fetched = await repository.card(by: card.id)
        #expect(fetched?.jlptLevel == nil)
    }

    // MARK: - desiredRetention Plumbing

    /// Seeds a UserProfile with a specific `desiredRetention` — like
    /// `seedActiveProfile` but lets the test control the FSRS retention
    /// target read by `CardModelActor.gradeCard`.
    @MainActor
    private func seedActiveProfileWithRetention(in container: ModelContainer, desiredRetention: Double) throws {
        let context = container.mainContext
        context.insert(UserProfile(
            displayName: "Test",
            settings: ProfileSettings(desiredRetention: desiredRetention)
        ))
        try context.save()
    }

    @Test("gradeCard reads the active profile's desiredRetention: 0.95 due date is sooner than 0.8's")
    func gradeCardUsesActiveProfileDesiredRetention() async throws {
        let lowRetentionContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: lowRetentionContainer, desiredRetention: 0.8)
        let lowRetentionRepository = CardRepository(modelContainer: lowRetentionContainer)

        let highRetentionContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: highRetentionContainer, desiredRetention: 0.95)
        let highRetentionRepository = CardRepository(modelContainer: highRetentionContainer)

        // Same card, same grade, same (approximate) instant — the only
        // difference between the two containers is the active profile's
        // desiredRetention.
        let lowCard = await lowRetentionRepository.createCard(front: "日", back: "day", type: .kanji)
        let highCard = await highRetentionRepository.createCard(front: "日", back: "day", type: .kanji)

        await lowRetentionRepository.gradeCard(cardId: lowCard.id, grade: .good, responseTimeMs: 1000)
        await highRetentionRepository.gradeCard(cardId: highCard.id, grade: .good, responseTimeMs: 1000)

        let lowResult = await lowRetentionRepository.card(by: lowCard.id)
        let highResult = await highRetentionRepository.card(by: highCard.id)

        // Higher desired retention => shorter interval => sooner due date.
        #expect(highResult?.dueDate != nil)
        #expect(lowResult?.dueDate != nil)
        #expect(highResult!.dueDate < lowResult!.dueDate)
    }

    @Test("gradeCard clamps an out-of-band desiredRetention to the 0.8...0.95 range")
    func gradeCardClampsDesiredRetention() async throws {
        // A profile persisted (or migrated) with an out-of-range value
        // (e.g. from a future/older settings surface) must not push the
        // scheduler outside the supported band.
        let extremeContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: extremeContainer, desiredRetention: 0.5)
        let extremeRepository = CardRepository(modelContainer: extremeContainer)

        let clampedContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: clampedContainer, desiredRetention: 0.8)
        let clampedRepository = CardRepository(modelContainer: clampedContainer)

        let extremeCard = await extremeRepository.createCard(front: "日", back: "day", type: .kanji)
        let clampedCard = await clampedRepository.createCard(front: "日", back: "day", type: .kanji)

        await extremeRepository.gradeCard(cardId: extremeCard.id, grade: .good, responseTimeMs: 1000)
        await clampedRepository.gradeCard(cardId: clampedCard.id, grade: .good, responseTimeMs: 1000)

        let extremeResult = await extremeRepository.card(by: extremeCard.id)
        let clampedResult = await clampedRepository.card(by: clampedCard.id)

        // 0.5 should clamp to the same effective 0.8 floor, producing the
        // same due date as a profile explicitly set to 0.8 (within a
        // one-second tolerance for wall-clock skew between the two grades).
        #expect(extremeResult?.dueDate != nil)
        #expect(clampedResult?.dueDate != nil)
        #expect(abs(extremeResult!.dueDate.timeIntervalSince(clampedResult!.dueDate)) < 2.0)
    }

    // MARK: - Save Error Surfacing

    @Test("Successful writes leave lastSaveError nil")
    func lastSaveErrorNilAfterSuccessfulWrites() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        let card = await repository.createCard(front: "日", back: "day", type: .kanji)
        await repository.gradeCard(cardId: card.id, grade: .good, responseTimeMs: 1000)
        await repository.setJLPTLevel(.n5, for: card.id)
        await repository.deleteCard(by: card.id)

        let error = await repository.saveErrorMonitor.lastSaveError
        #expect(error == nil)
    }

    @Test("Grading a nonexistent card does not record a save error")
    func gradeMissingCardRecordsNoSaveError() async throws {
        let container = try makeTestContainer()
        let repository = CardRepository(modelContainer: container)

        // Card-not-found is logged but is not a persistence failure
        await repository.gradeCard(cardId: UUID(), grade: .good, responseTimeMs: 1000)

        let error = await repository.saveErrorMonitor.lastSaveError
        #expect(error == nil)
    }

    @Test("CardSaveErrorMonitor records and clears errors")
    @MainActor
    func saveErrorMonitorRecordsAndClears() async throws {
        let monitor = CardSaveErrorMonitor()
        #expect(monitor.lastSaveError == nil)

        let saveError = CardRepositorySaveError(
            operation: "gradeCard",
            message: "disk full",
            timestamp: Date()
        )
        monitor.record(saveError)
        #expect(monitor.lastSaveError == saveError)
        #expect(monitor.lastSaveError?.operation == "gradeCard")

        monitor.clear()
        #expect(monitor.lastSaveError == nil)
    }
}
