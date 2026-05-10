import Foundation
import SwiftData
import os

// MARK: - DTO

/// Sendable, value-type snapshot of a `DailyTerm` row for cross-actor transfer.
public struct DailyTermDTO: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let word: String
    public let reading: String
    public let pronunciation: String
    public let meaning: String
    public let caption: String
    public let jlptLevel: JLPTLevel?
    public let revealedAt: Date?
    public let addedToDictionary: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        date: Date,
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        caption: String,
        jlptLevel: JLPTLevel?,
        revealedAt: Date?,
        addedToDictionary: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.date = date
        self.word = word
        self.reading = reading
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.caption = caption
        self.jlptLevel = jlptLevel
        self.revealedAt = revealedAt
        self.addedToDictionary = addedToDictionary
        self.createdAt = createdAt
    }

    /// Whether the user has opened the reveal popup for this term.
    public var hasBeenRevealed: Bool { revealedAt != nil }
}

// MARK: - Repository

/// Thread-safe CRUD for `DailyTerm` rows. Uses a `ModelActor` so SwiftData
/// access stays off the main thread.
public final class DailyTermRepository: Sendable {

    private let actor: DailyTermModelActor

    public init(modelContainer: ModelContainer) {
        self.actor = DailyTermModelActor(modelContainer: modelContainer)
    }

    /// Fetch the term for the given calendar day if it exists.
    public func term(on day: Date) async -> DailyTermDTO? {
        await actor.term(on: day)
    }

    /// Persist a new term for the given day. If a row already exists for
    /// that day, it is returned unchanged.
    @discardableResult
    public func upsertTerm(
        on day: Date,
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        caption: String,
        jlptLevel: JLPTLevel?
    ) async -> DailyTermDTO {
        await actor.upsertTerm(
            on: day,
            word: word,
            reading: reading,
            pronunciation: pronunciation,
            meaning: meaning,
            caption: caption,
            jlptLevel: jlptLevel
        )
    }

    /// Mark the term row as revealed (i.e. the user opened the popup).
    public func markRevealed(termId: UUID, at date: Date = Date()) async {
        await actor.markRevealed(termId: termId, at: date)
    }

    /// Mark the term as added to the user's personal dictionary.
    public func markAddedToDictionary(termId: UUID) async {
        await actor.markAddedToDictionary(termId: termId)
    }

    /// All terms whose `date` falls strictly before `day`, most-recent first.
    public func termsBefore(_ day: Date, limit: Int = 30) async -> [DailyTermDTO] {
        await actor.termsBefore(day, limit: limit)
    }

    /// Set of words already used in any past term — used to avoid repeats
    /// when picking today's term.
    public func usedWords() async -> Set<String> {
        await actor.usedWords()
    }
}

// MARK: - Model Actor

@ModelActor
actor DailyTermModelActor {

    func term(on day: Date) -> DailyTermDTO? {
        let normalised = Calendar.current.startOfDay(for: day)
        let predicate = #Predicate<DailyTerm> { $0.date == normalised }
        let descriptor = FetchDescriptor(predicate: predicate)
        return (try? modelContext.fetch(descriptor))?.first?.toDTO()
    }

    func upsertTerm(
        on day: Date,
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        caption: String,
        jlptLevel: JLPTLevel?
    ) -> DailyTermDTO {
        let normalised = Calendar.current.startOfDay(for: day)
        let predicate = #Predicate<DailyTerm> { $0.date == normalised }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing.toDTO()
        }

        let term = DailyTerm(
            date: normalised,
            word: word,
            reading: reading,
            pronunciation: pronunciation,
            meaning: meaning,
            caption: caption,
            jlptLevel: jlptLevel
        )
        modelContext.insert(term)
        try? modelContext.save()
        Logger.dailyTerm.info("Daily term scheduled for \(normalised, privacy: .public): \(word, privacy: .public)")
        return term.toDTO()
    }

    func markRevealed(termId: UUID, at date: Date) {
        let predicate = #Predicate<DailyTerm> { $0.id == termId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let term = (try? modelContext.fetch(descriptor))?.first else { return }
        if term.revealedAt == nil {
            term.revealedAt = date
            try? modelContext.save()
            Logger.dailyTerm.debug("Daily term revealed: \(term.word, privacy: .public)")
        }
    }

    func markAddedToDictionary(termId: UUID) {
        let predicate = #Predicate<DailyTerm> { $0.id == termId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let term = (try? modelContext.fetch(descriptor))?.first else { return }
        term.addedToDictionary = true
        try? modelContext.save()
    }

    func termsBefore(_ day: Date, limit: Int) -> [DailyTermDTO] {
        let normalised = Calendar.current.startOfDay(for: day)
        let predicate = #Predicate<DailyTerm> { $0.date < normalised }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\DailyTerm.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func usedWords() -> Set<String> {
        let descriptor = FetchDescriptor<DailyTerm>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Set(all.map(\.word))
    }
}

// MARK: - DTO Conversion

extension DailyTerm {
    func toDTO() -> DailyTermDTO {
        DailyTermDTO(
            id: id,
            date: date,
            word: word,
            reading: reading,
            pronunciation: pronunciation,
            meaning: meaning,
            caption: caption,
            jlptLevel: jlptLevel,
            revealedAt: revealedAt,
            addedToDictionary: addedToDictionary,
            createdAt: createdAt
        )
    }
}
