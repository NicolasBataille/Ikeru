import SwiftUI
import IkeruCore

// MARK: - RadicalDecompositionView

/// Displays radical components of a kanji as horizontal chips.
struct RadicalDecompositionView: View {

    let radicals: [Radical]

    var body: some View {
        if radicals.isEmpty {
            emptyState
        } else {
            radicalChips
        }
    }

    // MARK: - Subviews

    private var radicalChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: IkeruTheme.Spacing.sm) {
                ForEach(radicals) { radical in
                    radicalChip(radical)
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.xs)
        }
    }

    private func radicalChip(_ radical: Radical) -> some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text(radical.character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.kanjiMedium
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))

            Text(radical.meaning)
                .ikeruScaledFont(IkeruTheme.Typography.Size.caption, relativeTo: .caption2)
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
                .lineLimit(1)
        }
        .frame(minWidth: 64)
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .background {
            Rectangle()
                .strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1)
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
    }

    private var emptyState: some View {
        Text("No radicals found")
            .ikeruScaledFont(IkeruTheme.Typography.Size.body, relativeTo: .body)
            .foregroundStyle(
                Color(hex: IkeruTheme.Colors.textPrimary)
                    .opacity(IkeruTheme.Colors.textSecondaryOpacity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
