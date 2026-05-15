import Foundation

// MARK: - AnalyticsEvent

/// Canonical event names. Keep this list short and stable — every rename
/// breaks historical dashboards. Use `snake_case` to match PostHog convention.
public enum AnalyticsEvent {
    public static let appOpened           = "app_opened"
    public static let onboardingCompleted = "onboarding_completed"
    public static let sessionStarted      = "session_started"
    public static let sessionCompleted    = "session_completed"
    public static let cardReviewed        = "card_reviewed"
    public static let featureUsed         = "feature_used"
}

// MARK: - Property keys

/// Canonical property names. Same rationale as `AnalyticsEvent` — renames are
/// breaking changes on the dashboard side.
public enum AnalyticsProperty {
    public static let cardsReviewed   = "cards_reviewed"
    public static let durationSeconds = "duration_seconds"
    public static let exerciseType    = "exercise_type"
    public static let jlptLevel       = "jlpt_level"
    public static let sessionSource   = "session_source"
    public static let feature         = "feature"
    public static let locale          = "locale"
}
