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
/// - **Première rencontre notée, correcte → `.good`** (voir ci-dessous)
/// - Correct under 2 s → `.easy`
/// - Correct under 5 s → `.good`
/// - Otherwise → `.hard`
///
/// ### Pourquoi la première rencontre échappe au chronomètre (OBS2-015)
///
/// Le seuil de 5 s punit systématiquement la population que le produit vise.
/// Un débutant qui voit un mot pour la PREMIÈRE fois lit la question, lit
/// quatre propositions, se décide : il dépasse 5 s presque à tous les coups.
/// Sa bonne réponse était donc notée « difficile », ce qui raccourcit
/// l'intervalle et fait revenir la carte plus vite — l'app en déduisait une
/// fragilité qu'elle venait d'inventer.
///
/// Rien à l'écran n'annonce qu'un chronomètre tourne, et l'intervalle
/// réellement appliqué contredisait celui affiché sur la carte. À défaut de
/// rendre le mécanisme visible — ce qui reste à faire — il ne s'applique plus
/// au tout premier passage noté d'une carte, là où il n'a aucune chance de
/// mesurer une vitesse de rappel : il n'y a encore rien à rappeler.
///
/// - Parameter isFirstEncounter: `true` quand la carte n'a jamais été notée
///   (`fsrsState.reps == 0`). L'appelant le sait, pas cette fonction.
func mapQuizResultToGrade(
    correct: Bool,
    responseTimeMs: Int,
    isFirstEncounter: Bool = false
) -> Grade {
    if !correct { return .again }
    if isFirstEncounter { return .good }
    if responseTimeMs < 2_000 { return .easy }
    if responseTimeMs < 5_000 { return .good }
    return .hard
}

/// Run FSRS scheduling once per grade to estimate intervals shown on flashcard
/// reveal buttons. Returns a dictionary mapping each grade to a formatted string.
/// `desiredRetention` MUST be the active profile's setting
/// (`CardRepository.activeDesiredRetention()`) so the prediction matches what
/// grading will actually schedule — the earlier default-0.9 predictions
/// silently contradicted a learner's 0.80/0.95 target.
func computePredictedIntervals(
    fsrsState: FSRSState,
    now: Date,
    desiredRetention: Double = 0.9
) -> [Grade: String] {
    var result: [Grade: String] = [:]
    for grade in Grade.allCases {
        let newState = FSRSService.schedule(state: fsrsState, grade: grade, now: now)
        let due = FSRSService.dueDate(for: newState, desiredRetention: desiredRetention, now: now)
        result[grade] = formatFSRSInterval(from: now, to: due)
    }
    return result
}
