import SwiftUI
import IkeruCore

// MARK: - ReadingPassageView

/// Displays a graded reading passage with furigana annotations.
/// Known kanji show plain text; unknown kanji show furigana above.
/// Tapping any word reveals its definition.
struct ReadingPassageView: View {

    @State private var viewModel: ReadingPassageViewModel
    let level: JLPTLevel

    init(level: JLPTLevel, cardRepository: CardRepository) {
        self.level = level
        self._viewModel = State(
            initialValue: ReadingPassageViewModel(cardRepository: cardRepository)
        )
    }

    var body: some View {
        ZStack {
            Color.ikeruBackground.ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let passage = viewModel.currentPassage {
                passageContent(passage)
            }
        }
        .task {
            await viewModel.loadPassage(for: level)
        }
        .overlay {
            if let word = viewModel.selectedWord {
                wordDefinitionOverlay(word: word)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            ProgressView()
                .tint(Color.ikeruPrimaryAccent)
            Text("Loading passage...")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Passage Content

    private func passageContent(_ passage: ReadingPassage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                passageHeader(passage)

                ForEach(Array(passage.sentences.enumerated()), id: \.element.id) { index, sentence in
                    sentenceBlock(sentence, index: index)
                }

                furiganaLegend
            }
            .padding(IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Header

    private func passageHeader(_ passage: ReadingPassage) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            // JLPT level badge — encre rectangle, no capsule
            Text(passage.jlptLevel.displayLabel)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .tracking(1.2)
                .padding(.horizontal, IkeruTheme.Spacing.sm)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .overlay(
                    Rectangle()
                        .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                )

            // Title
            Text(passage.title)
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            // Reading skill color bar — 2pt gold rail, Tatami style
            Rectangle()
                .fill(Color.ikeruPrimaryAccent)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sentence Block

    private func sentenceBlock(_ sentence: PassageSentence, index: Int) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            // Sentence number
            Text("Sentence \(index + 1)")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            // Japanese text with furigana
            WrappingHStack(sentence: sentence, viewModel: viewModel)
                .tatamiRoom(.standard)

            // Translation toggle
            translationButton(sentence: sentence, index: index)
        }
    }

    // MARK: - Translation Button

    private func translationButton(sentence: PassageSentence, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: IkeruTheme.Animation.quickDuration)) {
                viewModel.toggleTranslation(for: index)
            }
        } label: {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                Image(systemName: viewModel.translationSentenceIndex == index
                    ? "eye.fill"
                    : "eye.slash"
                )
                .font(.system(size: 12))

                Text(viewModel.translationSentenceIndex == index
                    ? sentence.english
                    : "Show translation"
                )
                .font(.ikeruCaption)
            }
            .foregroundStyle(.ikeruTextSecondary)
            .padding(.horizontal, IkeruTheme.Spacing.sm)
        }
    }

    // MARK: - Furigana Legend

    private var furiganaLegend: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("Reading Guide")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            HStack(spacing: IkeruTheme.Spacing.md) {
                legendItem(
                    color: TatamiTokens.goldDim,
                    label: "Known kanji (no furigana)"
                )
                legendItem(
                    color: Color.ikeruPrimaryAccent,
                    label: "New kanji (with furigana)"
                )
            }
        }
        .padding(.top, IkeruTheme.Spacing.md)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .ikeruScaledFont(11, relativeTo: .caption2)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Word Definition Overlay

    private func wordDefinitionOverlay(word: PassageWord) -> some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: IkeruTheme.Animation.quickDuration)) {
                        viewModel.dismissWordDefinition()
                    }
                }

            // Definition popup
            WordDefinitionView(word: word) {
                viewModel.dismissWordDefinition()
            }
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(duration: IkeruTheme.Animation.standardDuration), value: word.id)
    }
}

// MARK: - WrappingHStack

/// A flow layout that wraps words horizontally, supporting furigana annotations.
private struct WrappingHStack: View {

    let sentence: PassageSentence
    let viewModel: ReadingPassageViewModel

    var body: some View {
        IkeruFlowLayout(spacing: 2) {
            ForEach(sentence.words) { word in
                FuriganaWordView(
                    word: word,
                    showFurigana: viewModel.shouldShowFurigana(for: word)
                )
                .onTapGesture {
                    guard !isPunctuation(word.text) else { return }
                    viewModel.selectWord(word)
                }
            }
        }
    }

    private func isPunctuation(_ text: String) -> Bool {
        let punctuation: Set<String> = ["。", "、", "！", "？", "「", "」", "（", "）", ".", ","]
        return punctuation.contains(text)
    }
}

// MARK: - FuriganaWordView

/// Renders a single word with optional furigana above it.
private struct FuriganaWordView: View {

    let word: PassageWord
    let showFurigana: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Furigana reading above
            if showFurigana, let reading = word.reading {
                Text(reading)
                    .ikeruScaledFont(9, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.8))
            } else {
                // Reserve space for alignment consistency
                Text(" ")
                    .ikeruScaledFont(9, relativeTo: .caption2)
                    .hidden()
            }

            // Main word text
            if word.containsKanji {
                Text(word.text)
                    .font(.custom(
                        IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                        size: IkeruTheme.Typography.Size.heading3
                    ))
                    .foregroundStyle(wordColor)
            } else {
                Text(word.text)
                    .ikeruScaledFont(IkeruTheme.Typography.Size.heading3, relativeTo: .title3)
                    .foregroundStyle(wordColor)
            }
        }
    }

    private var wordColor: Color {
        if word.containsKanji {
            return word.isKnown ? Color.ikeruKanjiText : Color.ikeruPrimaryAccent
        }
        return Color.ikeruKanjiText
    }
}

// MARK: - Preview

#Preview("ReadingPassageView") {
    // Create a mock passage for preview
    let passage = ReadingPassageViewModel.buildSamplePassage(
        level: .n5,
        knownKanji: ["七", "行"]
    )

    ScrollView {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
            Text(passage.title)
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            ForEach(passage.sentences) { sentence in
                IkeruFlowLayout(spacing: 2) {
                    ForEach(sentence.words) { word in
                        FuriganaWordView(
                            word: word,
                            showFurigana: word.containsKanji && !word.isKnown && word.reading != nil
                        )
                    }
                }
                .tatamiRoom(.standard)
            }
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
