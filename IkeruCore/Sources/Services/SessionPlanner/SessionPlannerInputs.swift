import Foundation

/// Inputs to `SessionPlanner.compose(...)`. Two distinct request shapes,
/// both producing a `SessionPlan`.
public struct SessionPlannerInputs: Sendable, Equatable {

    public enum Source: Sendable, Equatable {
        /// Home: auto-composed via the 40/30/20/10 skeleton + level-tied variety.
        case homeRecommendation
        /// Étude: user-specified types and JLPT levels, no skill-balance feedback.
        case studyCustom(types: Set<ExerciseType>, jlptLevels: Set<JLPTLevel>)
    }

    public let source: Source
    public let durationMinutes: Int
    public let profile: LearnerSnapshot
    public let unlockedTypes: Set<ExerciseType>
    public let availableCards: [CardDTO]

    public init(
        source: Source,
        durationMinutes: Int,
        profile: LearnerSnapshot,
        unlockedTypes: Set<ExerciseType>,
        availableCards: [CardDTO]
    ) {
        self.source = source
        self.durationMinutes = durationMinutes
        self.profile = profile
        self.unlockedTypes = unlockedTypes
        self.availableCards = availableCards
    }
}
