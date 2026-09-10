import SwiftUI
import IkeruCore

// MARK: - WordDetailSheet
//
// La fiche qui s'ouvre au tap d'un mot dans `AssistedReadingView`.
//
// Elle suit la mise en page de `VocabularyDetailSheet` (NavigationStack,
// detents, salles tatami, bouton collé en bas) pour qu'un mot de SON texte se
// consulte exactement comme un mot d'une conversation Sakura. Ce qu'elle ne
// partage pas avec elle, c'est la source : ici tout vient de l'analyse hors
// ligne, avec ses trous — et les trous se disent.

/// Fiche d'un token analysé : graphie, forme du dictionnaire, lecture,
/// définition, autres sens, et le geste « apprendre ».
struct WordDetailSheet: View {

    let token: AnalyzedToken

    /// Le mot est déjà dans le dictionnaire de l'apprenant.
    var isKnown: Bool = false

    /// Le mot est déjà retenu pour cet import.
    var isSelected: Bool = false

    /// Appelé par « Apprendre ce mot ». Côté `TextImportViewModel` c'est
    /// `toggle(_:)`, donc le bouton bascule au lieu d'empiler.
    ///
    /// `nil` = fiche en lecture seule : aucun bouton n'est rendu. Un écran qui
    /// ne sait pas quoi faire du mot ne doit pas promettre de l'apprendre.
    let onLearn: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var alternativesExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ikeruBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: IkeruTheme.Spacing.lg) {
                        header
                        if let entry = token.entry {
                            definitionSection(entry)
                            if !token.alternatives.isEmpty { alternativesSection }
                            if !token.isLearnable { grammarNote }
                        } else {
                            // « rien d'autre » : pas de définition inventée,
                            // pas de bouton d'écoute sur une lecture qu'on
                            // n'a pas, pas de carte à créer.
                            unavailableSection
                        }
                        // 100, comme `VocabularyDetailSheet` : le dégradé du
                        // bouton collé fait 80 pt, une réserve plus courte
                        // laisse la dernière ligne passer dessous.
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.lg)
                    .padding(.top, IkeruTheme.Spacing.lg)
                }

                if token.isLearnable, onLearn != nil {
                    VStack {
                        Spacer()
                        actionSection
                            .padding(.horizontal, IkeruTheme.Spacing.lg)
                            .padding(.bottom, IkeruTheme.Spacing.lg)
                            .background(
                                LinearGradient(
                                    colors: [Color.ikeruBackground.opacity(0), Color.ikeruBackground],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 80)
                                .allowsHitTesting(false),
                                alignment: .top
                            )
                    }
                }
            }
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            // La graphie TELLE QU'ÉCRITE dans le texte de l'apprenant.
            Text(verbatim: token.surface)
                .font(.system(size: 48, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)

            // Montrée seulement quand elle diffère : sur 雨 « forme du
            // dictionnaire : 雨 » n'apprend rien, sur 降っています si.
            if let form = token.dictionaryForm, form != token.surface {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Text("Dictionary form")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    Text(verbatim: form)
                        .ikeruScaledFont(16, weight: .medium, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let entry = token.entry, !entry.reading.isEmpty {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Text(verbatim: entry.reading)
                        .ikeruScaledFont(24, weight: .medium, design: .rounded, relativeTo: .title2)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    // La LECTURE, pas la graphie — voir la doc de `ListenButton`.
                    ListenButton(text: entry.reading)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.md)
    }

    // MARK: - Définition

    private func definitionSection(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionLabel("Meaning")
            glossRow(entry, font: .ikeruBody, color: Color.ikeruTextPrimary)

            if !entry.partsOfSpeech.isEmpty {
                Text(verbatim: entry.partsOfSpeech.joined(separator: " · "))
                    .ikeruScaledFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard)
    }

    /// La gloss, avec son étiquette de langue quand elle est anglaise.
    ///
    /// Règle produit ferme : `glossFR == nil` est le cas COURANT (7 % des
    /// entrées de JMdict portent du français, 43 % parmi les communes), donc
    /// afficher l'anglais en silence ferait passer de l'anglais pour de la
    /// traduction sur un mot sur quatre d'un texte réel. L'étiquette est le
    /// prix de l'honnêteté du lookup.
    @ViewBuilder
    private func glossRow(_ entry: DictionaryEntry, font: Font, color: Color) -> some View {
        let gloss = Self.gloss(entry)
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            if gloss.isEnglish { englishBadge }
            Text(verbatim: gloss.text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var englishBadge: some View {
        // `verbatim` : « EN » est un code de langue, pas une phrase d'UI. Le
        // traduire n'aurait pas de sens ; VoiceOver, lui, entend la version
        // longue plutôt que « eu-enne ».
        Text(verbatim: "EN")
            .ikeruScaledFont(9, weight: .bold, relativeTo: .caption2)
            .foregroundStyle(Color.ikeruBackground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.ikeruPrimaryAccent.opacity(0.85)))
            .accessibilityLabel(Text("Definition in English"))
    }

    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            sectionLabel("Meaning")
            Text("Definition unavailable offline")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard)
    }

    private var grammarNote: some View {
        Text("Grammar word — nothing to add to your dictionary here.")
            .ikeruScaledFont(12, relativeTo: .caption)
            .foregroundStyle(Color.ikeruTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Autres lectures

    /// Une graphie est souvent plusieurs mots — 生 en compte onze. L'analyseur
    /// en choisit un ; le taire reviendrait à deviner en silence. La section
    /// annonce donc leur nombre même repliée.
    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: IkeruTheme.Animation.quickDuration)) {
                    alternativesExpanded.toggle()
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    sectionLabel("Other readings and meanings")
                    Spacer(minLength: 0)
                    Text(verbatim: "\(token.alternatives.count)")
                        .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruTextTertiary)
                    Image(systemName: alternativesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Other readings and meanings"))
            .accessibilityHint(Text("One spelling is often several words"))
            .accessibilityAddTraits(alternativesExpanded ? [.isSelected] : [])

            if alternativesExpanded {
                ForEach(token.alternatives) { alternative in
                    alternativeRow(alternative)
                }
            } else {
                Text("One spelling is often several words")
                    .ikeruScaledFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard)
    }

    private func alternativeRow(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                Text(verbatim: entry.reading)
                    .ikeruScaledFont(15, weight: .medium, design: .rounded, relativeTo: .body)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Spacer(minLength: 0)
            }
            // Même règle que la définition principale : l'étiquette « EN »
            // suit la gloss anglaise partout, y compris ici.
            glossRow(entry, font: .ikeruCaption, color: Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Action

    /// Rendue seulement quand `token.isLearnable`.
    ///
    /// Pas par prudence esthétique : `TextImportViewModel.save()` ne parcourt
    /// que `analysis.learnableWords`, donc une forme non apprenable cochée ici
    /// serait acceptée par l'UI puis abandonnée en silence à l'enregistrement.
    /// Un bouton qui ne tient pas sa promesse est pire que pas de bouton.
    @ViewBuilder
    private var actionSection: some View {
        if isKnown {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("Already in your dictionary")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, IkeruTheme.Spacing.md)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                onLearn?()
                dismiss()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: isSelected ? "checkmark" : "plus")
                    Text(isSelected ? LocalizedStringKey("Kept for this import")
                                    : LocalizedStringKey("Learn this word"))
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(isSelected ? .secondary : .primary)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.ikeruMicro)
            .ikeruTracking(.micro)
            .textCase(.uppercase)
            .foregroundStyle(Color.ikeruTextTertiary)
    }

    /// La gloss à montrer, et si c'est de l'anglais. Une chaîne française vide
    /// compte comme absente : elle n'apprendrait rien et masquerait l'anglais.
    private static func gloss(_ entry: DictionaryEntry) -> (text: String, isEnglish: Bool) {
        if let french = entry.glossFR, !french.isEmpty { return (french, false) }
        return (entry.glossEN, true)
    }
}

// MARK: - Preview

#Preview("WordDetailSheet — gloss anglaise + alternatives") {
    let rain = DictionaryEntry(id: 1, reading: "ふる", partsOfSpeech: ["v5r", "vi"],
                               glossFR: nil, glossEN: "to fall (rain, snow, etc.)",
                               isCommon: true)
    let other = DictionaryEntry(id: 2, reading: "くだる", partsOfSpeech: ["v5r", "vi"],
                                glossFR: "descendre", glossEN: "to descend", isCommon: true)
    let token = AnalyzedToken(id: 0, surface: "降っています", isWord: true,
                              dictionaryForm: "降る", entry: rain, alternatives: [other])

    WordDetailSheet(token: token, onLearn: {})
        .preferredColorScheme(.dark)
}

#Preview("WordDetailSheet — hors dictionnaire") {
    WordDetailSheet(
        token: AnalyzedToken(id: 0, surface: "ぴえん", isWord: true),
        onLearn: {}
    )
    .preferredColorScheme(.dark)
}
