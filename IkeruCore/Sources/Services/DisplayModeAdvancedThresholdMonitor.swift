import Foundation

public enum DisplayModeThresholdResult: Sendable, Equatable {
    case eligible
    case notEligible
}

public enum DisplayModeAdvancedThresholdMonitor {

    /// Minimum cumulative reviews to unlock the advanced Tatami mode suggestion.
    /// Raised from 500 to 750 after removing the streak gate, so that
    /// competence-only criteria remain meaningful without daily-login pressure.
    public static let reviewsThreshold = 750

    /// Minimum number of cards at Familiar-or-above mastery level.
    /// Raised from 50 to 75 for the same reason as reviewsThreshold.
    public static let masteryThreshold = 75

    /// Pure function: returns `.eligible` iff both cumulative-competence signals
    /// meet their inclusive thresholds.
    ///
    /// The daily-streak criterion was intentionally removed: the product rejects
    /// streak-based pressure ("no streaks, no daily-login pressure"). Eligibility
    /// is now determined solely by the total volume of work done (reviews) and
    /// the depth of knowledge acquired (mastery), neither of which imposes any
    /// time-based obligation.
    public static func evaluate(
        totalReviewsCompleted: Int,
        cardsAtFamiliarOrAbove: Int
    ) -> DisplayModeThresholdResult {
        let reviewsOK = totalReviewsCompleted >= reviewsThreshold
        let masteryOK = cardsAtFamiliarOrAbove >= masteryThreshold
        return (reviewsOK && masteryOK) ? .eligible : .notEligible
    }
}
