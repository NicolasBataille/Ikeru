import SwiftUI
import IkeruCore

// MARK: - SessionSummaryView

/// Displays session completion summary: cards reviewed, XP earned, items learned, duration.
struct SessionSummaryView: View {

    let viewModel: SessionViewModel

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            // Completion icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.ikeruSuccess)

            Text("Session Complete!")
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            // Summary cards
            VStack(spacing: IkeruTheme.Spacing.md) {
                summaryRow(
                    icon: "rectangle.stack.fill",
                    label: "Cards Reviewed",
                    value: "\(viewModel.reviewedCount)",
                    valueColor: .white
                )

                summaryRow(
                    icon: "sparkles",
                    label: "New Items Learned",
                    value: "\(viewModel.newItemsLearned)",
                    valueColor: Color.ikeruSuccess
                )

                summaryRow(
                    icon: "star.fill",
                    label: "XP Earned",
                    value: "+\(viewModel.xpEarned)",
                    valueColor: Color.ikeruPrimaryAccent
                )

                summaryRow(
                    icon: "shield.fill",
                    label: "Level",
                    value: "Lv. \(viewModel.currentLevel)",
                    valueColor: Color(hex: IkeruTheme.Colors.Rarity.legendary)
                )

                summaryRow(
                    icon: "clock.fill",
                    label: "Duration",
                    value: viewModel.elapsedTimeFormatted,
                    valueColor: .ikeruTextSecondary
                )
            }
            .ikeruCard(.elevated)
            .padding(.horizontal, IkeruTheme.Spacing.md)

            Spacer()

            // Done button
            Button("Done") {
                viewModel.dismissSession()
            }
            .ikeruButtonStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .padding(.bottom, IkeruTheme.Spacing.xl)
        }
    }

    // MARK: - Summary Row

    private func summaryRow(
        icon: String,
        label: String,
        value: String,
        valueColor: Color
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .frame(width: 24)

            Text(label)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            Spacer()

            Text(value)
                .font(.ikeruHeading3)
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Preview

#Preview("SessionSummaryView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        // Create a mock scenario by using a real ViewModel
        // In preview we just show the layout
        Text("Preview: See ActiveSessionView preview for full flow")
            .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
