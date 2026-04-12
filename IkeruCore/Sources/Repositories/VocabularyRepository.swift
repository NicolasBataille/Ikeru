import Foundation
import SwiftData
import os

/// Thread-safe repository for VocabularyEntry CRUD, encounter logging, and drill queries.
/// Uses ModelActor for background thread safety with SwiftData.
public final class VocabularyRepository: Sendable {

    private let backgroundActor: VocabularyModelActor

    public init(modelContainer: ModelContainer) {
        self.backgroundActor = VocabularyModelActor(modelContainer: modelContainer)
    }

    // MARK: - Entry CRUD

    /// Add a new word to the personal dictionary.
    public func addEntry(
        word: String,
        reading: String,
        meaning: String,
        jlptLevel: JLPTLevel? = nil
    ) async -> VocabularyEntryDTO {
        await backgroundActor.addEntry(
            word: word,
            reading: reading,
            meaning: meaning,
            jlptLevel: jlptLevel
        )
    }

    /// Fetch an entry by its ID.
    public func entry(by id: UUID) async -> VocabularyEntryDTO? {
        await backgroundActor.entry(by: id)
    }

    /// Fetch an entry by its word (exact match).
    public func entry(byWord word: String) async -> VocabularyEntryDTO? {
        await backgroundActor.entry(byWord: word)
    }

    /// Fetch all dictionary entries.
    public func allEntries() async -> [VocabularyEntryDTO] {
        await backgroundActor.allEntries()
    }

    /// Delete an entry by its ID.
    public func deleteEntry(by id: UUID) async {
        await backgroundActor.deleteEntry(by: id)
    }

    // MARK: - Encounter Logging

    /// Log an encounter for an existing entry. Lightweight — just inserts a row.
    public func logEncounter(
        entryId: UUID,
        source: EncounterSource,
        contextSnippet: String
    ) async {
        await backgroundActor.logEncounter(
            entryId: entryId,
            source: source,
            contextSnippet: contextSnippet
        )
    }

    /// Log an encounter by word. Creates the entry if it doesn't exist yet (pre-tracking).
    public func logEncounterByWord(
        word: String,
        reading: String,
        meaning: String,
        source: EncounterSource,
        contextSnippet: String
    ) async {
        await backgroundActor.logEncounterByWord(
            word: word,
            reading: reading,
            meaning: meaning,
            source: source,
            contextSnippet: contextSnippet
        )
    }

    /// Fetch encounters for a given entry.
    public func encounters(for entryId: UUID) async -> [VocabularyEncounterDTO] {
        await backgroundActor.encounters(for: entryId)
    }

    // MARK: - Drill Queries

    /// Fetch entries due for review before the given date.
    public func dueEntries(before date: Date) async -> [VocabularyEntryDTO] {
        await backgroundActor.dueEntries(before: date)
    }

    /// Grade a vocabulary entry: atomically updates FSRS state and creates encounter.
    public func gradeEntry(
        entryId: UUID,
        grade: Grade,
        responseTimeMs: Int,
        now: Date = Date()
    ) async {
        await backgroundActor.gradeEntry(
            entryId: entryId,
            grade: grade,
            responseTimeMs: responseTimeMs,
            now: now
        )
    }

    /// Check whether a word already exists in the dictionary.
    public func hasEntry(forWord word: String) async -> Bool {
        await backgroundActor.entry(byWord: word) != nil
    }
}

// MARK: - Data Transfer Objects

/// Lightweight, Sendable snapshot of a VocabularyEntry for cross-actor transfer.
public struct VocabularyEntryDTO: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let word: String
    public let reading: String
    public let meaning: String
    public let jlptLevel: JLPTLevel?
    public let fsrsState: FSRSState
    public let easeFactor: Double
    public let interval: Int
    public let dueDate: Date
    public let lapseCount: Int
    public let isInDictionary: Bool
    public let createdAt: Date
    public let encounterCount: Int

    public var mastery: MasteryLevel {
        MasteryLevel.from(fsrsState: fsrsState)
    }
}

/// Lightweight, Sendable snapshot of a VocabularyEncounter for cross-actor transfer.
public struct VocabularyEncounterDTO: Sendable, Identifiable {
    public let id: UUID
    public let entryId: UUID?
    public let source: EncounterSource
    public let contextSnippet: String
    public let timestamp: Date
}

// MARK: - Model Actor

@ModelActor
actor VocabularyModelActor {

    func addEntry(
        word: String,
        reading: String,
        meaning: String,
        jlptLevel: JLPTLevel?
    ) -> VocabularyEntryDTO {
        // If a pre-tracked entry exists, promote it to dictionary
        let predicate = #Predicate<VocabularyEntry> { $0.word == word }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.isInDictionary = true
            existing.meaning = meaning
            if let jlptLevel { existing.jlptLevel = jlptLevel }
            try? modelContext.save()
            Logger.vocabulary.debug("Promoted pre-tracked entry to dictionary: \(word)")
            return existing.toDTO()
        }

        let entry = VocabularyEntry(
            word: word,
            reading: reading,
            meaning: meaning,
            jlptLevel: jlptLevel,
            isInDictionary: true
        )
        modelContext.insert(entry)
        try? modelContext.save()
        Logger.vocabulary.debug("Added vocab entry: \(word)")
        return entry.toDTO()
    }

    func entry(by id: UUID) -> VocabularyEntryDTO? {
        let predicate = #Predicate<VocabularyEntry> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first?.toDTO()
    }

    func entry(byWord word: String) -> VocabularyEntryDTO? {
        let predicate = #Predicate<VocabularyEntry> { $0.word == word }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first?.toDTO()
    }

    func allEntries() -> [VocabularyEntryDTO] {
        let predicate = #Predicate<VocabularyEntry> { $0.isInDictionary == true }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func deleteEntry(by id: UUID) {
        let predicate = #Predicate<VocabularyEntry> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first else { return }
        modelContext.delete(entry)
        try? modelContext.save()
        Logger.vocabulary.debug("Deleted vocab entry: \(entry.word)")
    }

    // MARK: - Encounter Logging

    func logEncounter(
        entryId: UUID,
        source: EncounterSource,
        contextSnippet: String
    ) {
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first else {
            Logger.vocabulary.warning("Entry not found for encounter logging: \(entryId)")
            return
        }

        let encounter = VocabularyEncounter(
            source: source,
            contextSnippet: contextSnippet,
            entry: entry
        )
        modelContext.insert(encounter)
        try? modelContext.save()
    }

    func logEncounterByWord(
        word: String,
        reading: String,
        meaning: String,
        source: EncounterSource,
        contextSnippet: String
    ) {
        // Find or create the entry
        let predicate = #Predicate<VocabularyEntry> { $0.word == word }
        let descriptor = FetchDescriptor(predicate: predicate)
        let existing = (try? modelContext.fetch(descriptor))?.first

        let entry: VocabularyEntry
        if let existing {
            entry = existing
        } else {
            entry = VocabularyEntry(word: word, reading: reading, meaning: meaning, isInDictionary: false)
            modelContext.insert(entry)
        }

        let encounter = VocabularyEncounter(
            source: source,
            contextSnippet: contextSnippet,
            entry: entry
        )
        modelContext.insert(encounter)
        try? modelContext.save()
    }

    func encounters(for entryId: UUID) -> [VocabularyEncounterDTO] {
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first,
              let encounters = entry.encounters else {
            return []
        }
        return encounters
            .sorted { $0.timestamp > $1.timestamp }
            .map { $0.toDTO() }
    }

    // MARK: - Drill Queries

    func dueEntries(before date: Date) -> [VocabularyEntryDTO] {
        let predicate = #Predicate<VocabularyEntry> { $0.isInDictionary == true && $0.dueDate < date }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    func gradeEntry(
        entryId: UUID,
        grade: Grade,
        responseTimeMs: Int,
        now: Date
    ) {
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first else {
            Logger.vocabulary.error("Entry not found for grading: \(entryId)")
            return
        }

        let newState = FSRSService.schedule(state: entry.fsrsState, grade: grade, now: now)
        let newDueDate = FSRSService.dueDate(for: newState, now: now)
        let intervalDays = max(1, Int(newDueDate.timeIntervalSince(now) / 86400))

        entry.fsrsState = newState
        entry.dueDate = newDueDate
        entry.lapseCount = newState.lapses
        entry.interval = intervalDays

        // Log the drill as an encounter
        let encounter = VocabularyEncounter(
            source: .srsSession,
            contextSnippet: "Drill: \(grade)",
            entry: entry
        )
        modelContext.insert(encounter)
        try? modelContext.save()

        Logger.vocabulary.debug(
            "Graded vocab \(entry.word): grade=\(grade.rawValue), stability=\(newState.stability)"
        )
    }
}

// MARK: - DTO Conversion

extension VocabularyEntry {
    func toDTO() -> VocabularyEntryDTO {
        VocabularyEntryDTO(
            id: id,
            word: word,
            reading: reading,
            meaning: meaning,
            jlptLevel: jlptLevel,
            fsrsState: fsrsState,
            easeFactor: easeFactor,
            interval: interval,
            dueDate: dueDate,
            lapseCount: lapseCount,
            isInDictionary: isInDictionary,
            createdAt: createdAt,
            encounterCount: encounters?.count ?? 0
        )
    }
}

extension VocabularyEncounter {
    func toDTO() -> VocabularyEncounterDTO {
        VocabularyEncounterDTO(
            id: id,
            entryId: entry?.id,
            source: source,
            contextSnippet: contextSnippet,
            timestamp: timestamp
        )
    }
}
