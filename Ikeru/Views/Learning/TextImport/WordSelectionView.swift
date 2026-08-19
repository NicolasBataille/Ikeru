import SwiftUI
import IkeruCore

// MARK: - WordSelectionView

/// Le geste central de la feature : l'apprenant **choisit** ce qu'il garde.
///
/// ## Pourquoi il n'y a pas de bouton « tout ajouter »
///
/// La vision le nomme comme un anti-modèle explicite — « add 95 % of the words
/// you see » est le chemin direct vers la dette de révisions. Le plafond de
/// suggestion pré-coche les premiers mots (ceux dont la phrase est déjà la
/// mieux comprise, esprit i+1) ; tout le reste est listé, décoché, à un tap.
/// Rien n'est verrouillé, rien n'est ajouté sans consentement.
///
/// ## Le miroir, pas le reproche
///
/// Le taux de couverture se lit « tu connais déjà 78 % de ce texte ». Quand il
/// n'est pas mesurable — texte sans mot de contenu — on n'affiche **rien** :
/// inventer 0 % serait un reproche adressé à quelqu'un qui n'a rien fait de
/// mal.
struct WordSelectionView: View {

    @Bindable var viewModel: TextImportViewModel

    /// Garde-fou de réentrance : `save()` crée une entrée de vocabulaire par
    /// mot coché et n'a pas de verrou interne, donc un double tap créerait des
    /// doublons.
    @State private var isSaving = false

    private var words: [AnalyzedToken] { viewModel.unknownWords }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                    coverageHeader
                    // « Les premiers sont déjà cochés » n'a de sens que s'il y
                    // a une liste : au-dessus d'un état vide, la phrase
                    // annonçait des cases à cocher qui n'existent pas.
                    if !words.isEmpty { intro }

                    if words.isEmpty {
                        // Deux vides très différents, deux messages : « tu
                        // connais tout » n'est vrai que si l'app a reconnu
                        // quelque chose.
                        if viewModel.coverage == nil {
                            nothingRecognized
                        } else {
                            nothingUnknown
                        }
                    } else {
                        wordList
                    }

                    // Le pied flotte AU-DESSUS de la liste : sans cette
                    // réserve, le dernier mot reste caché dessous et ne peut
                    // pas être décoché. Mesuré sur simulateur — le compteur et
                    // le bouton masquaient la quatrième ligne.
                    Spacer(minLength: 150)
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.md)
            }

            VStack {
                Spacer()
                footer
            }
        }
        .navigationTitle("TextImport.Selection.Title")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Coverage

    /// Rien du tout quand `coverage` est `nil` — pas de « 0 % », pas de tiret.
    @ViewBuilder
    private var coverageHeader: some View {
        if let coverage = viewModel.coverage {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                Text("TextImport.Selection.CoverageKicker")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text("TextImport.Selection.Coverage \(Int((coverage * 100).rounded()))")
                    .font(.ikeruHeading2)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                coverageBar(coverage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tatamiRoom(.standard)
        }
    }

    private func coverageBar(_ coverage: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.75))
                    .frame(width: geometry.size.width * min(max(coverage, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - Intro

    private var intro: some View {
        Text("TextImport.Selection.Intro")
            .font(.ikeruCaption)
            .foregroundStyle(Color.ikeruTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `coverage == nil` veut dire : **aucun mot de contenu reconnu**, pas
    /// « tout connu ». Afficher « tu connais déjà tous les mots d'ici » sur un
    /// texte que le dictionnaire n'a pas su lire — argot, noms propres, OCR
    /// approximatif — serait une félicitation inventée. On dit ce qui s'est
    /// passé, et ce que l'apprenant peut en faire.
    private var nothingRecognized: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "questionmark.text.page")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("TextImport.Selection.NothingRecognized")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
    }

    private var nothingUnknown: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.ikeruTertiaryAccent)
            Text("TextImport.Selection.NothingUnknown")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
    }

    // MARK: - Word list

    private var wordList: some View {
        LazyVStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, token in
                // La liste ne se coupe pas : elle se commente. Ce qui suit le
                // plafond est présenté comme « la suite si tu en veux », jamais
                // comme un reliquat qu'on aurait dû prendre.
                if index == TextImportViewModel.suggestionCap {
                    beyondCapDivider
                }
                wordRow(token)
            }
        }
    }

    private var beyondCapDivider: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Rectangle()
                .fill(TatamiTokens.goldDim.opacity(0.25))
                .frame(height: 1)
            Text("TextImport.Selection.BeyondCap")
                .font(.ikeruMicro)
                .foregroundStyle(Color.ikeruTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(TatamiTokens.goldDim.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, IkeruTheme.Spacing.sm)
    }

    private func wordRow(_ token: AnalyzedToken) -> some View {
        let isSelected = viewModel.isSelected(token)
        return Button {
            viewModel.toggle(token)
        } label: {
            HStack(alignment: .top, spacing: IkeruTheme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? Color.ikeruPrimaryAccent : Color.ikeruTextTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    wordHeadline(token)
                    glossLine(token)
                    contextLine(token)
                }

                Spacer(minLength: 0)
            }
            .padding(IkeruTheme.Spacing.md)
            .background {
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.07 : 0.03))
                    .overlay {
                        Rectangle().strokeBorder(
                            isSelected ? TatamiTokens.goldDim.opacity(0.55)
                                       : TatamiTokens.goldDim.opacity(0.18),
                            lineWidth: 0.5
                        )
                    }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func wordHeadline(_ token: AnalyzedToken) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IkeruTheme.Spacing.xs) {
            Text(token.dictionaryForm ?? token.surface)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruTextPrimary)
            if let reading = token.entry?.reading, !reading.isEmpty {
                Text(reading)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }
    }

    /// Une gloss anglaise se dit anglaise. Environ un quart des mots d'un texte
    /// réel n'a pas de traduction française dans les données embarquées : la
    /// servir en silence ferait croire à du français mal écrit.
    private func glossLine(_ token: AnalyzedToken) -> some View {
        HStack(alignment: .top, spacing: IkeruTheme.Spacing.xs) {
            if let entry = token.entry {
                // Une chaîne française VIDE compte comme absente, exactement
                // comme dans `WordDetailSheet.gloss(_:)`. Les deux écrans
                // montrent la même donnée et divergeaient : ici `== nil`
                // laissait passer `""`, ce qui affichait une ligne de gloss
                // vide, sans badge et sans sens. Aucune ligne de la base
                // livrée n'est dans ce cas (mesuré : 0 sur 218 498) — c'est
                // une divergence latente qu'on ferme, pas une panne vécue.
                if entry.glossFR?.isEmpty != false {
                    Text(verbatim: "EN")
                        .ikeruScaledFont(9, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.6), lineWidth: 0.5)
                        }
                        .accessibilityLabel("TextImport.Gloss.EnglishBadge")
                }
                Text(verbatim: entry.glossFR.flatMap { $0.isEmpty ? nil : $0 } ?? entry.glossEN)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Ne devrait pas arriver — un mot « apprenable » a une entrée —
                // mais on le dit plutôt que d'afficher un vide.
                Text("TextImport.Gloss.Unavailable")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
    }

    /// La phrase d'origine, celle-là même que la carte SRS gardera.
    @ViewBuilder
    private func contextLine(_ token: AnalyzedToken) -> some View {
        if let analysis = viewModel.analysis {
            let sentence = TextImportViewModel.sentence(containing: token, in: analysis)
            if !sentence.isEmpty {
                Text(sentence)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .lineLimit(2)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("TextImport.Selection.Kept \(viewModel.selectedCount)")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)

            Button {
                save()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.ikeruBackground)
                    }
                    Text("TextImport.Selection.Save")
                }
            }
            .ikeruButtonStyle(.primary)
            .disabled(isSaving)
            .accessibilityIdentifier("textImport.save")
            .opacity(isSaving ? 0.6 : 1)
        }
        .padding(IkeruTheme.Spacing.md)
        .background {
            Rectangle()
                .fill(Color.ikeruBackground.opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TatamiTokens.goldDim.opacity(0.25))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .ikeruTabBarClearance()
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await viewModel.save()
            isSaving = false
        }
    }
}
