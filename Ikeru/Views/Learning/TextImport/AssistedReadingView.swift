import SwiftUI
import IkeruCore

// MARK: - AssistedReadingView
//
// La lecture assistée d'« apporte ton propre texte » : le texte de
// l'apprenant, redessiné au caractère près, chaque mot tappable.
//
// ## Pourquoi pas `KanaRubyText`
//
// `KanaRubyText` est l'outil furigana du repo, et il ne convient pas ici pour
// deux raisons de fond, pas de style :
//
// 1. Il lit ses lectures DANS la chaîne, au format `漢字(かんじ)` que Sakura
//    produit. Les nôtres viennent du dictionnaire (`token.entry?.reading`) ;
//    les injecter dans le texte pour qu'il les retrouve reviendrait à
//    réécrire le texte de l'apprenant pour l'afficher — exactement ce que la
//    feature promet de ne jamais faire.
// 2. Il rend du texte, pas des cibles de tap. Ici chaque mot est un `Button`
//    qui ouvre sa fiche, et les mots inconnus portent un soulignement : deux
//    décisions par token, or `KanaRubyText` ne voit qu'une chaîne.
//
// Ce qui lui est repris, en revanche : `IkeruFlowLayout` à spacing 0, la
// ligne de ruby réservée en hauteur même quand elle est vide (sans quoi les
// mots d'une même ligne ne s'alignent pas), et le découpage des runs latins
// après chaque espace pour que le flow puisse couper entre les mots.

/// Affiche un `AnalyzedText` : texte intact, mots tappables, furigana à la
/// demande, inconnus discrètement soulignés.
///
/// Se câble sur `TextImportViewModel` avec des littéraux de closure :
/// ```swift
/// AssistedReadingView(
///     analysis: analysis,
///     knownForms: viewModel.knownForms,
///     isSelected: { viewModel.isSelected($0) },
///     onLearn: { viewModel.toggle($0) }
/// )
/// ```
struct AssistedReadingView: View {

    let analysis: AnalyzedText

    /// Les formes du dictionnaire que l'apprenant connaît déjà.
    let knownForms: Set<String>

    /// Le mot est-il déjà retenu pour cet import ? Sert à l'état du bouton de
    /// la fiche, jamais au rendu du texte : la lecture reste une lecture.
    var isSelected: (AnalyzedToken) -> Bool = { _ in false }

    /// Appelé quand l'apprenant retient (ou retire) un mot depuis sa fiche.
    ///
    /// `nil` — la valeur par défaut — n'est pas « ne rien faire » : la fiche
    /// n'affiche alors PAS de bouton « apprendre ». Un bouton branché sur une
    /// closure vide est pire que pas de bouton ; l'apprenant croit avoir
    /// retenu le mot et découvre le contraire à la fin de l'import.
    var onLearn: ((AnalyzedToken) -> Void)? = nil

    /// Tailles fixes, comme `KanaRubyText` : la ligne de ruby et la ligne de
    /// base doivent garder un rapport constant pour que le flow s'aligne.
    var baseFont: Font = .system(size: 19, weight: .regular)
    var rubyFont: Font = .system(size: 10.5, weight: .medium, design: .rounded)

    /// Furigana masqués au départ : la vision les veut « à la demande, pas
    /// imposés ». Un lecteur qui les voit toujours ne lit plus les kanji.
    @State private var showFurigana = false

    @State private var tappedToken: AnalyzedToken?

    private var lines: [ReadingLine] { ReadingLine.build(from: analysis.tokens) }

    private var hasUnknownWords: Bool {
        analysis.tokens.contains(where: isUnknown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            furiganaToggle
            textBody
            if hasUnknownWords { legend }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $tappedToken) { token in
            WordDetailSheet(
                token: token,
                isKnown: isKnown(token),
                isSelected: isSelected(token),
                onLearn: learnAction(for: token)
            )
        }
    }

    // MARK: - Furigana toggle

    private var furiganaToggle: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: IkeruTheme.Animation.quickDuration)) {
                    showFurigana.toggle()
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Image(systemName: showFurigana ? "eye.fill" : "eye.slash")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Furigana")
                        .ikeruScaledFont(12, weight: .medium, relativeTo: .caption)
                }
                .foregroundStyle(showFurigana ? Color.ikeruPrimaryAccent : Color.ikeruTextTertiary)
                .padding(.horizontal, IkeruTheme.Spacing.sm)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .overlay(
                    Capsule().strokeBorder(
                        (showFurigana ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim).opacity(0.5),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Furigana"))
            .accessibilityHint(Text("Show or hide the readings above the kanji"))
            .accessibilityAddTraits(showFurigana ? [.isSelected] : [])
        }
    }

    // MARK: - Le texte

    private var textBody: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            ForEach(lines) { line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: ReadingLine) -> some View {
        if line.segments.isEmpty {
            // Une ligne vide du texte source reste une ligne vide. Un
            // `IkeruFlowLayout` sans enfant a une hauteur nulle : sans ce
            // fantôme, le blanc voulu par l'apprenant disparaîtrait.
            Text(verbatim: " ")
                .font(baseFont)
                .hidden()
                .accessibilityHidden(true)
        } else {
            IkeruFlowLayout(spacing: 0) {
                ForEach(line.segments) { segment in
                    segmentView(segment)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: ReadingSegment) -> some View {
        if let token = segment.token {
            Button {
                tappedToken = token
            } label: {
                wordLabel(token)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: token.surface))
            .accessibilityHint(Text("Open the word details"))
        } else {
            // Ponctuation, espaces, chiffres : rendus tels quels, un peu plus
            // discrets que les mots, et jamais tappables.
            stackedRun(segment.text, color: Color.ikeruTextSecondary)
        }
    }

    private func wordLabel(_ token: AnalyzedToken) -> some View {
        VStack(spacing: 1) {
            if showFurigana { rubyRow(for: token) }
            Text(verbatim: token.surface)
                .font(baseFont)
                .foregroundStyle(Color.ikeruKanjiText)
                // Le soulignement ne court que sous la ligne de base : sur la
                // pile entière il passerait sous les furigana.
                .overlay(alignment: .bottom) { unknownUnderline(token) }
        }
        .padding(.horizontal, 0.5)
        .contentShape(Rectangle())
    }

    private func stackedRun(_ text: String, color: Color) -> some View {
        VStack(spacing: 1) {
            if showFurigana { rubySpacer }
            Text(verbatim: text)
                .font(baseFont)
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func rubyRow(for token: AnalyzedToken) -> some View {
        if let reading = furigana(for: token) {
            Text(verbatim: reading)
                .font(rubyFont)
                .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                // Le mot entier porte déjà son label VoiceOver ; la lecture
                // relue à part ferait doublon.
                .accessibilityHidden(true)
        } else {
            rubySpacer
        }
    }

    private var rubySpacer: some View {
        Text(verbatim: " ")
            .font(rubyFont)
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
    }

    // MARK: - Décisions par token

    /// La lecture posée au-dessus est celle de la FORME DU DICTIONNAIRE
    /// (ふる pour 降っています), pas celle de la surface fléchie. C'est une
    /// limite des données — JMdict ne porte pas la lecture des conjugaisons —
    /// et non un oubli : la fiche ouverte au tap montre les deux formes côte
    /// à côte, ce qui rend l'écart lisible plutôt que trompeur.
    ///
    /// Furigana sur les kanji seulement : jamais de kana au-dessus de kana,
    /// jamais de romaji.
    private func furigana(for token: AnalyzedToken) -> String? {
        guard let reading = token.entry?.reading, !reading.isEmpty,
              reading != token.surface,
              token.surface.contains(where: { $0.isCJK }) else { return nil }
        return reading
    }

    @ViewBuilder
    private func unknownUnderline(_ token: AnalyzedToken) -> some View {
        if isUnknown(token) {
            Rectangle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.55))
                .frame(height: 1.5)
                .offset(y: 1)
        }
    }

    /// Un mot « pas encore appris » : apprenable et absent du dictionnaire de
    /// l'apprenant.
    ///
    /// Un mot que le dictionnaire ne connaît pas n'est PAS souligné. Le
    /// soulignement dit « à apprendre » ; le mettre sous un mot dont l'app ne
    /// sait rien serait une promesse qu'elle ne peut pas tenir. Il reste
    /// tappable, et sa fiche le dit.
    private func isUnknown(_ token: AnalyzedToken) -> Bool {
        guard token.isLearnable, let form = token.dictionaryForm else { return false }
        return !knownForms.contains(form)
    }

    /// L'action « apprendre » de la fiche, ou `nil` quand l'écran hôte n'en
    /// propose pas.
    private func learnAction(for token: AnalyzedToken) -> (() -> Void)? {
        guard let onLearn else { return nil }
        return { onLearn(token) }
    }

    private func isKnown(_ token: AnalyzedToken) -> Bool {
        guard let form = token.dictionaryForm else { return false }
        return knownForms.contains(form)
    }

    private var legend: some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Rectangle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.55))
                .frame(width: 14, height: 1.5)
            Text("Underlined: a word you have not learned yet")
                .ikeruScaledFont(11, relativeTo: .caption2)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Découpage en lignes

/// Un morceau de ligne : soit un mot (avec son token), soit un run de
/// caractères entre les mots.
private struct ReadingSegment: Identifiable {
    let id: Int
    /// Le token quand le morceau est un mot ; `nil` pour ce qui vit entre eux.
    let token: AnalyzedToken?
    let text: String
}

/// Une ligne visuelle. `segments` vide = ligne blanche du texte source.
private struct ReadingLine: Identifiable {
    let id: Int
    let segments: [ReadingSegment]

    /// Découpe la liste de tokens en lignes, sans rien perdre.
    ///
    /// Deux raisons, une seule passe :
    ///
    /// - `IkeruFlowLayout` ne casse pas sur un saut de ligne : rendu en texte,
    ///   il y occupe une case comme une autre et disparaît. Les sauts du
    ///   texte source deviennent donc des lignes du `VStack`. Rien n'est
    ///   perdu : le `\n` EST la coupure qu'il dessine.
    /// - Un long run latin est incassable pour le flow, qui le laisse déborder
    ///   (et le débordement décale toute la ligne). On le recoupe après chaque
    ///   espace, comme `KanaRubyText`.
    static func build(from tokens: [AnalyzedToken]) -> [ReadingLine] {
        var lines: [ReadingLine] = []
        var segments: [ReadingSegment] = []
        var nextID = 0

        func appendRun(_ run: String) {
            guard !run.isEmpty else { return }
            var chunk = ""
            for character in run {
                chunk.append(character)
                if character == " " {
                    segments.append(ReadingSegment(id: nextID, token: nil, text: chunk))
                    nextID += 1
                    chunk = ""
                }
            }
            if !chunk.isEmpty {
                segments.append(ReadingSegment(id: nextID, token: nil, text: chunk))
                nextID += 1
            }
        }

        func closeLine() {
            lines.append(ReadingLine(id: lines.count, segments: segments))
            segments = []
        }

        for token in tokens {
            guard !token.isWord else {
                segments.append(ReadingSegment(id: nextID, token: token, text: token.surface))
                nextID += 1
                continue
            }
            var run = ""
            for character in token.surface {
                if character == "\n" {
                    appendRun(run)
                    run = ""
                    closeLine()
                } else {
                    run.append(character)
                }
            }
            appendRun(run)
        }
        closeLine()
        return lines
    }
}

// MARK: - Preview

#Preview("AssistedReadingView") {
    let today = DictionaryEntry(id: 1, reading: "きょう", partsOfSpeech: ["n"],
                                glossFR: "aujourd'hui", glossEN: "today", isCommon: true)
    let rain = DictionaryEntry(id: 2, reading: "あめ", partsOfSpeech: ["n"],
                               glossFR: nil, glossEN: "rain", isCommon: true)
    let tokens = [
        AnalyzedToken(id: 0, surface: "今日", isWord: true, dictionaryForm: "今日", entry: today),
        AnalyzedToken(id: 1, surface: "は", isWord: true),
        AnalyzedToken(id: 2, surface: "雨", isWord: true, dictionaryForm: "雨", entry: rain),
        AnalyzedToken(id: 3, surface: "。", isWord: false),
    ]

    ScrollView {
        AssistedReadingView(
            analysis: AnalyzedText(source: "今日は雨。", tokens: tokens),
            knownForms: ["今日"]
        )
        .padding(IkeruTheme.Spacing.lg)
    }
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
