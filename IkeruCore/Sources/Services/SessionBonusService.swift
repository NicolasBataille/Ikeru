import Foundation

/// Pure-function service that computes the end-of-session XP bonus awarded
/// for daily engagement (regardless of review accuracy).
///
/// This is the "reward for showing up" layer. Per-card XP is flat via
/// `RPGConstants.xpForGrade`; the meaningful consistency signal lives here.
public enum SessionBonusService {

    /// Result of evaluating a completed session for bonus XP.
    public struct Result: Equatable, Sendable {
        /// XP to award for this session (sum of first-of-day + milestones).
        public let bonusXP: Int
        /// Updated daily streak count to persist.
        public let newDailyStreak: Int
        /// Updated longest-streak high-water mark.
        public let newLongestStreak: Int
        /// Whether this was the first session of a new day.
        public let isNewDay: Bool
        /// Whether the 5-day milestone triggered this session.
        public let hitFiveDayMilestone: Bool
        /// Whether the 30-day milestone triggered this session.
        public let hitThirtyDayMilestone: Bool

        public init(
            bonusXP: Int,
            newDailyStreak: Int,
            newLongestStreak: Int,
            isNewDay: Bool,
            hitFiveDayMilestone: Bool,
            hitThirtyDayMilestone: Bool
        ) {
            self.bonusXP = bonusXP
            self.newDailyStreak = newDailyStreak
            self.newLongestStreak = newLongestStreak
            self.isNewDay = isNewDay
            self.hitFiveDayMilestone = hitFiveDayMilestone
            self.hitThirtyDayMilestone = hitThirtyDayMilestone
        }
    }

    /// Evaluates a session completion for bonus XP and streak progress.
    /// - Parameters:
    ///   - now: The moment the session completed.
    ///   - lastSessionDate: The last time a session was completed, if any.
    ///   - currentStreak: Current consecutive daily-session streak.
    ///   - longestStreak: Historical longest streak.
    ///   - calendar: Calendar used for day-boundary comparison (defaults to user's).
    public static func evaluate(
        now: Date,
        lastSessionDate: Date?,
        currentStreak: Int,
        longestStreak: Int,
        calendar: Calendar = .current
    ) -> Result {
        let isNewDay: Bool
        let newStreak: Int

        if let last = lastSessionDate {
            let daysBetween = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: now)
            ).day ?? 0

            switch daysBetween {
            case 0:
                isNewDay = false
                newStreak = max(1, currentStreak)
            case 1:
                isNewDay = true
                newStreak = currentStreak + 1
            default:
                isNewDay = true
                newStreak = 1
            }
        } else {
            isNewDay = true
            newStreak = 1
        }

        var bonus = 0
        var hitFive = false
        var hitThirty = false

        if isNewDay {
            bonus += RPGConstants.firstSessionOfDayBonus

            let previousStreak = currentStreak
            let crossingFive = previousStreak < 5 && newStreak >= 5
            let crossingThirty = previousStreak < 30 && newStreak >= 30

            if crossingFive {
                bonus += RPGConstants.fiveDayStreakBonus
                hitFive = true
            }
            if crossingThirty {
                bonus += RPGConstants.thirtyDayStreakBonus
                hitThirty = true
            }
        }

        let newLongest = max(longestStreak, newStreak)

        return Result(
            bonusXP: bonus,
            newDailyStreak: newStreak,
            newLongestStreak: newLongest,
            isNewDay: isNewDay,
            hitFiveDayMilestone: hitFive,
            hitThirtyDayMilestone: hitThirty
        )
    }
}
