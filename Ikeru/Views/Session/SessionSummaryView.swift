import SwiftUI
import IkeruCore

// MARK: - SessionSummaryView

/// Displays session completion summary: cards reviewed, XP earned, items learned, duration.
struct SessionSummaryView: View {

    let viewModel: SessionViewModel

    @State private var heroAppeared = false
    @State private var statsAppeared = false
    @State private var lootAppeared = false
    @State private var doneAppeared = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(spacing: IkeruTheme.Spacing.xl) {
                    Spacer(minLength: IkeruTheme.Spacing.xl)

                    heroHeader
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 18)
                        .scaleEffect(heroAppeared ? 1 : 0.96)

                    statsGrid
                        .opacity(statsAppeared ? 1 : 0)
                        .offset(y: statsAppeared ? 0 : 18)

                    if viewModel.sessionLootCount > 0 {
                        lootCallout
                            .opacity(lootAppeared ? 1 : 0)
                            .offset(y: lootAppeared ? 0 : 18)
                    }

                    Spacer(minLength: IkeruTheme.Spacing.xl)

                    Button {
                        dismissSummary()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .ikeruButtonStyle(.primary)
                    .opacity(doneAppeared ? 1 : 0)
                    .offset(y: doneAppeared ? 0 : 12)

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .padding(.top, IkeruTheme.Spacing.xl)
            }
        }
        .opacity(isDismissing ? 0 : 1)
        .scaleEffect(isDismissing ? 0.98 : 1)
        .onAppear(perform: playEntrance)
    }

    // MARK: - Entrance / Exit

    private func playEntrance() {
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)
        withAnimation(spring.delay(0.05)) { heroAppeared = true }
        withAnimation(spring.delay(0.18)) { statsAppeared = true }
        withAnimation(spring.delay(0.30)) { lootAppeared = true }
        withAnimation(spring.delay(0.42)) { doneAppeared = true }
    }

    private func dismissSummary() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isDismissing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            viewModel.dismissSession()
        }
    }

    // MARK: - Hero Header
    //
    // The earned XP becomes the hero stat (before → after bar underneath it).
    // 完 (kan, "completion") anchors the top — the kanji reads as a small
    // calligraphic seal confirming the session has been closed. Reviewed
    // count demotes to a quiet caption.

    private var heroHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text("完")
                .font(.system(size: 56, weight: .regular, design: .serif))
                .foregroundStyle(LinearGradient.ikeruGold)

            Text("SESSION COMPLETE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("+")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("\(viewModel.xpEarned)")
                    .font(.ikeruDisplayLarge)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("XP")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .tracking(1.4)
                    .padding(.leading, 2)
            }

            Text("\(viewModel.reviewedCount) cards reviewed · \(viewModel.elapsedTimeFormatted)")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)

            // Before → after XP bar.
            xpDeltaBar
                .padding(.top, IkeruTheme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(IkeruTheme.Spacing.xl)
        .ikeruCard(.hero)
    }

    /// Compact segmented XP bar showing the delta earned this session. The
    /// earned portion is rendered in gold over the prior (quieter) fill so
    /// the eye immediately sees how much was added.
    private var xpDeltaBar: some View {
        let currentLevel = viewModel.currentLevel
        let required = max(1, RPGConstants.xpForLevel(currentLevel))
        let xpAfter = RPGConstants.progressInLevel(totalXP: viewModel.totalXP).current
        let xpBefore = max(0, xpAfter - viewModel.xpEarned)
        let beforePct = Double(xpBefore) / Double(required)
        let afterPct  = Double(xpAfter)  / Double(required)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 6)

                    // Prior progress (muted gold).
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.ikeruPrimaryAccent.opacity(0.35))
                        .frame(width: max(0, geo.size.width * beforePct), height: 6)

                    // New progress earned this session (full gold).
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient.ikeruGold)
                        .frame(width: max(0, geo.size.width * afterPct), height: 6)
                        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.4), radius: 3)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Lv. \(currentLevel)")
                    .foregroundStyle(Color.ikeruTextTertiary)
                Spacer()
                Text("\(xpAfter) / \(required) XP")
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        // XP is the hero stat up top; the 2×2 grid now carries the supporting
        // metrics. Level uses the brushed rank label 段 instead of the old
        // shield — consistent with the RPG tab.
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
                icon: "rectangle.stack",
                value: "\(viewModel.reviewedCount)",
                label: "Reviewed",
                tint: Color.ikeruPrimaryAccent
            )
            statTile(
                icon: "mountain.2",
                value: "第\(viewModel.currentLevel)段",
                label: "Rank",
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
            Image(systemName: "archivebox.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.rare))

            VStack(alignment: .leading, spacing: 2) {
                Text(lootCalloutTitle)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("\(viewModel.sessionLootCount) new item\(viewModel.sessionLootCount == 1 ? "" : "s") · open in RPG")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(IkeruTheme.Spacing.lg)
        .ikeruGlass(
            cornerRadius: IkeruTheme.Radius.lg,
            tint: Color(hex: IkeruTheme.Colors.Rarity.rare),
            tintOpacity: 0.10
        )
    }

    /// A session-themed name for the loot cache. Early sessions read as
    /// "Kana Initiate's Cache" to echo the RPG progression language; past a
    /// threshold the name promotes to "Kanji Scholar's Trove".
    private var lootCalloutTitle: String {
        let lvl = viewModel.currentLevel
        switch lvl {
        case ..<3:   return "Kana Initiate's Cache"
        case 3..<10: return "Apprentice's Cache"
        case 10..<20: return "Kanji Scholar's Trove"
        default:     return "Master's Coffer"
        }
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
