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

    /// Choix PROVISOIRE : selectionner ne valide pas. Le tap joue la phrase
    /// completee par cette option, pour que l'apprenant la juge a l'oreille —
    /// c'est le reflexe qu'on veut installer — et il peut changer d'avis
    /// autant qu'il veut avant de valider.
    @State private var selectedIndex: Int?

    /// Choix VALIDE. Tant qu'il est nil, rien n'est corrige ni note.
    @State private var submittedIndex: Int?

    @State private var audioService = AudioService()

    private var hasAnswered: Bool { submittedIndex != nil }
    private var isCorrect: Bool { submittedIndex == options.correctIndex }

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
            } else if selectedIndex != nil {
                validateButton
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

    private var japanese: String { cloze.sentence }

    /// Dans la langue de l'apprenant : elle vient de la colonne localisée, pas
    /// d'une copie figée à la génération. La version figée affichait une glose
    /// anglaise sous une UI française (constaté sur device le 2026-08-19).
    private var translation: String { cloze.translation }

    /// La phrase complète, le trou rempli par la bonne réponse. Montrée
    /// seulement APRÈS coup — c'est elle qu'on fait entendre.
    private var completedSentence: String {
        cloze.completed(with: options.correctAnswer)
    }

    // MARK: - Options

    private func optionButton(index: Int, text: String) -> some View {
        Button {
            guard !hasAnswered else { return }
            selectedIndex = index
            // On entend SA propre proposition, pas la bonne reponse : les
            // quatre completions ont chacune leur clip (VOICEVOX, 51 x 4), donc
            // aucune ne se distingue a la voix. Sans ces clips, la bonne aurait
            // sonne « vraie » et les autres synthetiques — l'exercice se
            // gagnait a l'oreille sans connaitre la grammaire.
            let spoken = cloze.completed(with: text)
            Task { await audioService.playTTS(text: spoken) }
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
            fill = index == selectedIndex
                ? Color.ikeruPrimaryAccent.opacity(0.14)
                : Color.white.opacity(0.03)
        } else if index == options.correctIndex {
            fill = Color(red: 0.616, green: 0.729, blue: 0.486).opacity(0.18)
        } else if index == submittedIndex {
            fill = TatamiTokens.vermilion.opacity(0.18)
        } else {
            fill = Color.white.opacity(0.02)
        }
        return Rectangle().fill(fill)
    }

    private func borderColor(for index: Int) -> Color {
        guard hasAnswered else {
            return index == selectedIndex
                ? Color.ikeruPrimaryAccent
                : TatamiTokens.goldDim.opacity(0.5)
        }
        if index == options.correctIndex { return Color(red: 0.616, green: 0.729, blue: 0.486) }
        if index == submittedIndex { return TatamiTokens.vermilion }
        return TatamiTokens.goldDim.opacity(0.25)
    }

    // MARK: - Validate

    /// Valider est un geste distinct de choisir : on peut ecouter plusieurs
    /// options, se raviser, puis trancher. Soumettre au premier tap privait
    /// l'apprenant de l'ecoute comparative, qui est tout l'interet.
    private var validateButton: some View {
        Button {
            submittedIndex = selectedIndex
        } label: {
            Text("Grammar.Validate")
                .ikeruScaledFont(15, weight: .semibold, relativeTo: .body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .ikeruButtonStyle(.primary)
        .accessibilityIdentifier("grammar.validate")
    }

    // MARK: - Reveal

    private var revealFooter: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // La phrase complète, à entendre — et JAMAIS avant d'avoir répondu :
            // l'audio prononce l'élément manquant, donc le proposer plus tôt
            // donnerait la réponse. Après coup c'est l'inverse : entendre le
            // motif entier, au bon rythme, est ce qui l'installe.
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Text(completedSentence)
                    .ikeruScaledFont(17, weight: .regular, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ListenButton(text: completedSentence, diameter: 36, glyphSize: 13)
            }
            .padding(IkeruTheme.Spacing.sm)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))

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
