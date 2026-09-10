import Foundation

/// Inputs to `SessionPlanner.compose(...)`. Two distinct request shapes,
/// both producing a `SessionPlan`.
public struct SessionPlannerInputs: Sendable, Equatable {

    public enum Source: Sendable, Equatable {
        /// Home: auto-composed via the 40/30/20/10 skeleton + level-tied variety.
        case homeRecommendation
        /// Étude: user-specified types and JLPT levels, no skill-balance feedback.
        case studyCustom(types: Set<ExerciseType>, jlptLevels: Set<JLPTLevel>)
        /// Home, but the learner has nothing due and CHOSE what to do anyway.
        ///
        /// This exists so that "there is nothing to review" stops being a dead
        /// end. It is deliberately a separate source rather than a fallback
        /// inside `homeRecommendation`: a session the learner explicitly asked
        /// for is not the same thing as one the app composed on its own, and
        /// the old behaviour — quietly filling the gap — is exactly what the
        /// owner ruled out on 2026-08-16 ("explicite et présenté", not
        /// "rempli en silence").
        case caughtUp(CaughtUpOffer)
    }

    /// What a learner with nothing due chose to do.
    ///
    /// Two offers, because they answer two different wants and draw on two
    /// different pools — see `DefaultSessionPlanner.composeDeepen` /
    /// `composeDiscover`.
    public enum CaughtUpOffer: String, Sendable, Equatable, CaseIterable {
        /// Practise cards already started but not yet due, weakest first.
        ///
        /// Safe for FSRS: `scheduleReviewCard` derives elapsed time from
        /// `lastReview`, never from `dueDate`, so an early success simply
        /// earns a smaller stability gain than waiting would have. Measured,
        /// not assumed — see `FSRSServiceTests.earlyReviewEarnsLessStability`.
        case deepen
        /// Meet content never seen before, announced as new.
        case discover
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
