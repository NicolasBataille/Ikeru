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

    /// Corrige les trois champs saisis d'une entrée (OBS2-007/013).
    ///
    /// Il n'existait aucun moyen de réparer une entrée : on pouvait créer un
    /// mot sans sens ni lecture — une carte que le SRS sert ensuite et que
    /// personne ne peut réviser — et rien ne permettait d'y revenir. La
    /// validation à la saisie empêche d'en créer de nouvelles ; ceci répare
    /// celles qui existent déjà.
    ///
    /// Ne touche NI l'état FSRS NI l'historique de rencontres : corriger une
    /// faute de frappe ne doit pas réinitialiser une progression.
    @discardableResult
    public func updateEntry(
        id: UUID,
        word: String,
        reading: String,
        meaning: String
    ) async -> VocabularyEntryDTO? {
        await backgroundActor.updateEntry(id: id, word: word, reading: reading, meaning: meaning)
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

    /// The active profile's desired retention (clamped) — exposed so the
    /// vocab drill's predicted intervals match what `gradeEntry` schedules.
    public func activeDesiredRetention() async -> Double {
        await backgroundActor.activeDesiredRetention()
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

    // MARK: - Active Profile (desired retention)

    /// Reads the UserDefaults-backed active profile id. Returns nil if unset.
    /// Mirrors `CardModelActor.activeProfileID()` so both FSRS surfaces
    /// resolve the same profile.
    private func activeProfileID() -> UUID? {
        guard
            let raw = UserDefaults.standard.string(forKey: UserProfile.activeProfileIDDefaultsKey),
            !raw.isEmpty,
            let id = UUID(uuidString: raw)
        else { return nil }
        return id
    }

    /// Both lookups exclude tombstoned profiles. The *fallback* is the one
    /// that matters: without the filter, deleting the active profile would
    /// leave the "oldest profile" fallback resolving straight back to the
    /// deleted one, and its cards/settings would keep driving the app.
    private func fetchActiveProfile() -> UserProfile? {
        if let id = activeProfileID() {
            let predicate = #Predicate<UserProfile> { $0.id == id && $0.deletedAt == nil }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let profile = (try? modelContext.fetch(descriptor))?.first {
                return profile
            }
        }
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// The active profile's desired retention, clamped to the scheduler's
    /// supported band. Mirrors `CardModelActor.activeDesiredRetention()`.
    /// Public so the vocab drill view-model's predicted intervals use the
    /// same retention the actual grading will.
    public func activeDesiredRetention() -> Double {
        guard let profile = fetchActiveProfile() else { return 0.9 }
        return min(
            max(profile.settings.desiredRetention, FSRSService.desiredRetentionRange.lowerBound),
            FSRSService.desiredRetentionRange.upperBound
        )
    }

    func addEntry(
        word: String,
        reading: String,
        meaning: String,
        jlptLevel: JLPTLevel?
    ) -> VocabularyEntryDTO {
        // If a pre-tracked entry exists, promote it to dictionary.
        //
        // `deletedAt == nil` is load-bearing, not defensive: re-adding a word
        // the learner previously deleted must mint a NEW entry, never revive
        // the tombstoned one. Merge rule 4 (`SyncMergeRules.resolveWinner`)
        // lets a tombstone win regardless of timestamp, so a revived row would
        // be silently re-deleted by the next pull that carries the old
        // `deleted_at` — the word would vanish again for no visible reason.
        // See `SoftDeletable`'s "never un-tombstone" note.
        let predicate = #Predicate<VocabularyEntry> { $0.word == word && $0.deletedAt == nil }
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
        let predicate = #Predicate<VocabularyEntry> { $0.id == id && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first?.toDTO()
    }

    func entry(byWord word: String) -> VocabularyEntryDTO? {
        let predicate = #Predicate<VocabularyEntry> { $0.word == word && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first?.toDTO()
    }

    func allEntries() -> [VocabularyEntryDTO] {
        let predicate = #Predicate<VocabularyEntry> { $0.isInDictionary == true && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.toDTO() }
    }

    /// Soft-deletes an entry: stamps `deletedAt`/`updatedAt` instead of
    /// destroying the row, so the deletion has something to push
    /// (`deleted_at`) and survives a pull-cursor reset. A hard delete here
    /// left the server row intact with `deleted_at = null`, and the entry
    /// came back the next time the cursor rewound.
    ///
    /// Cascades to the entry's encounters by hand. The `@Relationship`'s
    /// `.cascade` rule only fires on a real `modelContext.delete(_:)`, so
    /// without this loop the encounters would stay live — visible to
    /// `SyncModelActor.pushDirtyVocabularyEncounters` and, on the pull side,
    /// re-materialising an encounter list for a word that no longer exists.
    /// Voir la doc de la façade publique. `updatedAt` est bourré à la main :
    /// `SyncModelActor.isDirty` compare `updatedAt` à `syncedAt`, donc une
    /// correction qui ne le touche pas ne partirait JAMAIS au serveur — le mot
    /// serait réparé sur cet appareil et resterait cassé sur les autres.
    func updateEntry(
        id: UUID,
        word: String,
        reading: String,
        meaning: String
    ) -> VocabularyEntryDTO? {
        let predicate = #Predicate<VocabularyEntry> { $0.id == id && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return nil }
        entry.word = word
        entry.reading = reading
        entry.meaning = meaning
        entry.updatedAt = Date()
        try? modelContext.save()
        Logger.vocabulary.debug("Updated vocab entry: \(word)")
        return entry.toDTO()
    }

    func deleteEntry(by id: UUID) {
        let predicate = #Predicate<VocabularyEntry> { $0.id == id && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first else { return }
        let now = Date()
        entry.tombstone(at: now)
        for encounter in entry.encounters ?? [] {
            encounter.tombstone(at: now)
        }
        try? modelContext.save()
        Logger.vocabulary.debug("Tombstoned vocab entry: \(entry.word)")
    }

    // MARK: - Encounter Logging

    func logEncounter(
        entryId: UUID,
        source: EncounterSource,
        contextSnippet: String
    ) {
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId && $0.deletedAt == nil }
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
        // Find or create the entry. A tombstoned entry is NOT reused — see
        // `addEntry`'s comment: reviving it would be undone by the next pull.
        // Re-encountering a deleted word starts a fresh (pre-tracked) entry.
        let predicate = #Predicate<VocabularyEntry> { $0.word == word && $0.deletedAt == nil }
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

    /// Encounters for an entry. Filtered in memory as well as in the
    /// predicate: `entry.encounters` is a SwiftData *relationship*, which no
    /// `#Predicate` reaches — a tombstoned encounter would otherwise still
    /// show up in the detail sheet's history list.
    func encounters(for entryId: UUID) -> [VocabularyEncounterDTO] {
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first,
              let encounters = entry.encounters else {
            return []
        }
        return encounters
            .filter { $0.deletedAt == nil }
            .sorted { $0.timestamp > $1.timestamp }
            .map { $0.toDTO() }
    }

    // MARK: - Drill Queries

    func dueEntries(before date: Date) -> [VocabularyEntryDTO] {
        let predicate = #Predicate<VocabularyEntry> {
            $0.isInDictionary == true && $0.dueDate < date && $0.deletedAt == nil
        }
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
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryId && $0.deletedAt == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entries = try? modelContext.fetch(descriptor),
              let entry = entries.first else {
            Logger.vocabulary.error("Entry not found for grading: \(entryId)")
            return
        }

        let newState = FSRSService.schedule(state: entry.fsrsState, grade: grade, now: now)
        // Due date honours the active profile's desired retention (clamped),
        // mirroring CardModelActor.gradeCard so both FSRS surfaces schedule
        // consistently.
        let newDueDate = FSRSService.dueDate(
            for: newState,
            desiredRetention: activeDesiredRetention(),
            now: now
        )
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
            // Tombstoned encounters are excluded: this count is rendered in
            // the dictionary list, and a relationship traversal sees deleted
            // rows that no `#Predicate` filtered out.
            encounterCount: (encounters ?? []).filter { $0.deletedAt == nil }.count
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
