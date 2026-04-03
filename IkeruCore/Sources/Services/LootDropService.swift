import Foundation
import os

/// Pure-function service for determining loot drops after learning exercises.
/// Drop probability and rarity scale with session performance and mastery.
public enum LootDropService {

    // MARK: - Drop Probability

    /// Base probability of a loot drop per exercise completion.
    static let baseDropRate: Double = 0.15

    /// Determines if a loot drop should occur after an exercise.
    /// Higher grades and longer streaks increase drop probability.
    /// - Parameters:
    ///   - grade: The grade achieved on the exercise.
    ///   - consecutiveCorrect: Number of consecutive correct answers in the session.
    ///   - randomValue: A random value (0.0 to 1.0) for testability. Pass nil for real randomness.
    /// - Returns: True if a loot drop should occur.
    public static func shouldDropLoot(
        grade: Grade,
        consecutiveCorrect: Int,
        randomValue: Double? = nil
    ) -> Bool {
        let probability = dropProbability(grade: grade, consecutiveCorrect: consecutiveCorrect)
        let roll = randomValue ?? Double.random(in: 0..<1)
        let didDrop = roll < probability
        Logger.rpg.debug("Loot drop check: prob=\(probability, format: .fixed(precision: 3)), roll=\(roll, format: .fixed(precision: 3)), drop=\(didDrop)")
        return didDrop
    }

    /// Computes the loot drop probability.
    /// - Parameters:
    ///   - grade: Exercise grade.
    ///   - consecutiveCorrect: Streak count.
    /// - Returns: Probability between 0.0 and 1.0.
    public static func dropProbability(grade: Grade, consecutiveCorrect: Int) -> Double {
        var prob = baseDropRate

        // Grade bonus
        switch grade {
        case .easy: prob += 0.10
        case .good: prob += 0.05
        case .hard: prob += 0.0
        case .again: return 0.0 // No loot on failed reviews
        }

        // Streak bonus: +2% per consecutive correct, capped at +20%
        let streakBonus = min(0.20, Double(consecutiveCorrect) * 0.02)
        prob += streakBonus

        return min(1.0, prob)
    }

    // MARK: - Drop Generation

    /// Generates a random loot item for a drop.
    /// Rarity is determined by a weighted random roll.
    /// - Parameter level: The player's current level (affects rarity weights).
    /// - Returns: A newly generated loot item.
    public static func generateDrop(level: Int) -> LootItem {
        let rarity = rollRarity(level: level)
        let template = randomTemplate(for: rarity)

        return LootItem(
            category: template.category,
            rarity: rarity,
            name: template.name,
            iconName: template.iconName
        )
    }

    // MARK: - Rarity Roll

    /// Rolls for a rarity tier based on weighted probabilities.
    /// Higher levels shift weight toward rarer tiers.
    /// - Parameter level: Current player level.
    /// - Returns: The rolled rarity tier.
    static func rollRarity(level: Int) -> LootRarity {
        // Base weights: common=60, rare=25, epic=12, legendary=3
        // Level bonus shifts weight from common to higher tiers
        let levelBonus = min(20, level)
        let commonWeight = max(30, 60 - levelBonus)
        let rareWeight = 25 + (levelBonus / 2)
        let epicWeight = 12 + (levelBonus / 3)
        let legendaryWeight = 3 + (levelBonus / 5)

        let total = commonWeight + rareWeight + epicWeight + legendaryWeight
        let roll = Int.random(in: 0..<total)

        if roll < commonWeight {
            return .common
        } else if roll < commonWeight + rareWeight {
            return .rare
        } else if roll < commonWeight + rareWeight + epicWeight {
            return .epic
        } else {
            return .legendary
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
