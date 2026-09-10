import SwiftUI
import IkeruCore

/// La ligne qui rend le mapping vitesse→note visible (OBS2-015).
///
/// Sous « Correct ! », l'apprenant lit ce que le quiz a réellement noté, en
/// combien de temps, et quand la carte revient — l'intervalle que la note
/// applique vraiment, pas celui d'un aperçu. Avant, « Correct ! » et
/// « 100 % » masquaient des « Difficile » silencieux côté SRS.
struct QuizOutcomeLine: View {
    let outcome: QuizGradeOutcome

    var body: some View {
        Text(line)
            .font(.ikeruCaption)
            .foregroundStyle(Color.ikeruTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("quiz.outcomeLine")
    }

    private var line: LocalizedStringKey {
        let grade = Self.gradeName(outcome.grade)
        let back = outcome.nextInterval
        if outcome.grade == .again {
            return "Marked \(grade) · back in \(back)"
        }
        if outcome.isFirstEncounter {
            return "First time you see it · marked \(grade) · back in \(back)"
        }
        let seconds = String(format: "%.1f", Double(outcome.responseTimeMs) / 1000)
        return "Answered in \(seconds) s · marked \(grade) · back in \(back)"
    }

    static func gradeName(_ grade: Grade) -> String {
        switch grade {
        case .again: String(localized: "Again")
        case .hard: String(localized: "Hard")
        case .good: String(localized: "Good")
        case .easy: String(localized: "Easy")
        }
    }
}
