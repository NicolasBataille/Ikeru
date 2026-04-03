import SwiftUI
import IkeruCore

// MARK: - VocabularyExamplesView

/// Displays vocabulary items that use a kanji, with example sentences.
struct VocabularyExamplesView: View {

    let vocabulary: [Vocabulary]

    /// Maximum items shown before "Show more" is required.
    private static let initialDisplayLimit = 5

    @State private var showAll = false

    private var displayedVocabulary: [Vocabulary] {
        if showAll || vocabulary.count <= Self.initialDisplayLimit {
            return vocabulary
        }
        return Array(vocabulary.prefix(Self.initialDisplayLimit))
    }

    private var hasMore: Bool {
        !showAll && vocabulary.count > Self.initialDisplayLimit
    }

    var body: some View {
        if vocabulary.isEmpty {
            emptyState
        } else {
            vocabularyList
        }
    }

    // MARK: - Subviews

    private var vocabularyList: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            ForEach(displayedVocabulary) { vocab in
                vocabularyCard(vocab)
            }

            if hasMore {
                showMoreButton
            }
        }
    }

    private func vocabularyCard(_ vocab: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Text(vocab.word)
                    .font(.system(size: IkeruTheme.Typography.Size.body, weight: .bold))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))

                Text("(\(vocab.reading))")
                    .font(.system(size: IkeruTheme.Typography.Size.body))
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
            }

            Text(vocab.meaning)
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

            if !vocab.exampleSentences.isEmpty {
                ForEach(vocab.exampleSentences, id: \.self) { sentence in
                    Text(sentence)
                        .font(.system(size: IkeruTheme.Typography.Size.caption))
                        .foregroundStyle(
                            Color(hex: IkeruTheme.Colors.textPrimary)
                                .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                        )
                        .padding(.leading, IkeruTheme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ikeruCard(.standard)
    }

    private var showMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: IkeruTheme.Animation.standardDuration)) {
                showAll = true
            }
        } label: {
            Text("Show more (\(vocabulary.count - Self.initialDisplayLimit) remaining)")
                .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .medium))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                .frame(maxWidth: .infinity)
                .padding(.vertical, IkeruTheme.Spacing.sm)
        }
    }

    private var emptyState: some View {
        Text("No vocabulary found")
            .font(.system(size: IkeruTheme.Typography.Size.body))
            .foregroundStyle(
                Color(hex: IkeruTheme.Colors.textPrimary)
                    .opacity(IkeruTheme.Colors.textSecondaryOpacity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
