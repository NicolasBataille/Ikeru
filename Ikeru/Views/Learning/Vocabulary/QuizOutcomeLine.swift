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
    @Environment(\.locale) private var locale

    var body: some View {
        Text(line)
            .font(.ikeruCaption)
            .foregroundStyle(Color.ikeruTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("quiz.outcomeLine")
    }

    private var line: LocalizedStringKey {
        let grade = Self.gradeName(outcome.grade, locale: locale)
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

    /// Le nom de la note dans la langue de l'INTERFACE, pas de l'appareil.
    /// `String(localized:)` seul lit `Bundle.main` avec la langue système et
    /// ignore l'override `AppLocale` (le `\.locale` injecté à `MainTabView`) :
    /// appareil en français, app forcée en anglais, la phrase disait
    /// « Answered in 6.2 s · marked Difficile ». Voir `AppLocale.bundle(for:)`.
    static func gradeName(_ grade: Grade, locale: Locale) -> String {
        let bundle = AppLocale.bundle(for: locale)
        return switch grade {
        case .again: String(localized: "Again", bundle: bundle, locale: locale)
        case .hard: String(localized: "Hard", bundle: bundle, locale: locale)
        case .good: String(localized: "Good", bundle: bundle, locale: locale)
        case .easy: String(localized: "Easy", bundle: bundle, locale: locale)
        }
    }
}
