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

    @Test("Query cards by type returns correct subset")
    func cardsByType() async throws {
        let container = try makeTestContainer()
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
}
