import SwiftUI
import IkeruCore

// MARK: - ReadingsView

/// Displays on'yomi and kun'yomi readings for a kanji.
struct ReadingsView: View {

    let onReadings: [String]
    let kunReadings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            readingSection(title: "On'yomi", readings: onReadings)
            readingSection(title: "Kun'yomi", readings: kunReadings)
        }
    }

    // MARK: - Subviews

    private func readingSection(title: String, readings: [String]) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text(title)
                .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .semibold))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.primaryAccent)
                )

            if readings.isEmpty {
                Text("-")
                    .font(.system(size: IkeruTheme.Typography.Size.body))
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
            } else {
                Text(readings.joined(separator: ", "))
                    .font(.system(size: IkeruTheme.Typography.Size.body))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))
            }
        }
    }
}
