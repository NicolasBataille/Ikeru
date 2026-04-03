import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - RPGProfileViewModel

@MainActor
@Observable
final class RPGProfileViewModel {

    // MARK: - Exposed State

    /// Current RPG level.
    private(set) var level: Int = 1

    /// Total XP earned.
    private(set) var xp: Int = 0

    /// Total reviews completed.
    private(set) var totalReviews: Int = 0

    /// Unlocked RPG attributes.
    private(set) var attributes: [RPGAttribute] = []

    /// Loot inventory items.
    private(set) var inventory: [LootItem] = []

    /// Unopened lootboxes available for challenge.
    private(set) var unopenedLootBoxes: [LootBox] = []

    /// Whether data has been loaded.
    private(set) var hasLoaded: Bool = false

    // MARK: - Computed

    /// XP progress fraction in current level (0.0 to 1.0).
    var progressFraction: Double {
        RPGConstants.progressFraction(totalXP: xp)
    }

    /// XP progress within current level.
    var progressInLevel: (current: Int, required: Int) {
        RPGConstants.progressInLevel(totalXP: xp)
    }

    /// Whether near level-up (triggers pulse effect).
    var isNearLevelUp: Bool {
        RPGService.isNearLevelUp(totalXP: xp)
    }

    /// Inventory grouped by rarity, sorted by rarest first.
    var inventoryByRarity: [(rarity: LootRarity, items: [LootItem])] {
        let grouped = Dictionary(grouping: inventory, by: \.rarity)
        return LootRarity.allCases.reversed().compactMap { rarity in
            guard let items = grouped[rarity], !items.isEmpty else { return nil }
            return (rarity: rarity, items: items)
        }
    }

    /// Attributes that are unlocked (have unlockLevel <= current level).
    var unlockedAttributes: [RPGAttribute] {
        attributes.filter { $0.unlockLevel <= level }
    }

    /// Attributes not yet unlocked.
    var lockedAttributes: [RPGAttribute] {
        RPGAttribute.allPredefined.filter { predefined in
            predefined.unlockLevel > level
        }
    }

    // MARK: - Dependencies

    private let modelContainer: ModelContainer

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Data Loading

    func loadData() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        let results = (try? context.fetch(descriptor)) ?? []

        if let state = results.first {
            level = state.level
            xp = state.xp
            totalReviews = state.totalReviewsCompleted
            attributes = state.attributes
            inventory = state.lootInventory
            unopenedLootBoxes = state.unopenedLootBoxes

            // Auto-sync newly unlocked attributes
            let newAttrs = RPGRewardService.newlyUnlockedAttributes(
                atLevel: level,
                currentAttributes: attributes
            )
            if !newAttrs.isEmpty {
                let updated = attributes + newAttrs
                state.setAttributes(updated)
                attributes = updated
                try? context.save()
                Logger.rpg.info("Auto-unlocked \(newAttrs.count) new attributes at level \(self.level)")
            }
        }

        hasLoaded = true
        Logger.ui.debug("RPG profile loaded: level=\(self.level), xp=\(self.xp), attrs=\(self.attributes.count), items=\(self.inventory.count)")
    }
}
