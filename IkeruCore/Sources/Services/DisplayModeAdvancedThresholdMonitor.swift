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

    /// Minimum number of distinct calendar days with at least one completed
    /// session, counted lifetime (not consecutive — this is deliberately not
    /// a streak). Restores the spec's `OR active days ≥ 30` eligibility path
    /// alongside the competence path, so a learner who studies steadily but
    /// irregularly (breaking their streak) isn't penalized relative to one
    /// who happens to hit the reviews/mastery thresholds sooner.
    public static let activeDaysThreshold = 30

    /// Pure function: returns `.eligible` iff either
    /// - both cumulative-competence signals (reviews, mastery) meet their
    ///   inclusive thresholds, **or**
    /// - the learner has been active on at least `activeDaysThreshold`
    ///   distinct calendar days.
    ///
    /// The daily-streak criterion remains intentionally excluded: the product
    /// rejects streak-based pressure ("no streaks, no daily-login pressure").
    /// `activeDaysCount` counts lifetime distinct active days, not a
    /// consecutive streak, so it doesn't reintroduce that pressure — a gap
    /// doesn't reset progress toward this path.
    public static func evaluate(
        totalReviewsCompleted: Int,
        cardsAtFamiliarOrAbove: Int,
        activeDaysCount: Int
    ) -> DisplayModeThresholdResult {
        let reviewsOK = totalReviewsCompleted >= reviewsThreshold
        let masteryOK = cardsAtFamiliarOrAbove >= masteryThreshold
        let competenceOK = reviewsOK && masteryOK
        let activeDaysOK = activeDaysCount >= activeDaysThreshold
        return (competenceOK || activeDaysOK) ? .eligible : .notEligible
    }
}
