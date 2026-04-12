import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - Sort & Filter

enum VocabSortOrder: String, CaseIterable, Identifiable {
    case mastery
    case recent
    case alphabetical
    case encounters

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mastery: "Mastery"
        case .recent: "Recent"
        case .alphabetical: "A-Z"
        case .encounters: "Encounters"
        }
    }
}

enum VocabMasteryFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case learning
    case familiar
    case mastered
    case anchored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .new: "New"
        case .learning: "Learning"
        case .familiar: "Familiar"
        case .mastered: "Mastered"
        case .anchored: "Anchored"
        }
    }

    var masteryLevel: MasteryLevel? {
        switch self {
        case .all: nil
        case .new: .new
        case .learning: .learning
        case .familiar: .familiar
        case .mastered: .mastered
        case .anchored: .anchored
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class VocabularyDictionaryViewModel {

    // MARK: - State

    private(set) var entries: [VocabularyEntryDTO] = []
    private(set) var hasLoaded = false
    private(set) var dueCount: Int = 0

    var searchText: String = ""
    var sortOrder: VocabSortOrder = .mastery
    var masteryFilter: VocabMasteryFilter = .all

    // MARK: - Computed

    var filteredEntries: [VocabularyEntryDTO] {
        var result = entries

        // Filter by mastery
        if let level = masteryFilter.masteryLevel {
            result = result.filter { $0.mastery == level }
        }

        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.word.lowercased().contains(query)
                || $0.reading.lowercased().contains(query)
                || $0.meaning.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOrder {
        case .mastery:
            result.sort { $0.mastery.rawValue < $1.mastery.rawValue }
        case .recent:
            result.sort { $0.createdAt > $1.createdAt }
        case .alphabetical:
            result.sort { $0.word < $1.word }
        case .encounters:
            result.sort { $0.encounterCount > $1.encounterCount }
        }

        return result
    }

    var totalCount: Int { entries.count }

    // MARK: - Dependencies

    private let vocabularyRepository: VocabularyRepository

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        self.vocabularyRepository = VocabularyRepository(modelContainer: modelContainer)
    }

    init(vocabularyRepository: VocabularyRepository) {
        self.vocabularyRepository = vocabularyRepository
    }

    // MARK: - Actions

    func loadData() async {
        entries = await vocabularyRepository.allEntries()
        let due = await vocabularyRepository.dueEntries(before: Date())
        dueCount = due.count
        hasLoaded = true
        Logger.vocabulary.info("Dictionary loaded: \(self.entries.count) entries, \(self.dueCount) due")
    }

    func deleteEntry(_ entry: VocabularyEntryDTO) async {
        await vocabularyRepository.deleteEntry(by: entry.id)
        entries = entries.filter { $0.id != entry.id }
    }

    func dueEntries() async -> [VocabularyEntryDTO] {
        await vocabularyRepository.dueEntries(before: Date())
    }
}
