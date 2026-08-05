import Foundation
import os

/// Pure-function service for RPG attribute unlocks and attribute-value growth.
/// Determines which attributes unlock at level thresholds.
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
