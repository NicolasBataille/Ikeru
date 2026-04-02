import Foundation
import SwiftData
import os

/// Thread-safe repository for Card CRUD and query operations.
/// Uses ModelActor for background thread safety with SwiftData.
///
/// All operations are async and use SwiftData's implicit transaction/autosave
/// to ensure atomic writes. The `gradeCard` method atomically updates
/// the card's FSRS state and creates a ReviewLog entry.
public final class CardRepository: Sendable {

    /// The model actor performing thread-safe background operations.
    private let backgroundActor: CardModelActor

    /// Leech threshold — a card is flagged as leech after this many lapses.
    public static let leechThreshold = 8

    public init(modelContainer: ModelContainer) {
        self.backgroundActor = CardModelActor(modelContainer: modelContainer)
    }

    // MARK: - CRUD Operations

    /// Create a new card and persist it.
    public func createCard(
        front: String,
        back: String,
        type: CardType,
        dueDate: Date = Date(),
        leechFlag: Bool = false
    ) async -> CardDTO {
        await backgroundActor.createCard(
            front: front,
            back: back,
            type: type,
            dueDate: dueDate,
            leechFlag: leechFlag
        )
    }

    /// Fetch a card by its ID.
    public func card(by id: UUID) async -> CardDTO? {
        await backgroundActor.card(by: id)
    }

    /// Fetch all cards.
    public func allCards() async -> [CardDTO] {
        await backgroundActor.allCards()
    }

    /// Delete a card by its ID.
    public func deleteCard(by id: UUID) async {
        await backgroundActor.deleteCard(by: id)
    }

    // MARK: - Query Operations

    /// Fetch cards that are due for review before the given date.
    public func dueCards(before date: Date) async -> [CardDTO] {
        await backgroundActor.dueCards(before: date)
    }

    /// Fetch cards that are flagged as leeches.
    public func leechCards() async -> [CardDTO] {
        await backgroundActor.leechCards()
    }

    /// Fetch cards filtered by type.
    public func cards(byType type: CardType) async -> [CardDTO] {
        await backgroundActor.cards(byType: type)
    }

    // MARK: - Review Operations

    /// Grade a card: atomically updates the card's FSRS state and creates a ReviewLog.
    /// This is an atomic operation — the card state and review log are persisted together.
    public func gradeCard(
        cardId: UUID,
        grade: Grade,
        responseTimeMs: Int,
        now: Date = Date()
    ) async {
        await backgroundActor.gradeCard(
            cardId: cardId,
            grade: grade,
            responseTimeMs: responseTimeMs,
            now: now,
            leechThreshold: Self.leechThreshold
        )
    }

    /// Fetch review logs for a given card.
    public func reviewLogs(for cardId: UUID) async -> [ReviewLogDTO] {
        await backgroundActor.reviewLogs(for: cardId)
    }
}

// MARK: - Data Transfer Objects

/// Lightweight, Sendable snapshot of a Card for cross-actor transfer.
public struct CardDTO: Sendable, Identifiable {
    public let id: UUID
    public let front: String
    public let back: String
    public let type: CardType
    public let fsrsState: FSRSState
    public let easeFactor: Double
    public let interval: Int
    public let dueDate: Date
    public let lapseCount: Int
    public let leechFlag: Bool
}

/// Lightweight, Sendable snapshot of a ReviewLog for cross-actor transfer.
public struct ReviewLogDTO: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let grade: Grade
    public let responseTimeMs: Int
}

// MARK: - Model Actor

/// ModelActor that performs all SwiftData operations on its own serial executor.
/// This ensures thread safety for all database reads and writes.
@ModelActor
actor CardModelActor {

    func createCard(
        front: String,
        back: String,
        type: CardType,
        dueDate: Date,
        leechFlag: Bool
    ) -> CardDTO {
        let card = Card(
            front: front,
            back: back,
            type: type,
            dueDate: dueDate,
            leechFlag: leechFlag
        )
        modelContext.insert(card)
        try? modelContext.save()
        Logger.srs.debug("Created card: \(card.front)")
        return card.toDTO()
    }

    func card(by id: UUID) -> CardDTO? {
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first?.toDTO()
    }

    func allCards() -> [CardDTO] {
        let descriptor = FetchDescriptor<Card>()
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func deleteCard(by id: UUID) {
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let cards = try? modelContext.fetch(descriptor),
              let card = cards.first else {
            return
        }
        modelContext.delete(card)
        try? modelContext.save()
        Logger.srs.debug("Deleted card: \(card.front)")
    }

    func dueCards(before date: Date) -> [CardDTO] {
        let predicate = #Predicate<Card> { $0.dueDate < date }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func leechCards() -> [CardDTO] {
        let predicate = #Predicate<Card> { $0.leechFlag == true }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func cards(byType type: CardType) -> [CardDTO] {
        let typeRawValue = type.rawValue
        let predicate = #Predicate<Card> { $0.typeRawValue == typeRawValue }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func gradeCard(
        cardId: UUID,
        grade: Grade,
        responseTimeMs: Int,
        now: Date,
        leechThreshold: Int
    ) {
        let predicate = #Predicate<Card> { $0.id == cardId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let cards = try? modelContext.fetch(descriptor),
              let card = cards.first else {
            Logger.srs.error("Card not found for grading: \(cardId)")
            return
        }

        // Compute new FSRS state (pure function)
        let newState = FSRSService.schedule(state: card.fsrsState, grade: grade, now: now)

        // Compute new due date
        let newDueDate = FSRSService.dueDate(for: newState, now: now)

        // Compute interval in days from due date
        let intervalDays = max(1, Int(newDueDate.timeIntervalSince(now) / 86400))

        // Update card state atomically
        card.fsrsState = newState
        card.dueDate = newDueDate
        card.lapseCount = newState.lapses
        card.interval = intervalDays

        // Detect leech
        if card.lapseCount >= leechThreshold {
            card.leechFlag = true
            Logger.srs.warning("Card flagged as leech: \(card.front), lapses=\(card.lapseCount)")
        }

        // Create review log in the same transaction
        let log = ReviewLog(card: card, grade: grade, responseTimeMs: responseTimeMs, timestamp: now)
        modelContext.insert(log)

        // Save atomically — both card update and review log persist together
        try? modelContext.save()

        Logger.srs.debug(
            "Graded card \(card.front): grade=\(grade.rawValue), " +
            "stability=\(newState.stability), due=\(newDueDate)"
        )
    }

    func reviewLogs(for cardId: UUID) -> [ReviewLogDTO] {
        // Fetch via the card's relationship for reliability
        let predicate = #Predicate<Card> { $0.id == cardId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let cards = try? modelContext.fetch(descriptor),
              let card = cards.first,
              let logs = card.reviewLogs else {
            return []
        }
        return logs.map { $0.toDTO() }
    }
}

// MARK: - DTO Conversion Extensions

extension Card {
    func toDTO() -> CardDTO {
        CardDTO(
            id: id,
            front: front,
            back: back,
            type: type,
            fsrsState: fsrsState,
            easeFactor: easeFactor,
            interval: interval,
            dueDate: dueDate,
            lapseCount: lapseCount,
            leechFlag: leechFlag
        )
    }
}

extension ReviewLog {
    func toDTO() -> ReviewLogDTO {
        ReviewLogDTO(
            id: id,
            timestamp: timestamp,
            grade: grade,
            responseTimeMs: responseTimeMs
        )
    }
}
