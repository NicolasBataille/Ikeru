import Foundation
import Observation
import SwiftData
import os

// MARK: - Save Error Surfacing

/// Snapshot of a persistence failure, surfaced via `CardSaveErrorMonitor`.
/// `message` is a diagnostic description of the underlying error — not
/// localized UI copy. UI layers presenting it should show their own
/// localized message.
public struct CardRepositorySaveError: Sendable, Equatable {
    /// The repository operation that failed (e.g. "gradeCard").
    public let operation: String
    /// Diagnostic description of the underlying error.
    public let message: String
    /// When the failure occurred.
    public let timestamp: Date

    public init(operation: String, message: String, timestamp: Date) {
        self.operation = operation
        self.message = message
        self.timestamp = timestamp
    }
}

/// Observable, MainActor-isolated surface for persistence failures.
///
/// `CardRepository`'s write methods keep their non-throwing signatures for
/// call-site compatibility; instead of throwing, a failed
/// `modelContext.save()` is logged at `.error` and recorded here so SwiftUI
/// can watch `lastSaveError` (e.g. to show a toast when a grading
/// transaction fails to persist).
@Observable
@MainActor
public final class CardSaveErrorMonitor {

    /// The most recent save failure, or `nil` if none has occurred.
    public private(set) var lastSaveError: CardRepositorySaveError? = nil

    public nonisolated init() {}

    /// Record a persistence failure. Internal — only `CardRepository` writes.
    func record(_ error: CardRepositorySaveError) {
        lastSaveError = error
    }

    /// Clear the recorded error (e.g. after the UI has surfaced it).
    public func clear() {
        lastSaveError = nil
    }
}

/// Thread-safe repository for Card CRUD and query operations.
/// Uses ModelActor for background thread safety with SwiftData.
///
/// All operations are async and use explicit `modelContext.save()` calls
/// to ensure atomic writes. The `gradeCard` method atomically updates
/// the card's FSRS state and creates a ReviewLog entry.
///
/// Save failures are never silently swallowed: they are logged at `.error`
/// and published on `saveErrorMonitor.lastSaveError` for the UI to observe.
public final class CardRepository: Sendable {

    /// The model actor performing thread-safe background operations.
    private let backgroundActor: CardModelActor

    /// Observable surface for persistence failures. UI layers can watch
    /// `saveErrorMonitor.lastSaveError` to detect failed writes (most
    /// importantly failed grading transactions).
    public let saveErrorMonitor: CardSaveErrorMonitor

    /// Leech threshold — a card is flagged as leech after this many lapses.
    public static let leechThreshold = 3

    public init(modelContainer: ModelContainer) {
        self.backgroundActor = CardModelActor(modelContainer: modelContainer)
        self.saveErrorMonitor = CardSaveErrorMonitor()
    }

    /// Log a save failure at `.error` and publish it on `saveErrorMonitor`.
    private func reportSaveFailure(operation: String, error: any Error) async {
        Logger.srs.error("Persistence failure in \(operation): \(error.localizedDescription)")
        await saveErrorMonitor.record(
            CardRepositorySaveError(
                operation: operation,
                message: error.localizedDescription,
                timestamp: Date()
            )
        )
    }

    // MARK: - CRUD Operations

    /// Create a new card and persist it.
    /// On save failure the in-memory DTO is still returned (with its real id),
    /// and the failure is logged and published on `saveErrorMonitor`.
    public func createCard(
        front: String,
        back: String,
        type: CardType,
        dueDate: Date = Date(),
        leechFlag: Bool = false
    ) async -> CardDTO {
        let (dto, saveError) = await backgroundActor.createCard(
            front: front,
            back: back,
            type: type,
            dueDate: dueDate,
            leechFlag: leechFlag
        )
        if let saveError {
            await reportSaveFailure(operation: "createCard", error: saveError)
        }
        return dto
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
        do {
            try await backgroundActor.attachOrphanCards()
        } catch {
            await reportSaveFailure(operation: "attachOrphanCards", error: error)
        }
    }

    /// Delete a card by its ID.
    public func deleteCard(by id: UUID) async {
        do {
            try await backgroundActor.deleteCard(by: id)
        } catch {
            await reportSaveFailure(operation: "deleteCard", error: error)
        }
    }

    /// Set (or clear) the JLPT level for a card. Used by `JLPTBackfillService`
    /// to tag existing seed cards on first launch.
    public func setJLPTLevel(_ level: JLPTLevel?, for cardId: UUID) async {
        do {
            try await backgroundActor.setJLPTLevel(level, for: cardId)
        } catch {
            await reportSaveFailure(operation: "setJLPTLevel", error: error)
        }
    }

    // MARK: - Query Operations

    /// Fetch cards that are due for review before the given date.
    /// Order is unspecified — use `dueCardsSortedByDueDate(before:)` when
    /// overdue-first ordering matters (e.g. session composition).
    public func dueCards(before date: Date) async -> [CardDTO] {
        await backgroundActor.dueCards(before: date)
    }

    /// Fetch cards due before the given date, sorted by `dueDate` ascending
    /// (most overdue first). Sorting is done in memory for now; moving the
    /// filter + sort into a `#Predicate`-based `FetchDescriptor` with a
    /// `SortDescriptor` is future work (see remediation plan item 8.3).
    public func dueCardsSortedByDueDate(before date: Date) async -> [CardDTO] {
        await backgroundActor.dueCardsSortedByDueDate(before: date)
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
    /// If the save fails, the failure is logged at `.error` and published on
    /// `saveErrorMonitor` so the UI can warn that the grade did not persist.
    public func gradeCard(
        cardId: UUID,
        grade: Grade,
        responseTimeMs: Int,
        now: Date = Date()
    ) async {
        do {
            try await backgroundActor.gradeCard(
                cardId: cardId,
                grade: grade,
                responseTimeMs: responseTimeMs,
                now: now,
                leechThreshold: Self.leechThreshold
            )
        } catch {
            await reportSaveFailure(operation: "gradeCard", error: error)
        }
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
    /// Optional JLPT level tag. `nil` for legacy/untagged cards (e.g. kana,
    /// user-authored). Populated by `JLPTBackfillService` for known seed
    /// vocabulary and kanji.
    public let jlptLevel: JLPTLevel?

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
        leechFlag: Bool,
        jlptLevel: JLPTLevel? = nil
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
        self.jlptLevel = jlptLevel
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

    /// Creates and persists a card. Returns the DTO (with the real card id)
    /// alongside an optional save error, so a failed save can be reported
    /// without losing the caller's handle on the created card.
    func createCard(
        front: String,
        back: String,
        type: CardType,
        dueDate: Date,
        leechFlag: Bool
    ) -> (dto: CardDTO, saveError: (any Error)?) {
        let card = Card(
            front: front,
            back: back,
            type: type,
            dueDate: dueDate,
            leechFlag: leechFlag
        )
        card.profile = fetchActiveProfile()
        modelContext.insert(card)
        do {
            try modelContext.save()
        } catch {
            return (card.toDTO(), error)
        }
        Logger.srs.debug("Created card: \(card.front)")
        return (card.toDTO(), nil)
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
    func attachOrphanCards() throws {
        guard let fallback = fetchActiveProfile() else { return }
        let predicate = #Predicate<Card> { $0.profile == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let orphans = try? modelContext.fetch(descriptor), !orphans.isEmpty else { return }
        for card in orphans { card.profile = fallback }
        try modelContext.save()
        Logger.srs.info("Attached \(orphans.count) orphan cards to profile: \(fallback.displayName)")
    }

    func deleteCard(by id: UUID) throws {
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let cards = try? modelContext.fetch(descriptor),
              let card = cards.first else {
            return
        }
        modelContext.delete(card)
        try modelContext.save()
        Logger.srs.debug("Deleted card: \(card.front)")
    }

    func setJLPTLevel(_ level: JLPTLevel?, for cardId: UUID) throws {
        let predicate = #Predicate<Card> { $0.id == cardId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let cards = try? modelContext.fetch(descriptor),
              let card = cards.first else {
            Logger.srs.error("Card not found for JLPT tagging: \(cardId)")
            return
        }
        card.jlptLevel = level
        try modelContext.save()
    }

    func dueCards(before date: Date) -> [CardDTO] {
        activeProfileCards()
            .filter { $0.dueDate < date }
            .map { $0.toDTO() }
    }

    /// Due cards sorted by dueDate ascending (most overdue first).
    /// In-memory sort for now — future work: `#Predicate` + `SortDescriptor`
    /// FetchDescriptor so filtering/sorting happen in the store.
    func dueCardsSortedByDueDate(before date: Date) -> [CardDTO] {
        dueCards(before: date)
            .sorted { $0.dueDate < $1.dueDate }
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
    ) throws {
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

        // Save atomically — both card update and review log persist together.
        // A failed save must NOT be swallowed: it would silently desync the
        // scheduler state from the review history. Propagate to the facade,
        // which logs and publishes the failure.
        try modelContext.save()

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
            leechFlag: leechFlag,
            jlptLevel: jlptLevel
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
