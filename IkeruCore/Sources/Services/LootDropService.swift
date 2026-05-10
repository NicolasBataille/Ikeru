import Foundation
import os

/// Pure-function service for determining loot drops after learning exercises.
/// Drop probability and rarity scale with session performance and mastery.
public enum LootDropService {

    // MARK: - Drop Probability

    /// Base probability of a loot drop per exercise completion.
    /// Nerfed from 0.15 → 0.05: loot is a rare punctuation, not an expected tax refund.
    static let baseDropRate: Double = 0.05

    /// Maximum drops allowed per session (session-cap guard).
    public static let sessionDropCap: Int = 1

    /// Number of consecutive empty sessions before a pity drop is forced.
    public static let pityThreshold: Int = 5

    /// Determines if a loot drop should occur after an exercise.
    /// - Parameters:
    ///   - grade: The grade achieved on the exercise.
    ///   - sessionLootCount: Number of drops already received this session.
    ///   - randomValue: A random value (0.0 to 1.0) for testability. Pass nil for real randomness.
    /// - Returns: True if a loot drop should occur.
    public static func shouldDropLoot(
        grade: Grade,
        sessionLootCount: Int,
        randomValue: Double? = nil
    ) -> Bool {
        if sessionLootCount >= sessionDropCap { return false }
        let probability = dropProbability(grade: grade)
        let roll = randomValue ?? Double.random(in: 0..<1)
        let didDrop = roll < probability
        Logger.rpg.debug("Loot drop check: prob=\(probability, format: .fixed(precision: 3)), roll=\(roll, format: .fixed(precision: 3)), drop=\(didDrop)")
        return didDrop
    }

    /// Computes the loot drop probability.
    /// Streak bonus removed — loot rewards presence, not grind.
    /// - Parameter grade: Exercise grade.
    /// - Returns: Probability between 0.0 and 1.0.
    public static func dropProbability(grade: Grade) -> Double {
        var prob = baseDropRate
        switch grade {
        case .easy: prob += 0.03
        case .good: prob += 0.01
        case .hard: prob += 0.0
        case .again: return 0.0
        }
        return min(1.0, prob)
    }

    /// Whether a pity drop must be forced on session end.
    /// Intended to be called after a session finished without a drop.
    /// - Parameter sessionsSinceLastDrop: Count of consecutive sessions ending with no drop,
    ///   including the session that just finished.
    public static func shouldForcePityDrop(sessionsSinceLastDrop: Int) -> Bool {
        sessionsSinceLastDrop >= pityThreshold
    }

    // MARK: - Drop Generation

    /// Generates a random loot item for a drop.
    /// RNG drops now cap at Rare — Epic and Legendary are reserved for mastery
    /// events (see `MasteryEventDetector`). This keeps random drops feeling
    /// like small gifts while concentrating celebration on earned milestones.
    /// - Parameter level: The player's current level (affects common/rare split).
    /// - Returns: A newly generated loot item at common or rare.
    public static func generateDrop(level: Int) -> LootItem {
        let rarity = rollRNGRarity(level: level)
        let template = randomTemplate(for: rarity)

        return LootItem(
            category: template.category,
            rarity: rarity,
            name: template.name,
            iconName: template.iconName
        )
    }

    // MARK: - Rarity Roll

    /// Rolls for RNG rarity — capped at Rare.
    /// Higher levels shift weight toward Rare.
    /// - Parameter level: Current player level.
    /// - Returns: common or rare.
    static func rollRNGRarity(level: Int) -> LootRarity {
        let levelBonus = min(20, level)
        let commonWeight = max(55, 80 - levelBonus)
        let rareWeight = 20 + levelBonus

        let total = commonWeight + rareWeight
        let roll = Int.random(in: 0..<total)
        return roll < commonWeight ? .common : .rare
    }

    // MARK: - Mastery Drops

    /// Generates a loot item awarded for a specific mastery event, with
    /// rarity scaled to the learner's current JLPT level via
    /// `BadgeRamping`. A "Burned" event for an N5 beginner is rare; the
    /// same event for an N1 veteran is legendary. The semantic name and
    /// iconography (e.g. "Burned In" / `flame.fill`) stay constant across
    /// levels — only the rarity tier ramps.
    /// - Parameters:
    ///   - event: The mastery milestone that triggered this drop.
    ///   - learnerLevel: The learner's current JLPT level (driven by the
    ///     active session's snapshot, not the per-card level).
    /// - Returns: A LootItem at the ramped rarity with a themed name.
    public static func generateMasteryDrop(
        for event: MasteryEvent,
        learnerLevel: JLPTLevel
    ) -> LootItem {
        let template = masteryTemplate(for: event)
        return LootItem(
            category: template.category,
            rarity: BadgeRamping.rarity(for: event, learnerLevel: learnerLevel),
            name: template.name,
            iconName: template.iconName
        )
    }

    /// Legacy overload retained as a thin shim so any in-flight callers
    /// compile while migrating. Delegates with `learnerLevel: .n5`, which
    /// matches the floor of `BadgeRamping`'s table — equivalent to the
    /// pre-ramping behavior for an N5 learner. New callers MUST use the
    /// `learnerLevel:` overload so rarity scales with the player.
    @available(
        *,
        deprecated,
        message: "Use generateMasteryDrop(for:learnerLevel:) so rarity ramps with the learner's level."
    )
    public static func generateMasteryDrop(for event: MasteryEvent) -> LootItem {
        generateMasteryDrop(for: event, learnerLevel: .n5)
    }

    private static func masteryTemplate(for event: MasteryEvent) -> LootTemplate {
        switch event {
        case .graduation:
            return LootTemplate(category: .badge, name: "First Steps", iconName: "leaf.fill")
        case .leechRecovered:
            return LootTemplate(category: .scroll, name: "Persistence Scroll", iconName: "scroll.fill")
        case .longIntervalRecall:
            return LootTemplate(category: .badge, name: "Lasting Memory", iconName: "brain.head.profile")
        case .burned:
            return LootTemplate(category: .title, name: "Burned In", iconName: "flame.fill")
        }
    }

    // MARK: - Loot Templates

    private struct LootTemplate {
        let category: LootItem.Category
        let name: String
        let iconName: String
    }

    private static func randomTemplate(for rarity: LootRarity) -> LootTemplate {
        let templates: [LootTemplate]
        switch rarity {
        case .common:
            templates = [
                LootTemplate(category: .badge, name: "Kana Shard", iconName: "hexagon.fill"),
                LootTemplate(category: .scroll, name: "Study Note", iconName: "note.text"),
                LootTemplate(category: .badge, name: "Practice Token", iconName: "circle.fill"),
                LootTemplate(category: .theme, name: "Ink Wash", iconName: "paintbrush.fill"),
            ]
        case .uncommon:
            templates = [
                LootTemplate(category: .badge, name: "Bamboo Sprig", iconName: "leaf.fill"),
                LootTemplate(category: .scroll, name: "Practice Sutra", iconName: "scroll.fill"),
                LootTemplate(category: .badge, name: "Tea Cup", iconName: "cup.and.saucer.fill"),
                LootTemplate(category: .theme, name: "Misty Morning", iconName: "cloud.fill"),
            ]
        case .rare:
            templates = [
                LootTemplate(category: .badge, name: "Kanji Crystal", iconName: "diamond.fill"),
                LootTemplate(category: .scroll, name: "Proverb Scroll", iconName: "scroll.fill"),
                LootTemplate(category: .title, name: "Eager Learner", iconName: "textformat"),
                LootTemplate(category: .theme, name: "Cherry Blossom", iconName: "leaf.fill"),
            ]
        case .epic:
            templates = [
                LootTemplate(category: .badge, name: "Dragon Scale", iconName: "shield.lefthalf.filled"),
                LootTemplate(category: .scroll, name: "Ancient Wisdom", iconName: "scroll.fill"),
                LootTemplate(category: .title, name: "Kanji Sage", iconName: "textformat"),
                LootTemplate(category: .theme, name: "Mountain Temple", iconName: "mountain.2.fill"),
            ]
        case .legendary:
            templates = [
                LootTemplate(category: .badge, name: "Phoenix Feather", iconName: "flame.fill"),
                LootTemplate(category: .scroll, name: "Master's Teaching", iconName: "scroll.fill"),
                LootTemplate(category: .title, name: "Language Master", iconName: "crown.fill"),
                LootTemplate(category: .badge, name: "Golden Calligraphy", iconName: "pencil.and.outline"),
            ]
        }

        guard let template = templates.randomElement() else {
            return LootTemplate(category: .badge, name: "Mystery Shard", iconName: "questionmark.circle.fill")
        }
        return template
    }
}
