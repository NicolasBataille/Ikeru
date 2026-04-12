import Foundation
import IkeruCore
import os

// MARK: - KanaPreset

/// Predefined selections for quick pool configuration.
public enum KanaPreset: String, CaseIterable, Sendable, Identifiable {
    case hiraganaBase
    case hiraganaAll
    case katakanaBase
    case katakanaAll
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hiraganaBase: return "Hiragana basics"
        case .hiraganaAll:  return "Hiragana full"
        case .katakanaBase: return "Katakana basics"
        case .katakanaAll:  return "Katakana full"
        case .all:          return "All"
        }
    }

    public var groups: Set<KanaGroup> {
        switch self {
        case .hiraganaBase:
            return Set(KanaGroup.allCases.filter { $0.script == .hiragana && $0.section == .base })
        case .hiraganaAll:
            return Set(KanaGroup.allCases.filter { $0.script == .hiragana })
        case .katakanaBase:
            return Set(KanaGroup.allCases.filter { $0.script == .katakana && $0.section == .base })
        case .katakanaAll:
            return Set(KanaGroup.allCases.filter { $0.script == .katakana })
        case .all:
            return Set(KanaGroup.allCases)
        }
    }
}

// MARK: - KanaDrillMode

/// Drill modes launched from the pool selector. Crew C implements the actual views.
public enum KanaDrillMode: String, Sendable {
    case dueReview
    case freePractice
    case weakReinforcement

    public var displayName: String {
        switch self {
        case .dueReview:         return "Review Due"
        case .freePractice:      return "Free Practice"
        case .weakReinforcement: return "Weak Spots"
        }
    }
}

// MARK: - KanaPoolViewModel

@MainActor
@Observable
public final class KanaPoolViewModel {

    // MARK: State

    public var selectedGroups: Set<KanaGroup> {
        didSet { persistSelection() }
    }

    public private(set) var masteries: [KanaGroup: GroupMastery] = [:]
    /// Per-character mastery level, keyed by the kana character itself.
    public private(set) var characterMastery: [String: MasteryLevel] = [:]
    public private(set) var loadingState: LoadingState<Void> = .idle

    // MARK: Dependencies

    private let repository: KanaCardRepository

    // MARK: Persistence

    private static let storageKey = "ikeru.kana.selectedGroups"

    // MARK: Init

    public init(repository: KanaCardRepository) {
        self.repository = repository
        self.selectedGroups = Self.loadPersistedSelection() ?? [.hVowels]
    }

    // MARK: Loading

    public func loadMasteries() async {
        loadingState = .loading
        await repository.seedIfNeeded()
        let allGroups = Set(KanaGroup.allCases)
        let result = await repository.mastery(for: allGroups)
        let allCards = await repository.cardsForGroups(allGroups)
        var charMap: [String: MasteryLevel] = [:]
        for card in allCards {
            charMap[card.front] = card.masteryLevel
        }
        masteries = result
        characterMastery = charMap
        loadingState = .loaded(())
        Logger.content.info("KanaPool: loaded mastery for \(result.count) groups")
    }

    // MARK: Selection

    public func toggleGroup(_ group: KanaGroup) {
        var next = selectedGroups
        if next.contains(group) {
            next.remove(group)
        } else {
            next.insert(group)
        }
        selectedGroups = next
    }

    public func toggleAllInSection(_ section: KanaSection, script: KanaScript) {
        let groups = KanaGroup.allCases.filter { $0.section == section && $0.script == script }
        let groupSet = Set(groups)
        let allSelected = groupSet.isSubset(of: selectedGroups)
        var next = selectedGroups
        if allSelected {
            next.subtract(groupSet)
        } else {
            next.formUnion(groupSet)
        }
        selectedGroups = next
    }

    public func isSectionFullySelected(_ section: KanaSection, script: KanaScript) -> Bool {
        let groups = KanaGroup.allCases.filter { $0.section == section && $0.script == script }
        guard !groups.isEmpty else { return false }
        return Set(groups).isSubset(of: selectedGroups)
    }

    public func applyPreset(_ preset: KanaPreset) {
        selectedGroups = preset.groups
    }

    public func clearSelection() {
        selectedGroups = []
    }

    public var selectedCharacterCount: Int {
        selectedGroups.reduce(0) { $0 + $1.characters.count }
    }

    // MARK: Fetching cards for drill modes

    public func cards(for mode: KanaDrillMode) async -> [CardDTO] {
        switch mode {
        case .dueReview:
            return await repository.dueCardsForGroups(selectedGroups, now: Date())
        case .freePractice:
            return await repository.cardsForGroups(selectedGroups)
        case .weakReinforcement:
            return await repository.weakCardsForGroups(selectedGroups)
        }
    }

    // MARK: Persistence helpers

    private func persistSelection() {
        do {
            let data = try JSONEncoder().encode(selectedGroups)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Logger.content.error("KanaPool: failed to persist selection: \(error.localizedDescription)")
        }
    }

    private static func loadPersistedSelection() -> Set<KanaGroup>? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Set<KanaGroup>.self, from: data)
    }
}
