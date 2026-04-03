import Foundation

/// Structured summary of a learner's weekly progress for companion check-in conversations.
/// All properties are immutable and the type is Sendable for safe cross-actor transfer.
public struct WeeklyCheckInSummary: Sendable, Codable, Equatable {

    /// Start of the summary period.
    public let weekStartDate: Date

    /// End of the summary period.
    public let weekEndDate: Date

    /// Total distinct study sessions completed this week.
    public let sessionsCompleted: Int

    /// Total cards reviewed (including re-reviews of the same card).
    public let cardsReviewed: Int

    /// New cards seen for the first time this week.
    public let newCardsLearned: Int

    /// Kanji cards that reached mastered status (stability > threshold) this week.
    public let kanjiMastered: Int

    /// Overall accuracy this week (proportion of Good+Easy grades to total reviews).
    public let overallAccuracy: Double

    /// Per-skill review counts for the week, used to detect balance shifts.
    public let skillReviewCounts: [String: Int]

    /// Human-readable observations generated from the data (e.g. "Writing accuracy dropped 15%").
    public let observations: [String]

    /// Data-driven recommendations for the coming week.
    public let recommendations: [String]

    public init(
        weekStartDate: Date,
        weekEndDate: Date,
        sessionsCompleted: Int,
        cardsReviewed: Int,
        newCardsLearned: Int,
        kanjiMastered: Int,
        overallAccuracy: Double,
        skillReviewCounts: [String: Int],
        observations: [String],
        recommendations: [String]
    ) {
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.sessionsCompleted = sessionsCompleted
        self.cardsReviewed = cardsReviewed
        self.newCardsLearned = newCardsLearned
        self.kanjiMastered = kanjiMastered
        self.overallAccuracy = overallAccuracy
        self.skillReviewCounts = skillReviewCounts
        self.observations = observations
        self.recommendations = recommendations
    }
}

// MARK: - Export Envelope

/// Envelope wrapping the weekly summary with additional context for external AI agent consumption.
public struct CheckInExportEnvelope: Sendable, Codable {

    /// Schema version for forward compatibility.
    public let schemaVersion: Int

    /// Timestamp when the export was generated.
    public let exportedAt: Date

    /// The weekly summary data.
    public let summary: WeeklyCheckInSummary

    /// Per-skill accuracy breakdown (skill name -> accuracy 0.0-1.0).
    public let skillAccuracies: [String: Double]

    /// Learner-provided feedback captured during the check-in conversation.
    public let learnerFeedback: [String]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        summary: WeeklyCheckInSummary,
        skillAccuracies: [String: Double],
        learnerFeedback: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.summary = summary
        self.skillAccuracies = skillAccuracies
        self.learnerFeedback = learnerFeedback
    }
}
