import Foundation

public enum DisplayModeThresholdResult: Sendable, Equatable {
    case eligible
    case notEligible
}

public enum DisplayModeAdvancedThresholdMonitor {

    public static let streakThreshold = 21
    public static let reviewsThreshold = 500
    public static let masteryThreshold = 50

    /// Pure function: returns `.eligible` iff all three signals meet the
    /// inclusive thresholds.
    public static func evaluate(
        currentDailyStreak: Int,
        totalReviewsCompleted: Int,
        cardsAtFamiliarOrAbove: Int
    ) -> DisplayModeThresholdResult {
        let streakOK = currentDailyStreak >= streakThreshold
        let reviewsOK = totalReviewsCompleted >= reviewsThreshold
        let masteryOK = cardsAtFamiliarOrAbove >= masteryThreshold
        return (streakOK && reviewsOK && masteryOK) ? .eligible : .notEligible
    }
}
