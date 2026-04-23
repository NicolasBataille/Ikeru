import Foundation

/// Pure-function detector for mastery milestones during card review.
/// Inputs: the pre-grade card state + the grade the learner just applied.
/// Outputs: zero or more `MasteryEvent` values that should fire loot drops.
///
/// Events are detected on PRE-grade state so we can reason about the card
/// the learner was actually looking at (reps, interval, leech status).
public enum MasteryEventDetector {

    /// Minimum interval (in days) that counts as a "long interval recall".
    public static let longIntervalDays: Int = 30

    /// Minimum interval (in days) to mark a card as burned-in.
    public static let burnedIntervalDays: Int = 180

    /// Minimum lapses to classify a card as a leech candidate for recovery.
    public static let leechLapseThreshold: Int = 3

    /// Detects mastery events for a single graded review.
    /// Only correct grades (good / easy) trigger events — lapses reset.
    /// - Parameters:
    ///   - preGradeCard: The card's state before grading.
    ///   - grade: The grade just applied.
    /// - Returns: All applicable mastery events (0-N), ordered highest rarity first.
    public static func detect(preGradeCard card: CardDTO, grade: Grade) -> [MasteryEvent] {
        guard grade == .good || grade == .easy else { return [] }

        var events: [MasteryEvent] = []

        if card.interval >= burnedIntervalDays {
            events.append(.burned)
        }
        if card.leechFlag && card.lapseCount >= leechLapseThreshold {
            events.append(.leechRecovered)
        }
        if card.interval >= longIntervalDays && card.interval < burnedIntervalDays {
            events.append(.longIntervalRecall)
        }
        if card.fsrsState.reps == 0 {
            events.append(.graduation)
        }

        return events
    }
}
