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

    public init(
        desiredRetention: Double = 0.9,
        dailyNewCardLimit: Int = 20,
        dailyReviewLimit: Int = 200
    ) {
        self.desiredRetention = desiredRetention
        self.dailyNewCardLimit = dailyNewCardLimit
        self.dailyReviewLimit = dailyReviewLimit
    }
}
