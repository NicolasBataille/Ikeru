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
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, weight: .bold, relativeTo: .body)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))

                Text("(\(vocab.reading))")
                    .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
            }

            Text(vocab.meaning)
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption2)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

            if !vocab.exampleSentences.isEmpty {
                ForEach(vocab.exampleSentences, id: \.self) { sentence in
                    Text(sentence)
                        .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption2)
                        .foregroundStyle(
                            Color(hex: IkeruTheme.Colors.textPrimary)
                                .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                        )
                        .padding(.leading, IkeruTheme.Spacing.sm)
                }
            }
        }
        .tatamiRoom(.standard)
    }

    private var showMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: IkeruTheme.Animation.standardDuration)) {
                showAll = true
            }
        } label: {
            Text("Show more (\(vocabulary.count - Self.initialDisplayLimit) remaining)")
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, weight: .medium, relativeTo: .caption2)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                .frame(maxWidth: .infinity)
                .padding(.vertical, IkeruTheme.Spacing.sm)
        }
    }

    private var emptyState: some View {
        Text("No vocabulary found")
            .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            .foregroundStyle(
                Color(hex: IkeruTheme.Colors.textPrimary)
                    .opacity(IkeruTheme.Colors.textSecondaryOpacity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
