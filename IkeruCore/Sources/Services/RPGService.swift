import Foundation
import os

/// Pure-function RPG progression service.
/// Computes XP awards and level-up detection.
///
/// All functions are static and pure -- no side effects, no database access.
/// Takes RPGState + Grade, returns updated values.
public enum RPGService {

    // MARK: - XP Award

    /// Awards XP for a card review grade and returns the updated state values.
    ///
    /// This is a pure function -- no side effects, no database access.
    /// - Parameters:
    ///   - grade: The grade given by the learner.
    ///   - currentXP: Current total XP.
    ///   - currentLevel: Current level.
    ///   - totalReviews: Current total reviews completed.
    /// - Returns: A tuple with updated (xp, level, totalReviews, didLevelUp, xpAwarded).
    public static func awardXP(
        grade: Grade,
        currentXP: Int,
        currentLevel: Int,
        totalReviews: Int
    ) -> XPAwardResult {
        let xpAmount = RPGConstants.xpForGrade(grade)
        let newXP = currentXP + xpAmount
        let newLevel = RPGConstants.levelForXP(newXP)
        let didLevelUp = newLevel > currentLevel

        Logger.rpg.debug(
            "XP awarded: +\(xpAmount) (grade=\(grade.rawValue)), total=\(newXP), level=\(newLevel)"
        )

        if didLevelUp {
            Logger.rpg.info("Level up! \(currentLevel) → \(newLevel)")
        }

        return XPAwardResult(
            newXP: newXP,
            newLevel: newLevel,
            newTotalReviews: totalReviews + 1,
            didLevelUp: didLevelUp,
            xpAwarded: xpAmount
        )
    }

    /// Checks whether the current XP puts the user within 10% of the next level threshold.
    /// Used for the pulse glow effect on the XP bar.
    /// - Parameter totalXP: Total XP accumulated.
    /// - Returns: True if within 10% of level-up.
    public static func isNearLevelUp(totalXP: Int) -> Bool {
        let fraction = RPGConstants.progressFraction(totalXP: totalXP)
        return fraction >= 0.9
    }
}

// MARK: - XP Award Result

/// Immutable result of an XP award calculation.
public struct XPAwardResult: Sendable, Equatable {

    /// Updated total XP.
    public let newXP: Int

    /// Updated level.
    public let newLevel: Int

    /// Updated total reviews count.
    public let newTotalReviews: Int

    /// Whether this award triggered a level-up.
    public let didLevelUp: Bool

    /// Amount of XP that was awarded.
    public let xpAwarded: Int
}
