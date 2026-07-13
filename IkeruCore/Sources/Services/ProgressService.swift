import Foundation
import os

// MARK: - Skill Balance

/// Represents a snapshot of the learner's balance across the four language skills.
/// Each value is normalized to 0.0–1.0 (fraction of cards mastered in that category).
public struct SkillBalanceSnapshot: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    /// Speaking currently has no real signal (no `.speaking` card type and
    /// no persisted speaking-exercise results reachable from
    /// `CardRepository`), so `ProgressService` always reports 0 here — an
    /// honest "no data yet" rather than the previous fake ease-factor
    /// constant. See `ProgressService.computeSkillBalance`.
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

    /// Projects the four axes onto the `[SkillType: Double]` shape the
    /// `LearnerSnapshot` (and thus the planner's skill-balance booster +
    /// `skillImbalance`) consumes. Single source of truth for the mapping so
    /// every snapshot construction site stays consistent.
    public var asSkillBalances: [SkillType: Double] {
        [
            .reading: reading,
            .writing: writing,
            .listening: listening,
            .speaking: speaking,
        ]
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

        // Review logs covering the 6-month snapshot window. Accuracy is
        // derived from actual review grades — NOT from card `easeFactor`,
        // which `gradeCard` never mutates (it stays at the 2.5 default and
        // used to render as a constant ~0.71).
        let calendar = Calendar.current
        var windowStart = now
        if let oldestMonth = calendar.date(byAdding: .month, value: -5, to: now),
           let monthStart = calendar.date(
               from: calendar.dateComponents([.year, .month], from: oldestMonth)
           ) {
            windowStart = monthStart
        }
        let reviewLogs = await cardRepository.allReviewLogs(from: windowStart, to: now)
        let speakingAccuracy = await cardRepository.speakingAccuracyLast30()

        let skillBalance = computeSkillBalance(
            allCards: allCards,
            speakingAccuracy: speakingAccuracy
        )
        let jlptEstimate = computeJLPTReadinessEstimate(allCards: allCards, now: now)
        let dueTodayCount = computeDueTodayCount(allCards: allCards, now: now)
        let forecast = computeForecast(allCards: allCards, now: now)
        let snapshots = computeMonthlySnapshots(
            allCards: allCards,
            reviewLogs: reviewLogs,
            now: now
        )

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

    /// Computes skill balance as fraction of mastered cards per type. The
    /// speaking axis is not derivable from cards (no `.speaking` card type), so
    /// the caller supplies `speakingAccuracy` from persisted shadowing outcomes.
    private func computeSkillBalance(
        allCards: [CardDTO],
        speakingAccuracy: Double
    ) -> SkillBalanceSnapshot {
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
            // Speaking has no `.speaking` card type, so its signal comes from
            // persisted shadowing outcomes (`ExerciseOutcomeLog`), aggregated by
            // `CardRepository.speakingAccuracyLast30()` and passed in here. Still
            // 0 ("no data yet") until the learner has completed shadowing drills.
            speaking: speakingAccuracy
        )
    }

    // MARK: - JLPT Estimate

    /// Estimates JLPT readiness through `JLPTReadinessFormula`. Replaces
    /// the legacy "count any card with reps > 0" heuristic, which spiked
    /// after kana onboarding (kana cards are `.vocabulary` with
    /// `jlptLevel == nil`). The new pipeline routes through
    /// `LearnerSnapshotBuilder` so untagged cards never contribute to the
    /// per-level pool, and the report's `bestFit` is the highest level
    /// where every requirement axis (vocab/kanji/grammar/listen/recall)
    /// crosses the readiness threshold.
    ///
    /// `JLPTReadinessFormula.compute` does NOT read `snapshot.jlptLevel`;
    /// the snapshot is built with `.n5` as a placeholder so the dashboard
    /// computation stays pure (no need to look up the user's profile).
    private func computeJLPTReadinessEstimate(
        allCards: [CardDTO],
        now: Date
    ) -> JLPTEstimate {
        // Readiness-only placeholder snapshot: `JLPTReadinessFormula.compute`
        // reads only the per-level mastery buckets (vocab/kanji/grammar counts,
        // all derived from `allCards` by the builder) plus the listening axes.
        // It never reads `skillBalances`, so this stays `[:]` — feeding real
        // balances here would need `computeSkillBalance` and risk a cycle within
        // the same service. Listening accuracy has no source here (dashboard
        // load path), so 0 caps the listening axis honestly.
        let snapshot = LearnerSnapshotBuilder.build(
            cards: allCards,
            jlptLevel: .n5,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: now
        )
        let report = JLPTReadinessFormula.compute(snapshot: snapshot)

        // 10% sampled telemetry — high-volume event (every dashboard load).
        // Same sampling pattern as Spec B's `xp.attributed` event in
        // SessionViewModel; keeps log volume manageable while preserving
        // enough signal to chart readiness over time.
        if Int.random(in: 0..<100) < 10 {
            Logger.rpg.info(
                "readiness.computed bestFit=\(report.bestFit.rawValue) confidence=\(report.bestFitConfidence) n5=\(report.perLevel[.n5] ?? 0) n4=\(report.perLevel[.n4] ?? 0) n3=\(report.perLevel[.n3] ?? 0) n2=\(report.perLevel[.n2] ?? 0) n1=\(report.perLevel[.n1] ?? 0)"
            )
        }

        let bestFitReq = JLPTReadinessRequirements.requirements(for: report.bestFit)
        let masteredVocab = snapshot.vocabularyMasteredAtOrBelow[report.bestFit] ?? 0
        return JLPTEstimate(
            level: report.bestFit.displayName,
            masteryFraction: report.bestFitConfidence,
            masteredCount: masteredVocab,
            totalRequired: bestFitReq.vocab
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
    /// Accuracy is the share of successful grades (anything but `.again`)
    /// among the review logs recorded in each month.
    private func computeMonthlySnapshots(
        allCards: [CardDTO],
        reviewLogs: [ReviewLogDTO],
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

            // Accuracy: share of good/easy grades among reviews logged in
            // this month. Grades come from ReviewLog — the ease-factor
            // proxy used before was constant (easeFactor is never mutated).
            let logsInMonth = reviewLogs.filter { log in
                log.timestamp >= monthStart && log.timestamp < monthEnd
            }
            let accuracy = gradeAccuracy(of: logsInMonth)

            return MonthlySnapshot(
                monthLabel: formatter.string(from: monthDate),
                cardsMastered: masteredByMonth,
                accuracy: accuracy
            )
        }
    }

    /// Share of successful grades among the given logs. `.hard` counts as
    /// a success — it means "slow but correct"; only `.again` is a mistake
    /// (matching SessionViewModel's mistake tracking). Returns 0 when there
    /// are no logs (no data yet).
    private func gradeAccuracy(of logs: [ReviewLogDTO]) -> Double {
        guard !logs.isEmpty else { return 0 }
        let successes = logs.filter { $0.grade != .again }.count
        return Double(successes) / Double(logs.count)
    }
}
