import Foundation
import os

/// Computes weekly learning summaries and tracks check-in scheduling.
///
/// All summary computation is local — no paid APIs. The service reads review logs
/// and card data to produce structured observations and recommendations.
public final class WeeklyCheckInService: Sendable {

    // MARK: - Constants

    /// Key used to persist the last check-in date in UserDefaults.
    private static let lastCheckInKey = "ikeru_lastWeeklyCheckInDate"

    /// Minimum days between check-ins.
    private static let checkInIntervalDays = 7

    /// Stability threshold (in days) to consider a kanji card "mastered".
    private static let masteredStabilityThreshold: Double = 21.0

    /// Accuracy drop threshold to generate a warning observation.
    private static let accuracyDropThreshold: Double = 0.10

    // MARK: - Dependencies

    private let cardRepository: CardRepository
    /// UserDefaults is thread-safe for reads/writes but not Sendable.
    /// Access is limited to simple key-value operations on the main queue caller side.
    nonisolated(unsafe) private let userDefaults: UserDefaults

    // MARK: - Init

    public init(
        cardRepository: CardRepository,
        userDefaults: UserDefaults = .standard
    ) {
        self.cardRepository = cardRepository
        self.userDefaults = userDefaults
    }

    // MARK: - Check-In Scheduling

    /// Whether a weekly check-in is due (7+ days since last check-in).
    public func isCheckInDue() -> Bool {
        guard let lastDate = lastCheckInDate() else {
            // Never checked in — due if the user has any review history
            return true
        }
        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysSince >= Self.checkInIntervalDays
    }

    /// Records the current date as the last check-in date.
    public func recordCheckIn() {
        userDefaults.set(Date(), forKey: Self.lastCheckInKey)
    }

    /// Returns the last check-in date, if any.
    public func lastCheckInDate() -> Date? {
        userDefaults.object(forKey: Self.lastCheckInKey) as? Date
    }

    // MARK: - Summary Generation

    /// Generates a structured weekly summary from local data.
    /// - Returns: A `WeeklyCheckInSummary` covering the past 7 days.
    public func generateWeeklySummary() async -> WeeklyCheckInSummary {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let allCards = await cardRepository.allCards()
        let reviewLogs = await cardRepository.allReviewLogs(from: weekStart, to: now)

        let sessionsCompleted = countSessions(from: reviewLogs)
        let cardsReviewed = reviewLogs.count
        let newCardsLearned = countNewCards(allCards: allCards, since: weekStart)
        let kanjiMastered = countKanjiMastered(allCards: allCards)
        let overallAccuracy = computeAccuracy(from: reviewLogs)
        let skillCounts = computeSkillReviewCounts(from: reviewLogs)
        let skillAccuracies = computeSkillAccuracies(from: reviewLogs)
        let observations = generateObservations(
            reviewLogs: reviewLogs,
            skillAccuracies: skillAccuracies,
            kanjiMastered: kanjiMastered,
            newCardsLearned: newCardsLearned
        )
        let recommendations = generateRecommendations(
            skillCounts: skillCounts,
            skillAccuracies: skillAccuracies,
            overallAccuracy: overallAccuracy,
            sessionsCompleted: sessionsCompleted
        )

        return WeeklyCheckInSummary(
            weekStartDate: weekStart,
            weekEndDate: now,
            sessionsCompleted: sessionsCompleted,
            cardsReviewed: cardsReviewed,
            newCardsLearned: newCardsLearned,
            kanjiMastered: kanjiMastered,
            overallAccuracy: overallAccuracy,
            skillReviewCounts: skillCounts,
            observations: observations,
            recommendations: recommendations
        )
    }

    /// Computes per-skill accuracy for export purposes.
    public func computeSkillAccuraciesForExport(
        from reviewLogs: [ReviewLogDTO]
    ) -> [String: Double] {
        computeSkillAccuracies(from: reviewLogs)
    }

    // MARK: - Private Computation

    /// Estimates session count by grouping reviews into 30-minute windows.
    private func countSessions(from logs: [ReviewLogDTO]) -> Int {
        guard !logs.isEmpty else { return 0 }

        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        var sessionCount = 1
        var lastTimestamp = sorted[0].timestamp

        for log in sorted.dropFirst() {
            let gap = log.timestamp.timeIntervalSince(lastTimestamp)
            // A gap of 30+ minutes indicates a new session
            if gap > 1800 {
                sessionCount += 1
            }
            lastTimestamp = log.timestamp
        }

        return sessionCount
    }

    /// Counts cards first reviewed this week (reps == 1 and last review within range).
    private func countNewCards(allCards: [CardDTO], since startDate: Date) -> Int {
        allCards.filter { card in
            guard let lastReview = card.fsrsState.lastReview else { return false }
            return card.fsrsState.reps > 0
                && lastReview >= startDate
                && card.fsrsState.reps <= 2 // Only 1-2 reps means likely new this week
        }.count
    }

    /// Counts kanji cards that have reached mastered stability.
    private func countKanjiMastered(allCards: [CardDTO]) -> Int {
        allCards.filter { card in
            card.type == .kanji
                && card.fsrsState.stability >= Self.masteredStabilityThreshold
        }.count
    }

    /// Computes overall accuracy as the ratio of Good+Easy grades to total reviews.
    private func computeAccuracy(from logs: [ReviewLogDTO]) -> Double {
        guard !logs.isEmpty else { return 0 }
        let successCount = logs.filter { $0.grade == .good || $0.grade == .easy }.count
        return Double(successCount) / Double(logs.count)
    }

    /// Counts reviews per skill type for balance analysis.
    private func computeSkillReviewCounts(from logs: [ReviewLogDTO]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for log in logs {
            let skillName = skillName(for: log.cardType)
            counts[skillName, default: 0] += 1
        }
        return counts
    }

    /// Computes accuracy per skill type.
    private func computeSkillAccuracies(from logs: [ReviewLogDTO]) -> [String: Double] {
        var skillLogs: [String: [ReviewLogDTO]] = [:]
        for log in logs {
            let name = skillName(for: log.cardType)
            skillLogs[name, default: []].append(log)
        }

        var accuracies: [String: Double] = [:]
        for (skill, skillReviews) in skillLogs {
            let successes = skillReviews.filter { $0.grade == .good || $0.grade == .easy }.count
            accuracies[skill] = Double(successes) / Double(skillReviews.count)
        }
        return accuracies
    }

    /// Maps CardType to a human-readable skill name.
    private func skillName(for cardType: CardType?) -> String {
        switch cardType {
        case .kanji, .vocabulary:
            "reading"
        case .grammar:
            "writing"
        case .listening:
            "listening"
        case nil:
            "unknown"
        }
    }

    /// Generates human-readable observations from weekly data.
    private func generateObservations(
        reviewLogs: [ReviewLogDTO],
        skillAccuracies: [String: Double],
        kanjiMastered: Int,
        newCardsLearned: Int
    ) -> [String] {
        var observations: [String] = []

        // Highlight kanji mastery achievements
        if kanjiMastered > 0 {
            observations.append("You have \(kanjiMastered) kanji at mastered level.")
        }

        // Highlight new cards learned
        if newCardsLearned > 0 {
            observations.append("You learned \(newCardsLearned) new cards this week.")
        }

        // Flag skills with low accuracy
        for (skill, accuracy) in skillAccuracies {
            if accuracy < 0.6 {
                let pct = Int(accuracy * 100)
                observations.append("\(skill.capitalized) accuracy is at \(pct)% -- this area needs attention.")
            }
        }

        // Flag skills with very high accuracy (potential for more challenge)
        for (skill, accuracy) in skillAccuracies {
            if accuracy > 0.95 {
                observations.append("\(skill.capitalized) accuracy is excellent -- you might be ready for harder material.")
            }
        }

        // No reviews at all
        if reviewLogs.isEmpty {
            observations.append("No reviews were completed this week.")
        }

        return observations
    }

    /// Generates recommendations based on weekly patterns.
    private func generateRecommendations(
        skillCounts: [String: Int],
        skillAccuracies: [String: Double],
        overallAccuracy: Double,
        sessionsCompleted: Int
    ) -> [String] {
        var recommendations: [String] = []

        // Low session count
        if sessionsCompleted < 3 {
            recommendations.append("Try to study at least 3 times per week for consistent progress.")
        }

        // Skill imbalance detection
        let totalReviews = skillCounts.values.reduce(0, +)
        if totalReviews > 0 {
            let neglectedSkills = SkillType.allCases.filter { skill in
                let count = skillCounts[skill.rawValue] ?? 0
                return Double(count) / Double(totalReviews) < 0.10
            }
            for skill in neglectedSkills {
                recommendations.append("Consider adding more \(skill.rawValue) practice to your sessions.")
            }
        }

        // Accuracy-based recommendations
        if overallAccuracy < 0.7 && overallAccuracy > 0 {
            recommendations.append("Your overall accuracy is below 70%. Consider reviewing easier material first.")
        }

        return recommendations
    }
}
