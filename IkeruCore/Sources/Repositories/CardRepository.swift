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
    public static let leechThreshold = 3

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

    /// Fetch all cards belonging to the currently active profile.
    public func allCards() async -> [CardDTO] {
        await backgroundActor.allCards()
    }

    /// Attaches any orphan cards (profile == nil) to the active profile.
    /// One-shot migration for users created before per-profile card scoping.
    public func attachOrphanCards() async {
        await backgroundActor.attachOrphanCards()
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

    /// Fetch all review logs within a date range across all cards.
    public func allReviewLogs(from startDate: Date, to endDate: Date) async -> [ReviewLogDTO] {
        await backgroundActor.allReviewLogs(from: startDate, to: endDate)
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

    public init(
        id: UUID,
        front: String,
        back: String,
        type: CardType,
        fsrsState: FSRSState,
        easeFactor: Double,
        interval: Int,
        dueDate: Date,
        lapseCount: Int,
        leechFlag: Bool
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.type = type
        self.fsrsState = fsrsState
        self.easeFactor = easeFactor
        self.interval = interval
        self.dueDate = dueDate
        self.lapseCount = lapseCount
        self.leechFlag = leechFlag
    }
}

/// Lightweight, Sendable snapshot of a ReviewLog for cross-actor transfer.
public struct ReviewLogDTO: Sendable, Identifiable {
    public let id: UUID
    public let cardId: UUID?
    public let cardType: CardType?
    public let timestamp: Date
    public let grade: Grade
    public let responseTimeMs: Int
}

// MARK: - Model Actor

/// ModelActor that performs all SwiftData operations on its own serial executor.
/// This ensures thread safety for all database reads and writes.
@ModelActor
actor CardModelActor {

    // MARK: - Active Profile Scoping

    /// Reads the UserDefaults-backed active profile id. Returns nil if unset.
    private func activeProfileID() -> UUID? {
        guard
            let raw = UserDefaults.standard.string(forKey: UserProfile.activeProfileIDDefaultsKey),
            !raw.isEmpty,
            let id = UUID(uuidString: raw)
        else { return nil }
        return id
    }

    /// Fetches the currently-active UserProfile, or the oldest as a fallback.
    private func fetchActiveProfile() -> UserProfile? {
        if let id = activeProfileID() {
            let predicate = #Predicate<UserProfile> { $0.id == id }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let profile = (try? modelContext.fetch(descriptor))?.first {
                return profile
            }
        }
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Returns cards belonging to the active profile (including legacy
    /// orphans with `profile == nil`, once migrated). See `attachOrphanCards`.
    private func activeProfileCards() -> [Card] {
        guard let profile = fetchActiveProfile() else { return [] }
        return profile.cards ?? []
    }

    // MARK: - CRUD (scoped to active profile)

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
        card.profile = fetchActiveProfile()
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

    /// All cards belonging to the active profile.
    func allCards() -> [CardDTO] {
        activeProfileCards().map { $0.toDTO() }
    }

    /// Attach any orphan cards (profile == nil) to the oldest profile.
    /// Safe to call on every launch — no-op once all cards have a profile.
    func attachOrphanCards() {
        guard let fallback = fetchActiveProfile() else { return }
        let predicate = #Predicate<Card> { $0.profile == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let orphans = try? modelContext.fetch(descriptor), !orphans.isEmpty else { return }
        for card in orphans { card.profile = fallback }
        try? modelContext.save()
        Logger.srs.info("Attached \(orphans.count) orphan cards to profile: \(fallback.displayName)")
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
        activeProfileCards()
            .filter { $0.dueDate < date }
            .map { $0.toDTO() }
    }

    func leechCards() -> [CardDTO] {
        activeProfileCards()
            .filter { $0.leechFlag }
            .map { $0.toDTO() }
    }

    func cards(byType type: CardType) -> [CardDTO] {
        let raw = type.rawValue
        return activeProfileCards()
            .filter { $0.typeRawValue == raw }
            .map { $0.toDTO() }
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

        Logger.srs.debug("Graded card \(card.front): grade=\(grade.rawValue), stability=\(newState.stability), due=\(newDueDate)")
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

    func allReviewLogs(from startDate: Date, to endDate: Date) -> [ReviewLogDTO] {
        let predicate = #Predicate<ReviewLog> {
            $0.timestamp >= startDate && $0.timestamp <= endDate
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
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
            cardId: card?.id,
            cardType: card?.type,
            timestamp: timestamp,
            grade: grade,
            responseTimeMs: responseTimeMs
        )
    }
}
