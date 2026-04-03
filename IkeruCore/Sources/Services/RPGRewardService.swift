import Foundation
import os

/// Pure-function service for RPG attribute unlocks and level rewards.
/// Determines which attributes/rewards unlock at level thresholds.
/// Maps RPG progression to real skill mastery, not engagement.
public enum RPGRewardService {

    // MARK: - Attribute Unlocks

    /// Returns attributes that should be unlocked at the given level.
    /// Compares against currently unlocked attributes to find new ones.
    /// - Parameters:
    ///   - level: The player's current level.
    ///   - currentAttributes: Already unlocked attributes.
    /// - Returns: Newly unlocked attributes (not previously in the list).
    public static func newlyUnlockedAttributes(
        atLevel level: Int,
        currentAttributes: [RPGAttribute]
    ) -> [RPGAttribute] {
        let currentIDs = Set(currentAttributes.map(\.id))
        return RPGAttribute.allPredefined.filter { attribute in
            attribute.unlockLevel <= level && !currentIDs.contains(attribute.id)
        }
    }

    /// Returns all attributes that should be unlocked at the given level,
    /// initialized with default values.
    /// - Parameter level: The player's current level.
    /// - Returns: All predefined attributes whose unlockLevel <= level.
    public static func unlockedAttributes(atLevel level: Int) -> [RPGAttribute] {
        RPGAttribute.allPredefined.filter { $0.unlockLevel <= level }
    }

    // MARK: - Level Rewards

    /// Determines the loot reward for reaching a specific level.
    /// Higher levels yield rarer rewards.
    /// - Parameter level: The level just reached.
    /// - Returns: A loot item reward for the level milestone, or nil for non-milestone levels.
    public static func levelReward(forLevel level: Int) -> LootItem? {
        guard let milestone = LevelMilestone.forLevel(level) else { return nil }

        return LootItem(
            category: milestone.rewardCategory,
            rarity: milestone.rewardRarity,
            name: milestone.rewardName,
            iconName: milestone.rewardIcon
        )
    }

    // MARK: - Attribute Value Updates

    /// Computes updated attribute values based on skill-specific review performance.
    /// Attributes grow based on actual mastery metrics, not just activity.
    /// - Parameters:
    ///   - attributes: Current attribute state.
    ///   - skillID: The skill dimension that was exercised (e.g., "reading", "listening").
    ///   - successRate: Fraction of correct answers (0.0 to 1.0).
    /// - Returns: Updated attributes with the relevant skill's value increased.
    public static func updateAttributeValues(
        attributes: [RPGAttribute],
        skillID: String,
        successRate: Double
    ) -> [RPGAttribute] {
        attributes.map { attribute in
            guard attribute.id == skillID else { return attribute }
            // Only grow from good performance (>60% success)
            let growth = successRate > 0.6 ? Int((successRate * 3).rounded()) : 0
            let newValue = min(100, attribute.value + growth)
            return attribute.withValue(newValue)
        }
    }
}

// MARK: - Level Milestones

extension RPGRewardService {

    /// Defines reward milestones at specific levels.
    enum LevelMilestone {
        case beginner       // Level 2
        case apprentice     // Level 5
        case student        // Level 10
        case scholar        // Level 15
        case adept          // Level 20
        case master         // Level 30
        case sage           // Level 50

        var rewardRarity: LootRarity {
            switch self {
            case .beginner: .common
            case .apprentice: .common
            case .student: .rare
            case .scholar: .rare
            case .adept: .epic
            case .master: .epic
            case .sage: .legendary
            }
        }

        var rewardCategory: LootItem.Category {
            switch self {
            case .beginner: .badge
            case .apprentice: .title
            case .student: .badge
            case .scholar: .scroll
            case .adept: .badge
            case .master: .title
            case .sage: .badge
            }
        }

        var rewardName: String {
            switch self {
            case .beginner: "First Steps"
            case .apprentice: "Apprentice"
            case .student: "Dedicated Student"
            case .scholar: "Wisdom of the Ancients"
            case .adept: "Adept Linguist"
            case .master: "Master"
            case .sage: "Sage of Languages"
            }
        }

        var rewardIcon: String {
            switch self {
            case .beginner: "figure.walk"
            case .apprentice: "graduationcap.fill"
            case .student: "medal.fill"
            case .scholar: "scroll.fill"
            case .adept: "star.circle.fill"
            case .master: "crown.fill"
            case .sage: "sparkles"
            }
        }

        static func forLevel(_ level: Int) -> LevelMilestone? {
            switch level {
            case 2: .beginner
            case 5: .apprentice
            case 10: .student
            case 15: .scholar
            case 20: .adept
            case 30: .master
            case 50: .sage
            default: nil
            }
        }
    }
}
