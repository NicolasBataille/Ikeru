import Foundation

/// Constants and XP curve calculations for the RPG progression system.
/// All functions are pure -- no side effects.
public enum RPGConstants {

    // MARK: - XP Curve

    /// Base XP required per level (multiplied by level number).
    public static let xpPerLevelBase: Int = 100

    /// Scaling factor applied to higher levels.
    /// XP required = base * level * scalingFactor^(level / 10)
    public static let scalingFactor: Double = 1.2

    /// Computes the total XP required to reach a given level from zero.
    /// - Parameter level: The target level (must be >= 1).
    /// - Returns: Total XP needed to reach this level.
    public static func totalXPForLevel(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for lvl in 1..<level {
            total += xpForLevel(lvl)
        }
        return total
    }

    /// Computes the XP required to advance from a given level to the next.
    /// - Parameter level: The current level (must be >= 1).
    /// - Returns: XP needed to go from this level to level + 1.
    public static func xpForLevel(_ level: Int) -> Int {
        guard level >= 1 else { return xpPerLevelBase }
        let scalePower = Double(level) / 10.0
        let scaled = Double(xpPerLevelBase) * Double(level) * pow(scalingFactor, scalePower)
        return Int(scaled.rounded())
    }

    // MARK: - XP Awards

    /// XP awarded for each grade.
    public static func xpForGrade(_ grade: Grade) -> Int {
        switch grade {
        case .easy: 10
        case .good: 10
        case .hard: 5
        case .again: 2
        }
    }

    // MARK: - Level Helpers

    /// Computes the level for a given total XP amount.
    /// - Parameter totalXP: Total XP accumulated.
    /// - Returns: The level the user is at.
    public static func levelForXP(_ totalXP: Int) -> Int {
        var level = 1
        var accumulated = 0
        while accumulated + xpForLevel(level) <= totalXP {
            accumulated += xpForLevel(level)
            level += 1
        }
        return level
    }

    /// Computes XP progress within the current level.
    /// - Parameter totalXP: Total XP accumulated.
    /// - Returns: A tuple of (currentXPInLevel, xpNeededForNextLevel).
    public static func progressInLevel(totalXP: Int) -> (current: Int, required: Int) {
        let level = levelForXP(totalXP)
        let xpAtLevelStart = totalXPForLevel(level)
        let currentInLevel = totalXP - xpAtLevelStart
        let requiredForNext = xpForLevel(level)
        return (current: currentInLevel, required: requiredForNext)
    }

    /// Computes the fractional progress (0.0 to 1.0) within the current level.
    /// - Parameter totalXP: Total XP accumulated.
    /// - Returns: Fraction of progress toward the next level.
    public static func progressFraction(totalXP: Int) -> Double {
        let progress = progressInLevel(totalXP: totalXP)
        guard progress.required > 0 else { return 0 }
        return min(1.0, Double(progress.current) / Double(progress.required))
    }
}
