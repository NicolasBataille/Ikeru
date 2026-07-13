#if IKERU_DEV_TOOLS
import Foundation
import SwiftData
import IkeruCore
import os

/// Dev-only fixture seeder that builds a deterministic profile from launch arguments
/// or from the Outils développeur menu in Réglages.
///
/// Launch-args usage (Debug builds):
/// ```bash
/// xcrun simctl launch booted com.ikeru.app \
///   -mockProfile -mockLevel=15 -mockDue=25 -mockMastered=120 -mockLootboxes=3
/// ```
///
/// In-app usage (Debug + TestFlight): the `Outils développeur` section in Réglages
/// exposes the same controls (`wipeAndSeed`, `wipeAll`, `addLootbox`, `grantLevelUp`).
///
/// The whole file is gated behind `#if IKERU_DEV_TOOLS` so the App Store build,
/// which strips the flag, cannot ship fixture code. See CLAUDE.md "Removing
/// IKERU_DEV_TOOLS" for the App Store cleanup procedure.
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

    /// Total XP required to reach `level`, using the *exact* production formula
    /// from RPGConstants so the seeded profile is internally consistent.
    /// Previously this used a hand-rolled quadratic that diverged from the real
    /// curve at level ≥ 4, causing Home / Rang to display a stale seeded rank
    /// while the session summary showed the real rank derived from the XP.
    private static func xpRequired(forLevel level: Int) -> Int {
        RPGConstants.totalXPForLevel(level)
    }

    // MARK: - In-app helpers (Outils développeur menu)

    /// Wipes every persisted profile (and dependent rows) and reseeds with the
    /// given fixture parameters. Used from the Outils développeur menu so the
    /// tester can iterate through fixture variants without uninstalling the app.
    @MainActor
    public static func wipeAndSeed(
        context: ModelContext,
        profileVM: ProfileViewModel,
        level: Int,
        dueCount: Int,
        masteredCount: Int,
        lootboxCount: Int,
        inventoryCount: Int
    ) {
        wipeAll(context: context, profileVM: profileVM)

        let profile = UserProfile(displayName: "Nico")
        context.insert(profile)

        let state = seedRPGState(
            profile: profile,
            level: level,
            lootboxCount: lootboxCount,
            inventoryCount: inventoryCount
        )
        context.insert(state)
        seedCards(context: context, profile: profile, due: dueCount, mastered: masteredCount)

        do {
            try context.save()
        } catch {
            logger.error("wipeAndSeed save failed: \(error.localizedDescription)")
            return
        }

        profileVM.loadProfile()
        logger.info("wipeAndSeed: level=\(level) due=\(dueCount) mastered=\(masteredCount) loot=\(lootboxCount) inv=\(inventoryCount)")
    }

    /// Deletes every UserProfile + RPGState + Card so the next launch returns
    /// to the onboarding screen. Mirrors what `-uninstall` would do without
    /// removing the build itself.
    @MainActor
    public static func wipeAll(context: ModelContext, profileVM: ProfileViewModel) {
        let entities: [any PersistentModel.Type] = [
            UserProfile.self,
            RPGState.self,
            Card.self,
            ReviewLog.self,
            CompanionChatMessage.self,
            VocabularyEncounter.self,
            VocabularyEntry.self,
            ExerciseOutcomeLog.self,
        ]
        for entity in entities {
            do {
                try context.delete(model: entity)
            } catch {
                logger.error("wipeAll delete \(String(describing: entity)) failed: \(error.localizedDescription)")
            }
        }
        do {
            try context.save()
        } catch {
            logger.error("wipeAll save failed: \(error.localizedDescription)")
        }
        UserDefaults.standard.removeObject(forKey: ActiveProfileResolver.activeProfileIDKey)
        profileVM.loadProfile()
        logger.info("wipeAll: cleared all persisted state")
    }

    /// Appends a mock LootBox to the active profile's RPG state so a tester can
    /// open it from the Rang tab and capture the open-modal flow.
    @MainActor
    public static func addLootbox(context: ModelContext) {
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            logger.warning("addLootbox skipped — no active profile")
            return
        }
        let reward = LootItem(
            category: .scroll,
            rarity: .rare,
            name: "Outils dev — Scroll de test",
            iconName: "scroll.fill"
        )
        var boxes = state.lootBoxes
        boxes.append(LootBox(
            challengeType: .kanjiSpeed,
            requiredScore: 5,
            rewards: [reward]
        ))
        state.setLootBoxes(boxes)
        do {
            try context.save()
            logger.info("addLootbox: now \(boxes.count) box(es)")
        } catch {
            logger.error("addLootbox save failed: \(error.localizedDescription)")
        }
    }

    /// Bumps the active profile's XP past the next-level threshold so the Home
    /// banner / RPG screen can render the level-up state on the next refresh.
    @MainActor
    public static func grantLevelUp(context: ModelContext) {
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            logger.warning("grantLevelUp skipped — no active profile")
            return
        }
        let nextLevelXP = xpRequired(forLevel: state.level + 1)
        state.xp = nextLevelXP + 1
        do {
            try context.save()
            logger.info("grantLevelUp: xp set to \(state.xp), expecting level \(state.level + 1)")
        } catch {
            logger.error("grantLevelUp save failed: \(error.localizedDescription)")
        }
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

        // Due cards: reps=2 (been seen before, now overdue) so they are
        // classified as "review" items, not "new". Previously reps defaulted
        // to 0, making every due card look like a brand-new card in the
        // Home breakdown and inflating the NEW counter.
        for index in 0..<due {
            let glyph = kanjiPool[index % kanjiPool.count]
            let card = Card(
                front: glyph,
                back: "reading-\(index)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5,
                    stability: 1,
                    reps: 2,
                    lapses: 0,
                    lastReview: now.addingTimeInterval(-60 * 60 * 24 * 2)
                ),
                interval: 1,
                dueDate: now.addingTimeInterval(-Double(index) * 60)
            )
            card.profile = profile
            context.insert(card)
        }

        // Mastered cards: reps=10 and due far in the future.
        for index in 0..<mastered {
            let glyph = kanjiPool[index % kanjiPool.count]
            let card = Card(
                front: "\(glyph)\(index)",
                back: "mastered-\(index)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 4,
                    stability: 30,
                    reps: 10,
                    lapses: 0,
                    lastReview: now.addingTimeInterval(-60 * 60 * 24 * 5)
                ),
                interval: 365,
                dueDate: now.addingTimeInterval(60 * 60 * 24 * 30)
            )
            card.profile = profile
            context.insert(card)
        }
    }
}
#endif
