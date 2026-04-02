import Foundation

/// The output of adaptive session composition.
/// Contains an ordered list of exercises, timing estimates, and skill breakdowns.
public struct SessionPlan: Sendable, Equatable {

    /// Ordered list of exercises for the session.
    /// SRS reviews come first, followed by supplementary exercises
    /// ordered by pedagogical appropriateness (receptive before productive).
    public let exercises: [ExerciseItem]

    /// Estimated total duration in minutes.
    public let estimatedDurationMinutes: Int

    /// Count of exercises per skill type.
    public let exerciseBreakdown: [SkillType: Int]

    public init(
        exercises: [ExerciseItem],
        estimatedDurationMinutes: Int,
        exerciseBreakdown: [SkillType: Int]
    ) {
        self.exercises = exercises
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.exerciseBreakdown = exerciseBreakdown
    }

    /// An empty session plan with no exercises.
    public static let empty = SessionPlan(
        exercises: [],
        estimatedDurationMinutes: 0,
        exerciseBreakdown: [:]
    )

    /// Total number of SRS review cards in this plan.
    public var srsReviewCount: Int {
        exercises.filter {
            if case .srsReview = $0 { return true }
            return false
        }.count
    }

    /// Total number of non-SRS exercises in this plan.
    public var supplementaryExerciseCount: Int {
        exercises.count - srsReviewCount
    }
}
