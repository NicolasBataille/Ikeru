import Foundation
import IkeruCore

// MARK: - Shared Drill Utilities

/// Free functions shared by KanaDrillViewModel and VocabularyDrillViewModel
/// to avoid duplicating FSRS formatting, grading, and prediction logic.

/// Format the time interval between two dates into a compact French string
/// used on flashcard reveal buttons (e.g. "5 min", "2 h", "3 j", "1 mois").
func formatFSRSInterval(from start: Date, to end: Date) -> String {
    let seconds = max(0, end.timeIntervalSince(start))
    if seconds < 60 {
        return "1 min"
    }
    let minutes = Int(ceil(seconds / 60))
    if minutes < 60 {
        return "\(minutes) min"
    }
    let hours = Int(ceil(seconds / 3_600))
    if hours < 24 {
        return "\(hours) h"
    }
    let days = Int(ceil(seconds / 86_400))
    if days < 30 {
        return "\(days) j"
    }
    let months = Int(ceil(seconds / (86_400 * 30)))
    return "\(months) mois"
}

/// Map a quiz result (correct / response time) to an FSRS Grade using a speed bonus.
/// - Wrong → `.again`
/// - Correct under 2 s → `.easy`
/// - Correct under 5 s → `.good`
/// - Otherwise → `.hard`
func mapQuizResultToGrade(correct: Bool, responseTimeMs: Int) -> Grade {
    if !correct { return .again }
    if responseTimeMs < 2_000 { return .easy }
    if responseTimeMs < 5_000 { return .good }
    return .hard
}

/// Run FSRS scheduling once per grade to estimate intervals shown on flashcard
/// reveal buttons. Returns a dictionary mapping each grade to a formatted string.
func computePredictedIntervals(fsrsState: FSRSState, now: Date) -> [Grade: String] {
    var result: [Grade: String] = [:]
    for grade in Grade.allCases {
        let newState = FSRSService.schedule(state: fsrsState, grade: grade, now: now)
        let due = FSRSService.dueDate(for: newState, now: now)
        result[grade] = formatFSRSInterval(from: now, to: due)
    }
    return result
}
