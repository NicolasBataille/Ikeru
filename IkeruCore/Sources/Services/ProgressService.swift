import Foundation
import os

// MARK: - Skill Balance

/// Represents a snapshot of the learner's balance across the four language skills.
/// Each value is normalized to 0.0–1.0 (fraction of cards mastered in that category).
public struct SkillBalanceSnapshot: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    public let speaking: Double

    public init(
        reading: Double = 0,
        writing: Double = 0,
        listening: Double = 0,
        speaking: Double = 0
    ) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }
}

// MARK: - JLPT Estimate

/// Represents the learner's estimated JLPT level mastery.
public struct JLPTEstimate: Sendable, Equatable {
    /// The estimated JLPT level (e.g., "N5", "N4").
    public let level: String
    /// Fraction mastered within this level (0.0–1.0).
    public let masteryFraction: Double
    /// Count of mastered items at this level.
    public let masteredCount: Int
    /// Total items required for this level.
    public let totalRequired: Int

    public init(level: String, masteryFraction: Double, masteredCount: Int, totalRequired: Int) {
        self.level = level
        self.masteryFraction = masteryFraction
        self.masteredCount = masteredCount
        self.totalRequired = totalRequired
    }
}

// MARK: - Monthly Snapshot

/// A snapshot of progress for a given month.
public struct MonthlySnapshot: Sendable, Equatable, Identifiable {
    public var id: String { monthLabel }
    /// Display label (e.g., "Mar", "Apr").
    public let monthLabel: String
    /// Number of cards mastered (reps > 0) by end of month.
    public let cardsMastered: Int
    /// Accuracy as fraction (0.0–1.0) for reviews in that month.
    public let accuracy: Double

    public init(monthLabel: String, cardsMastered: Int, accuracy: Double) {
        self.monthLabel = monthLabel
        self.cardsMastered = cardsMastered
        self.accuracy = accuracy
    }
}

// MARK: - Review Forecast Entry

/// A single point in the daily review forecast.
public struct ForecastEntry: Sendable, Equatable, Identifiable {
    public var id: String { dayLabel }
    /// Display label (e.g., "Mon", "Tue", or date).
    public let dayLabel: String
    /// Number of cards due on this day.
    public let cardsDue: Int

    public init(dayLabel: String, cardsDue: Int) {
        self.dayLabel = dayLabel
        self.cardsDue = cardsDue
    }
}

// MARK: - Progress Dashboard Data

/// Aggregated data for the progress dashboard.
public struct ProgressDashboardData: Sendable, Equatable {
    public let skillBalance: SkillBalanceSnapshot
    public let jlptEstimate: JLPTEstimate
    public let dueNowCount: Int
    public let dueTodayCount: Int
    public let forecast: [ForecastEntry]
    public let monthlySnapshots: [MonthlySnapshot]

    public init(
        skillBalance: SkillBalanceSnapshot,
        jlptEstimate: JLPTEstimate,
        dueNowCount: Int,
        dueTodayCount: Int,
        forecast: [ForecastEntry],
        monthlySnapshots: [MonthlySnapshot]
    ) {
        self.skillBalance = skillBalance
        self.jlptEstimate = jlptEstimate
        self.dueNowCount = dueNowCount
        self.dueTodayCount = dueTodayCount
        self.forecast = forecast
        self.monthlySnapshots = monthlySnapshots
    }
}

// MARK: - Progress Service

/// Aggregates card data into dashboard metrics.
/// All computations are pure — depends only on CardRepository for data.
public final class ProgressService: Sendable {

    private let cardRepository: CardRepository

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    /// Loads and computes all progress dashboard data.
    public func loadDashboardData(now: Date = Date()) async -> ProgressDashboardData {
        let startTime = CFAbsoluteTimeGetCurrent()

        let allCards = await cardRepository.allCards()
        let dueNow = await cardRepository.dueCards(before: now)

        let skillBalance = computeSkillBalance(allCards: allCards)
        let jlptEstimate = computeJLPTEstimate(allCards: allCards)
        let dueTodayCount = computeDueTodayCount(allCards: allCards, now: now)
        let forecast = computeForecast(allCards: allCards, now: now)
        let snapshots = computeMonthlySnapshots(allCards: allCards, now: now)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.planner.info(
            "Progress data loaded in \(String(format: "%.1f", elapsed))ms — \(allCards.count) cards, \(dueNow.count) due"
        )

        return ProgressDashboardData(
            skillBalance: skillBalance,
            jlptEstimate: jlptEstimate,
            dueNowCount: dueNow.count,
            dueTodayCount: dueTodayCount,
            forecast: forecast,
            monthlySnapshots: snapshots
        )
    }

    // MARK: - Skill Balance

    /// Computes skill balance as fraction of mastered cards per type.
    private func computeSkillBalance(allCards: [CardDTO]) -> SkillBalanceSnapshot {
        let masteredByType = Dictionary(grouping: allCards) { $0.type }

        func masteryRatio(for type: CardType) -> Double {
            guard let cards = masteredByType[type], !cards.isEmpty else { return 0 }
            let mastered = cards.filter { $0.fsrsState.reps > 0 }.count
            return Double(mastered) / Double(cards.count)
        }

        // Map card types to skill axes:
        // kanji + vocabulary → reading, grammar → writing,
        // listening → listening, vocabulary (spoken) → speaking
        let kanjiCards = masteredByType[.kanji] ?? []
        let vocabCards = masteredByType[.vocabulary] ?? []
        let _ = masteredByType[.grammar] ?? []
        let _ = masteredByType[.listening] ?? []

        let readingTotal = kanjiCards.count + vocabCards.count
        let readingMastered = kanjiCards.filter { $0.fsrsState.reps > 0 }.count
            + vocabCards.filter { $0.fsrsState.reps > 0 }.count
        let readingRatio = readingTotal > 0 ? Double(readingMastered) / Double(readingTotal) : 0

        return SkillBalanceSnapshot(
            reading: readingRatio,
            writing: masteryRatio(for: .grammar),
            listening: masteryRatio(for: .listening),
            speaking: estimateSpeakingScore(allCards: allCards)
        )
    }

    /// Speaking is estimated from overall accuracy across all card types
    /// (proxy for output ability until dedicated speaking exercises exist).
    private func estimateSpeakingScore(allCards: [CardDTO]) -> Double {
        let reviewed = allCards.filter { $0.fsrsState.reps > 0 }
        guard !reviewed.isEmpty else { return 0 }
        // Use average ease factor as a rough proxy (higher ease → better recall → better output)
        let avgEase = reviewed.reduce(0.0) { $0 + $1.easeFactor } / Double(reviewed.count)
        // Normalize: ease typically ranges 1.3..3.0, map to 0..1
        return min(1.0, max(0, (avgEase - 1.3) / 1.7))
    }

    // MARK: - JLPT Estimate

    /// Estimates JLPT level based on total mastered vocabulary + kanji.
    /// N5 ≈ 100 items, N4 ≈ 300, N3 ≈ 650, N2 ≈ 1000, N1 ≈ 2000
    private func computeJLPTEstimate(allCards: [CardDTO]) -> JLPTEstimate {
        let mastered = allCards.filter { $0.fsrsState.reps > 0 }.count

        let levels: [(level: String, threshold: Int)] = [
            ("N5", 100),
            ("N4", 300),
            ("N3", 650),
            ("N2", 1000),
            ("N1", 2000)
        ]

        // Find the highest level the learner is working toward
        for (level, threshold) in levels {
            if mastered < threshold {
                let fraction = Double(mastered) / Double(threshold)
                return JLPTEstimate(
                    level: level,
                    masteryFraction: fraction,
                    masteredCount: mastered,
                    totalRequired: threshold
                )
            }
        }

        // Beyond N1
        return JLPTEstimate(
            level: "N1",
            masteryFraction: 1.0,
            masteredCount: mastered,
            totalRequired: 2000
        )
    }

    // MARK: - Due Today

    /// Counts cards due by end of today.
    private func computeDueTodayCount(allCards: [CardDTO], now: Date) -> Int {
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(
            bySettingHour: 23, minute: 59, second: 59, of: now
        ) else {
            return 0
        }
        return allCards.filter { $0.dueDate <= endOfDay }.count
    }

    // MARK: - Forecast

    /// Computes a 7-day review forecast.
    private func computeForecast(allCards: [CardDTO], now: Date) -> [ForecastEntry] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).map { dayOffset in
            let dayStart = calendar.startOfDay(for: calendar.date(
                byAdding: .day, value: dayOffset, to: now
            ) ?? now)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dueCount = allCards.filter { card in
                card.dueDate >= dayStart && card.dueDate < dayEnd
            }.count

            let label = dayOffset == 0 ? "Today" : formatter.string(from: dayStart)
            return ForecastEntry(dayLabel: label, cardsDue: dueCount)
        }
    }

    // MARK: - Monthly Snapshots

    /// Computes monthly snapshots for the last 6 months.
    private func computeMonthlySnapshots(
        allCards: [CardDTO],
        now: Date
    ) -> [MonthlySnapshot] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        return (0..<6).reversed().map { monthOffset in
            guard let monthDate = calendar.date(
                byAdding: .month, value: -monthOffset, to: now
            ) else {
                return MonthlySnapshot(monthLabel: "?", cardsMastered: 0, accuracy: 0)
            }

            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: monthDate)
            ) ?? monthDate
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthDate

            // Cards mastered by end of this month: cards with lastReview before monthEnd
            let masteredByMonth = allCards.filter { card in
                guard let lastReview = card.fsrsState.lastReview else { return false }
                return lastReview < monthEnd && card.fsrsState.reps > 0
            }.count

            // Accuracy proxy: average ease factor of cards reviewed in this month
            let reviewedInMonth = allCards.filter { card in
                guard let lastReview = card.fsrsState.lastReview else { return false }
                return lastReview >= monthStart && lastReview < monthEnd
            }

            let accuracy: Double
            if reviewedInMonth.isEmpty {
                accuracy = 0
            } else {
                let avgEase = reviewedInMonth.reduce(0.0) { $0 + $1.easeFactor }
                    / Double(reviewedInMonth.count)
                accuracy = min(1.0, max(0, (avgEase - 1.3) / 1.7))
            }

            return MonthlySnapshot(
                monthLabel: formatter.string(from: monthDate),
                cardsMastered: masteredByMonth,
                accuracy: accuracy
            )
        }
    }
}
