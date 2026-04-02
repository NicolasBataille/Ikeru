import Foundation

/// A preview of what an upcoming session will contain.
/// Displayed on the home screen before the user starts a session.
public struct SessionPreview: Sendable, Equatable {

    /// Estimated session duration in minutes.
    public let estimatedMinutes: Int

    /// Total number of cards/exercises in the session.
    public let cardCount: Int

    /// Count of exercises per skill type.
    public let exerciseBreakdown: [SkillType: Int]

    /// Percentage split per skill type (0.0-1.0).
    public let skillSplit: [SkillType: Double]

    public init(
        estimatedMinutes: Int,
        cardCount: Int,
        exerciseBreakdown: [SkillType: Int],
        skillSplit: [SkillType: Double]
    ) {
        self.estimatedMinutes = estimatedMinutes
        self.cardCount = cardCount
        self.exerciseBreakdown = exerciseBreakdown
        self.skillSplit = skillSplit
    }

    /// An empty preview when no session data is available.
    public static let empty = SessionPreview(
        estimatedMinutes: 0,
        cardCount: 0,
        exerciseBreakdown: [:],
        skillSplit: [:]
    )
}
