#if DEBUG
import Foundation
import SwiftData
import IkeruCore
import os

/// Dev-only fixture seeder that builds a deterministic profile from launch arguments.
///
/// Usage from the simulator:
/// ```bash
/// xcrun simctl launch booted com.ikeru.app \
///   -mockProfile -mockLevel=15 -mockDue=25 -mockMastered=120 -mockLootboxes=3
/// ```
///
/// All seeding happens **only when no profile already exists**, so a manual tester
/// can switch between mock and real flows by uninstalling the app.
///
/// The whole file is gated behind `#if DEBUG` so the App Store build cannot ship
/// fixture code or unused launch arguments.
public enum TestFixtures {

    private static let logger = Logger(subsystem: "com.ikeru.app", category: "TestFixtures")

    /// Seeds a fixture profile if `-mockProfile` is present and no profile exists yet.
    /// Returns `true` if a profile was created.
    @MainActor
    @discardableResult
    public static func seedIfRequested(
        context: ModelContext,
        profileVM: ProfileViewModel
    ) -> Bool {
        guard AppEnvironment.hasFlag("mockProfile") else { return false }
        guard !profileVM.hasProfile else {
            logger.info("Skipping fixture seed — profile already exists")
            return false
        }

        let level = AppEnvironment.intArg("mockLevel") ?? 5
        let dueCount = AppEnvironment.intArg("mockDue") ?? 12
        let masteredCount = AppEnvironment.intArg("mockMastered") ?? 40
        let lootboxCount = AppEnvironment.intArg("mockLootboxes") ?? 1
        let inventoryCount = AppEnvironment.intArg("mockInventory") ?? 4

        logger.info("Seeding fixture profile: level=\(level) due=\(dueCount) mastered=\(masteredCount) lootboxes=\(lootboxCount) inventory=\(inventoryCount)")

        let profile = UserProfile(displayName: "Nico")
        context.insert(profile)

        let state = seedRPGState(profile: profile, level: level, lootboxCount: lootboxCount, inventoryCount: inventoryCount)
        context.insert(state)
        seedCards(context: context, profile: profile, due: dueCount, mastered: masteredCount)

        do {
            try context.save()
        } catch {
            logger.error("Failed to save fixture profile: \(error.localizedDescription)")
            return false
        }

        profileVM.loadProfile()
        return true
    }

    // MARK: - RPG seeding

    @discardableResult
    private static func seedRPGState(
        profile: UserProfile,
        level: Int,
        lootboxCount: Int,
        inventoryCount: Int
    ) -> RPGState {
        let xpForLevel = xpRequired(forLevel: level)
        let xpForNext = xpRequired(forLevel: level + 1)
        let midXP = xpForLevel + (xpForNext - xpForLevel) / 2

        let state = RPGState(xp: midXP, level: level, totalReviewsCompleted: level * 25)
        state.totalSessionsCompleted = max(1, level / 2)

        // Attributes scaled to level
        let scaled = RPGAttribute.allPredefined.map { attr in
            guard attr.unlockLevel <= level else { return attr }
            let value = min(100, max(5, level * 5))
            return attr.withValue(value)
        }
        state.setAttributes(scaled)

        // Inventory
        if inventoryCount > 0 {
            let rarities: [LootRarity] = [.common, .rare, .epic, .legendary]
            let categories: [LootItem.Category] = [.theme, .title, .badge, .scroll]
            let items = (0..<inventoryCount).map { idx -> LootItem in
                let rarity = rarities[idx % rarities.count]
                let category = categories[idx % categories.count]
                return LootItem(
                    category: category,
                    rarity: rarity,
                    name: "\(rarity.rawValue.capitalized) \(category.displayName)",
                    iconName: category.iconName
                )
            }
            state.setLootInventory(items)
        }

        // Lootboxes
        if lootboxCount > 0 {
            let placeholderReward = LootItem(
                category: .scroll,
                rarity: .rare,
                name: "Mystery Scroll",
                iconName: "scroll.fill"
            )
            let boxes = (0..<lootboxCount).map { _ in
                LootBox(
                    challengeType: .kanjiSpeed,
                    requiredScore: 5,
                    rewards: [placeholderReward]
                )
            }
            state.setLootBoxes(boxes)
        }

        state.profile = profile
        profile.rpgState = state
        return state
    }

    /// XP curve mirrors the production formula closely enough for visual smoke tests.
    /// 102, 230, 384, ... — quadratic-ish growth.
    private static func xpRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1...(level - 1)).reduce(0) { acc, lv in acc + 100 + lv * 2 }
    }

    // MARK: - Card seeding

    private static func seedCards(
        context: ModelContext,
        profile: UserProfile,
        due: Int,
        mastered: Int
    ) {
        let now = Date()
        let kanjiPool = ["人", "日", "月", "火", "水", "木", "金", "土", "山", "川",
                         "口", "目", "耳", "手", "足", "心", "本", "車", "雨", "電"]

        for index in 0..<due {
            let glyph = kanjiPool[index % kanjiPool.count]
            let card = Card(
                front: glyph,
                back: "reading-\(index)",
                type: .kanji,
                interval: 1,
                dueDate: now.addingTimeInterval(-Double(index) * 60)
            )
            card.profile = profile
            context.insert(card)
        }

        for index in 0..<mastered {
            let glyph = kanjiPool[index % kanjiPool.count]
            let card = Card(
                front: "\(glyph)\(index)",
                back: "mastered-\(index)",
                type: .kanji,
                interval: 365,
                dueDate: now.addingTimeInterval(60 * 60 * 24 * 30)
            )
            card.profile = profile
            context.insert(card)
        }
    }
}
#endif
