import SwiftUI
import IkeruCore

// MARK: - SessionSummaryView

/// Displays session completion summary: cards reviewed, XP earned, items learned, duration.
struct SessionSummaryView: View {

    let viewModel: SessionViewModel

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.xl) {
                    Spacer(minLength: IkeruTheme.Spacing.xl)

                    heroHeader

                    statsGrid

                    if viewModel.sessionLootCount > 0 {
                        lootCallout
                    }

                    Spacer(minLength: IkeruTheme.Spacing.xl)

                    Button("Done") {
                        viewModel.dismissSession()
                    }
                    .ikeruButtonStyle(.primary)
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .padding(.top, IkeruTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(LinearGradient.ikeruGold)

            Text("SESSION COMPLETE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)

            Text("\(viewModel.reviewedCount)")
                .font(.ikeruDisplayLarge)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)

            Text("cards reviewed")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(IkeruTheme.Spacing.xl)
        .ikeruCard(.hero)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: IkeruTheme.Spacing.md),
                GridItem(.flexible(), spacing: IkeruTheme.Spacing.md)
            ],
            spacing: IkeruTheme.Spacing.md
        ) {
            statTile(
                icon: "sparkles",
                value: "\(viewModel.newItemsLearned)",
                label: "New items",
                tint: Color.ikeruTertiaryAccent
            )
            statTile(
                icon: "star.fill",
                value: "+\(viewModel.xpEarned)",
                label: "XP earned",
                tint: Color.ikeruPrimaryAccent
            )
            statTile(
                icon: "shield.lefthalf.filled",
                value: "Lv. \(viewModel.currentLevel)",
                label: "Level",
                tint: Color(hex: IkeruTheme.Colors.Rarity.legendary)
            )
            statTile(
                icon: "clock",
                value: viewModel.elapsedTimeFormatted,
                label: "Duration",
                tint: Color.ikeruSecondaryAccent
            )
        }
    }

    private func statTile(
        icon: String,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.ikeruStatsLarge)
                .foregroundStyle(Color.ikeruTextPrimary)

            Text(label.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.lg)
        .ikeruGlass(
            cornerRadius: IkeruTheme.Radius.lg,
            tint: tint,
            tintOpacity: 0.06
        )
    }

    private var lootCallout: some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: "bag.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.rare))

            VStack(alignment: .leading, spacing: 2) {
                Text("Loot earned")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("\(viewModel.sessionLootCount) new item\(viewModel.sessionLootCount == 1 ? "" : "s")")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Spacer()
        }
        .padding(IkeruTheme.Spacing.lg)
        .ikeruGlass(
            cornerRadius: IkeruTheme.Radius.lg,
            tint: Color(hex: IkeruTheme.Colors.Rarity.rare),
            tintOpacity: 0.10
        )
    }
}

// MARK: - Preview

#Preview("SessionSummaryView") {
    ZStack {
        IkeruScreenBackground()
        Text("Preview: See ActiveSessionView preview for full flow")
            .foregroundStyle(Color.ikeruTextPrimary)
    }
    .preferredColorScheme(.dark)
}
