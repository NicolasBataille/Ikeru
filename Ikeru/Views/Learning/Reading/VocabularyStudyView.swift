import SwiftUI
import IkeruCore

// MARK: - VocabularyStudyView

/// Displays a vocabulary item with word, reading, meaning, and expandable example sentences.
struct VocabularyStudyView: View {

    let vocabulary: VocabularyExercise

    @State private var showExamples = false

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // JLPT level badge
            jlptBadge

            // Main word card
            wordCard

            // Meaning and part of speech
            meaningSection

            // Expandable example sentences
            if !vocabulary.exampleSentences.isEmpty {
                exampleSentencesSection
            }
        }
        .padding(IkeruTheme.Spacing.md)
    }

    // MARK: - JLPT Badge

    private var jlptBadge: some View {
        Text(vocabulary.jlptLevel.displayName)
            .font(.ikeruCaption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, IkeruTheme.Spacing.sm)
            .padding(.vertical, IkeruTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.8))
            )
    }

    // MARK: - Word Card

    private var wordCard: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(vocabulary.word)
                .font(.kanjiDisplay)
                .foregroundStyle(Color.ikeruKanjiText)

            Text(vocabulary.reading)
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
        .ikeruCard(.elevated)
    }

    // MARK: - Meaning Section

    private var meaningSection: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            if !vocabulary.partOfSpeech.isEmpty {
                Text(vocabulary.partOfSpeech)
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }

            Text(vocabulary.meaning)
                .font(.ikeruHeading2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Example Sentences

    private var exampleSentencesSection: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Button {
                withAnimation(.spring(duration: IkeruTheme.Animation.standardDuration)) {
                    showExamples.toggle()
                }
            } label: {
                HStack {
                    Text("Example Sentences")
                        .font(.ikeruHeading3)
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: showExamples ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.ikeruTextSecondary)
                        .font(.ikeruBody)
                }
                .padding(.horizontal, IkeruTheme.Spacing.sm)
            }
            .buttonStyle(.plain)

            if showExamples {
                VStack(spacing: IkeruTheme.Spacing.md) {
                    ForEach(vocabulary.exampleSentences) { sentence in
                        ExampleSentenceRow(sentence: sentence)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .ikeruCard(.standard)
    }
}

// MARK: - ExampleSentenceRow

private struct ExampleSentenceRow: View {

    let sentence: ExampleSentence

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text(sentence.japanese)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                    size: IkeruTheme.Typography.Size.body
                ))
                .foregroundStyle(Color.ikeruKanjiText)

            if !sentence.reading.isEmpty {
                Text(sentence.reading)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            Text(sentence.english)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                .fill(Color.ikeruSurface.opacity(0.5))
        )
    }
}
