import Foundation

/// User-configurable settings for their learning experience.
/// Stored as a Codable struct within UserProfile.
public struct ProfileSettings: Codable, Equatable, Sendable {

    /// Target retention rate (0.0–1.0) for FSRS scheduling
    public let desiredRetention: Double

    /// Maximum number of new cards to introduce per day
    public let dailyNewCardLimit: Int

    /// Maximum number of review cards to show per day
    public let dailyReviewLimit: Int

    /// Whether daily review reminders are enabled
    public let reviewReminderEnabled: Bool

    /// Hour of day for the review reminder (0-23)
    public let reviewReminderHour: Int

    /// Whether weekly check-in notifications are enabled
    public let weeklyCheckInEnabled: Bool

    /// Day of week for check-in (1=Sunday, 7=Saturday)
    public let weeklyCheckInDay: Int

    /// Hour of day for the weekly check-in (0-23)
    public let weeklyCheckInHour: Int

    public init(
        desiredRetention: Double = 0.9,
        dailyNewCardLimit: Int = 20,
        dailyReviewLimit: Int = 200,
        reviewReminderEnabled: Bool = false,
        reviewReminderHour: Int = 9,
        weeklyCheckInEnabled: Bool = false,
        weeklyCheckInDay: Int = 1,
        weeklyCheckInHour: Int = 10
    ) {
        self.desiredRetention = desiredRetention
        self.dailyNewCardLimit = dailyNewCardLimit
        self.dailyReviewLimit = dailyReviewLimit
        self.reviewReminderEnabled = reviewReminderEnabled
        self.reviewReminderHour = reviewReminderHour
        self.weeklyCheckInEnabled = weeklyCheckInEnabled
        self.weeklyCheckInDay = weeklyCheckInDay
        self.weeklyCheckInHour = weeklyCheckInHour
    }
}
