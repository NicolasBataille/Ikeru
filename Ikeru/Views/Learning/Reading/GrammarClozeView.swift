import SwiftUI
import IkeruCore

// MARK: - GrammarClozeView
//
// L'exercice de grammaire, à la place du placeholder.
//
// Avant ce lot, une séance qui tirait `.grammarExercise` affichait une icône,
// le titre « Grammar Exercise » et le mot « Grammar point » — un
// `placeholderExerciseView`, sans aucun rapport avec les 51 points du bundle.
// Le planificateur émettait même un `UUID()` fabriqué, qui ne désignait aucun
// point.

/// Une question à trou : la phrase amputée de son élément grammatical, et
/// quatre propositions.
///
/// La traduction reste sous la phrase, et ce n'est pas décoratif : sans elle
/// plusieurs réponses remplissent le trou de façon défendable. `写真を撮っ____
/// ですか。` seul admet trois réponses ; avec « Puis-je prendre une photo ? »
/// il n'en admet qu'une.
struct GrammarClozeView: View {

    let cloze: GrammarCloze
    let options: GrammarClozeOptions
    let onComplete: (Grade) -> Void

    @State private var chosenIndex: Int?

    private var hasAnswered: Bool { chosenIndex != nil }
    private var isCorrect: Bool { chosenIndex == options.correctIndex }

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer(minLength: 0)

            questionCard

            VStack(spacing: IkeruTheme.Spacing.sm) {
                ForEach(Array(options.options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, text: option)
                }
            }

            if hasAnswered {
                revealFooter
            }

            Spacer(minLength: 0)
        }
        .padding(IkeruTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("grammar.cloze")
    }

    // MARK: - Question

    private var questionCard: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text(japanese)
                .ikeruScaledFont(22, weight: .regular, relativeTo: .title3)
                .foregroundStyle(Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !translation.isEmpty {
                Text(translation)
                    .ikeruScaledFont(14, weight: .regular, relativeTo: .footnote)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(IkeruTheme.Spacing.lg)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.8) }
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
        .accessibilityElement(children: .combine)
    }

    /// La phrase est stockée « japonais — traduction ». On sépare à
    /// l'affichage plutôt qu'en base : la colonne reste lisible telle quelle,
    /// et l'audio comme les tests s'appuient dessus.
    private var japanese: String {
        cloze.sentence.components(separatedBy: " — ").first ?? cloze.sentence
    }

    private var translation: String {
        let parts = cloze.sentence.components(separatedBy: " — ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " — ") : ""
    }

    // MARK: - Options

    private func optionButton(index: Int, text: String) -> some View {
        Button {
            guard !hasAnswered else { return }
            chosenIndex = index
        } label: {
            Text(text)
                .ikeruScaledFont(17, weight: .regular, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background(for: index))
                .sumiCorners(color: borderColor(for: index), size: 5, weight: 1.0)
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
        .accessibilityIdentifier("grammar.option.\(index)")
    }

    /// Après réponse, la bonne est toujours marquée — y compris quand
    /// l'apprenant s'est trompé. Une correction qui ne montre pas la réponse
    /// juste apprend seulement qu'on a eu tort.
    private func background(for index: Int) -> some View {
        let fill: Color
        if !hasAnswered {
            fill = Color.white.opacity(0.03)
        } else if index == options.correctIndex {
            fill = Color(red: 0.616, green: 0.729, blue: 0.486).opacity(0.18)
        } else if index == chosenIndex {
            fill = TatamiTokens.vermilion.opacity(0.18)
        } else {
            fill = Color.white.opacity(0.02)
        }
        return Rectangle().fill(fill)
    }

    private func borderColor(for index: Int) -> Color {
        guard hasAnswered else { return TatamiTokens.goldDim.opacity(0.5) }
        if index == options.correctIndex { return Color(red: 0.616, green: 0.729, blue: 0.486) }
        if index == chosenIndex { return TatamiTokens.vermilion }
        return TatamiTokens.goldDim.opacity(0.25)
    }

    // MARK: - Reveal

    private var revealFooter: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text(cloze.title)
                .ikeruScaledFont(13, weight: .semibold, relativeTo: .footnote)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .multilineTextAlignment(.center)

            // Une seule note, pas les quatre de FSRS : sur un QCM la justesse
            // est déjà connue, et redemander « c'était facile ? » après coup
            // ferait porter la planification par une auto-évaluation que la
            // réponse contredit parfois.
            Button {
                onComplete(isCorrect ? .good : .again)
            } label: {
                Text("Continue")
                    .ikeruScaledFont(15, weight: .semibold, relativeTo: .body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .ikeruButtonStyle(.primary)
            .accessibilityIdentifier("grammar.continue")
        }
    }
}
