import SwiftUI
import IkeruCore

// MARK: - GrammarPointView

/// Displays a grammar point with title, explanation, and examples.
/// Clean, readable layout with JLPT level badge.
struct GrammarPointView: View {

    let grammarPoint: GrammarPoint

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // Header with JLPT badge and title
            headerSection

            // Explanation
            explanationSection

            // Examples
            if !grammarPoint.examples.isEmpty {
                examplesSection
            }
        }
        .padding(IkeruTheme.Spacing.md)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(grammarPoint.jlptLevel.displayName)
                .font(.ikeruCaption)
                .fontWeight(.semibold)
                .tracking(1.2)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, IkeruTheme.Spacing.sm)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .overlay(
                    Rectangle()
                        .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                )

            Text(grammarPoint.title)
                .font(.kanjiMedium)
                .foregroundStyle(Color.ikeruKanjiText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .tatamiRoom(.standard, padding: IkeruTheme.Spacing.lg)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Label("Explanation", systemImage: "text.book.closed")
                .font(.ikeruHeading3)
                .foregroundStyle(.white)

            Text(grammarPoint.explanation)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard)
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            Label("Examples", systemImage: "text.quote")
                .font(.ikeruHeading3)
                .foregroundStyle(.white)

            ForEach(Array(grammarPoint.examples.enumerated()), id: \.offset) { _, example in
                Text(example)
                    .font(.custom(
                        IkeruTheme.Typography.FontFamily.kanjiSerifMedium,
                        size: IkeruTheme.Typography.Size.body
                    ))
                    .foregroundStyle(Color.ikeruKanjiText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(IkeruTheme.Spacing.sm)
                    .background(Rectangle().fill(Color.ikeruSurface.opacity(0.35)))
                    .overlay(
                        Rectangle()
                            .strokeBorder(TatamiTokens.goldDim.opacity(0.3), lineWidth: 1)
                    )
                    .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tatamiRoom(.standard)
    }
}
