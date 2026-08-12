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
    private static let legacyExtendedGroupsMigratedKey = "ikeru.kana.migratedLegacyExtendedGroupsV1"

    // MARK: Init

    public init(repository: KanaCardRepository) {
        self.repository = repository
        Self.migrateLegacyExtendedSelectionIfNeeded()
        self.selectedGroups = Self.loadPersistedSelection() ?? [.hVowels]
    }

    // MARK: Loading

    public func loadMasteries() async {
        // Guard against concurrent re-entry: `seed` reads the existing fronts
        // and then inserts whatever is missing, so two overlapping runs would
        // each see a partial store and both insert — creating duplicate cards
        // (which later trap `mastery(for:)`'s unique-keyed Dictionary).
        if case .loading = loadingState { return }
        loadingState = .loading
        // Seed ONLY the currently-selected groups, not all 92 kana. Opening the
        // grid no longer materialises the entire katakana set as immediately-due
        // cards — that was the source of katakana leaking into Home Practice.
        // Un-selected groups still render (0%) from KanaGroup metadata.
        //
        // And only seed at all once the learner has actually confirmed a study
        // set: a fresh user peeking at the chooser (then backing out) must not
        // create cards — those phantom cards flipped Home's `hasKanaCards`
        // check and silently dismissed the "choose your kana" gate. Before the
        // first confirmation, mastery renders 0% from metadata, which is
        // exactly right; real seeding happens in `confirmStudySet()` and when
        // launching a drill (`cards(for:)`).
        if StudySetStore.hasChosenStudySet {
            await repository.seed(groups: selectedGroups)
        }
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
        // Make sure the currently-selected groups have backing cards before we
        // query them — a group the user just selected may not have been seeded
        // yet (seeding is selection-scoped, not bulk).
        await repository.seed(groups: selectedGroups)
        switch mode {
        case .dueReview:
            return await repository.dueCardsForGroups(selectedGroups, now: Date())
        case .freePractice:
            return await repository.cardsForGroups(selectedGroups)
        case .weakReinforcement:
            return await repository.weakCardsForGroups(selectedGroups)
        }
    }

    /// Confirm the current selection as the learner's study set: persist it
    /// (already done via `selectedGroups.didSet`), seed its cards, and mark the
    /// choice so Home stops showing the "choose your kana" gate. Used by the
    /// first-run chooser presented from Home.
    public func confirmStudySet() async {
        await repository.seed(groups: selectedGroups)
        StudySetStore.markChosen()
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

    /// One-time migration for testers who checked a dakuten/yōon group back
    /// when those groups were scaffolded with an empty character table: the
    /// selection persisted, but it cost nothing and displayed nothing. Now
    /// that the table is populated (see `KanaGroup`), leaving a stale
    /// selection in place would silently seed up to 116 kana cards — all due
    /// at once — the next time `loadMasteries()` runs. Strip any non-`.base`
    /// group from a selection that predates this migration so existing
    /// installs don't wake up to an avalanche they never knowingly chose.
    /// Runs once (gated by `legacyExtendedGroupsMigratedKey`): a group picked
    /// AFTER this migration is a deliberate choice and is left alone.
    private static func migrateLegacyExtendedSelectionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyExtendedGroupsMigratedKey) else { return }
        defer { defaults.set(true, forKey: legacyExtendedGroupsMigratedKey) }

        guard let persisted = loadPersistedSelection() else { return }
        let baseOnly = persisted.filter { $0.section == .base }
        guard baseOnly != persisted else { return }
        // A selection that was entirely non-base groups is not a real study
        // set (nothing would have rendered pre-fix either) — fall back to the
        // same default a fresh install gets, rather than persisting an empty
        // selection that would silently leave the learner with zero cards.
        let migrated = baseOnly.isEmpty ? [.hVowels] : baseOnly

        do {
            let data = try JSONEncoder().encode(migrated)
            defaults.set(data, forKey: storageKey)
            Logger.content.info(
                "KanaPool: migrated legacy selection, dropped \(persisted.count - baseOnly.count) non-base group(s)"
            )
        } catch {
            Logger.content.error("KanaPool: failed to persist migrated selection: \(error.localizedDescription)")
        }
    }
}

// MARK: - StudySetStore

/// Tiny persistence facade over the learner's chosen kana study set. It shares
/// the `KanaPoolViewModel` selection key (so the pool selector and the Home
/// gate are one source of truth) and adds a "has chosen" flag that Home reads
/// to decide whether to invite the learner to pick their kana before practising.
///
/// Lives here (rather than in its own file) because the app target is
/// non-synchronised — folding it into an existing source file avoids a
/// project.pbxproj edit. It is intentionally global/single-user, matching the
/// existing selection persistence.
enum StudySetStore {
    private static let groupsKey = "ikeru.kana.selectedGroups"        // shared with KanaPoolViewModel
    private static let chosenKey = "ikeru.kana.hasChosenStudySet"

    /// Whether the learner has explicitly confirmed a study set at least once.
    static var hasChosenStudySet: Bool {
        UserDefaults.standard.bool(forKey: chosenKey)
    }

    /// The chosen kana groups (decoded from the shared selection key).
    static var chosenGroups: Set<KanaGroup> {
        guard let data = UserDefaults.standard.data(forKey: groupsKey) else { return [] }
        return (try? JSONDecoder().decode(Set<KanaGroup>.self, from: data)) ?? []
    }

    /// Mark that the learner has made an explicit study-set choice.
    static func markChosen() {
        UserDefaults.standard.set(true, forKey: chosenKey)
    }
}
