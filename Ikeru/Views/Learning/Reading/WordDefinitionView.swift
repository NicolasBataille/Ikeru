import SwiftUI
import IkeruCore

// MARK: - WordDefinitionView

/// A compact popup showing the definition of a tapped word.
/// Displays the word, its reading (furigana), and English meaning.
struct WordDefinitionView: View {

    let word: PassageWord
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            // Word with furigana
            wordDisplay

            // Divider — gold sumi rail
            Rectangle()
                .fill(TatamiTokens.goldDim.opacity(0.18))
                .frame(height: 1)

            // Meaning
            Text(word.meaning)
                .font(.ikeruBody)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Known status badge
            if word.containsKanji {
                knownBadge
            }
        }
        .frame(maxWidth: 280)
        .tatamiRoom(.standard)
    }

    // MARK: - Word Display

    private var wordDisplay: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            if let reading = word.reading {
                Text(reading)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            Text(word.text)
                .font(
                    word.containsKanji
                        ? .custom(
                            IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                            size: IkeruTheme.Typography.Size.kanjiMedium
                        )
                        : .ikeruHeading1
                )
                .foregroundStyle(Color.ikeruKanjiText)
        }
    }

    // MARK: - Known Badge

    private var knownBadge: some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Image(systemName: word.isKnown ? "checkmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 12))
            Text(word.isKnown ? "Known" : "New")
                .font(.ikeruCaption)
        }
        .foregroundStyle(Color.ikeruPrimaryAccent)
        .padding(.horizontal, IkeruTheme.Spacing.sm)
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .overlay(
            Rectangle()
                .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview("WordDefinitionView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.lg) {
            WordDefinitionView(
                word: PassageWord(
                    text: "学校",
                    reading: "がっこう",
                    meaning: "school",
                    isKnown: false,
                    containsKanji: true
                ),
                onDismiss: {}
            )

            WordDefinitionView(
                word: PassageWord(
                    text: "食べます",
                    reading: "たべます",
                    meaning: "to eat",
                    isKnown: true,
                    containsKanji: true
                ),
                onDismiss: {}
            )
        }
    }
    .preferredColorScheme(.dark)
}
