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
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
                .lineLimit(1)
        }
        .frame(minWidth: 64)
        .ikeruCard(.standard)
    }

    private var emptyState: some View {
        Text("No radicals found")
            .font(.system(size: IkeruTheme.Typography.Size.body))
            .foregroundStyle(
                Color(hex: IkeruTheme.Colors.textPrimary)
                    .opacity(IkeruTheme.Colors.textSecondaryOpacity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
