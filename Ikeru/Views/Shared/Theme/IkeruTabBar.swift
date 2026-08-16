import SwiftUI
import IkeruCore

// MARK: - Tatami Tab Bar
//
// Mode-aware tab bar. In `.beginner` it renders SF Symbols + localized
// labels (BeginnerTabCell). In `.tatami` it renders the kanji-only
// strip (TatamiTabCell). Both modes share a sliding kintsugi gold rail
// driven by `matchedGeometryEffect`.

struct IkeruTabBar: View {

    @Binding var selection: AppTab
    let tabs: [AppTab]
    @Environment(\.displayMode) private var displayMode
    @Namespace private var railNamespace

    private static let tapSpring: Animation =
        .spring(response: 0.35, dampingFraction: 0.86)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Group {
                    switch displayMode {
                    case .beginner:
                        BeginnerTabCell(
                            tab: tab,
                            isActive: selection == tab,
                            railNamespace: railNamespace,
                            onTap: { tap(tab) }
                        )
                    case .tatami:
                        TatamiTabCell(
                            tab: tab,
                            isActive: selection == tab,
                            railNamespace: railNamespace,
                            onTap: { tap(tab) }
                        )
                    }
                }
                .tourAnchor(tourTarget(for: tab))
            }
        }
        .padding(.horizontal, 22)
        // MEASURED on an iPhone 14 Pro, not estimated. Instrumenting the bar
        // with a GeometryReader and reading it off the device gave
        // `height=76.33 safeBottom=34.0`, which settled two things at once:
        //
        //  1. The bar DOES own the bottom safe area (`MainTabView` hands it
        //     over) — `safeBottom=34` is its overlap into the home-indicator
        //     region, not a second inset stacked underneath. At 76pt it was
        //     already SHORTER than a standard iOS tab bar (~83pt).
        //  2. So height was never the complaint. The content was ASYMMETRIC —
        //     8pt of air above the icons against 22 + 3 below — and that
        //     lopsidedness is what reads as "space under the icons". Three
        //     earlier rounds shortened the bar; none touched the real problem.
        //
        // 12/14 balances it while keeping the labels clear of the home
        // indicator, which draws ~8pt from the bottom edge.
        //
        // Rebalance from a fresh measurement if this changes. Those two numbers
        // cost one instrumented build and were worth more than three rounds of
        // adjusting by eye.
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            FusumaRail(opacity: 0.7)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tap(_ tab: AppTab) {
        withAnimation(Self.tapSpring) { selection = tab }
    }

    /// Maps a tab to its feature-tour spotlight target (3-tab IA).
    private func tourTarget(for tab: AppTab) -> TourTarget {
        switch tab {
        case .explore:  return .exploreTab
        case .practice: return .practiceTab
        case .settings: return .settingsTab
        }
    }
}

// MARK: - Tatami Tab Cell

private struct TatamiTabCell: View {
    let tab: AppTab
    let isActive: Bool
    let railNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                if isActive {
                    MonCrest(kind: monKind, size: 10, color: .ikeruPrimaryAccent)
                } else {
                    Color.clear.frame(height: 10)
                }
                Text(japaneseLabel)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                ZStack {
                    Color.clear.frame(height: 3)
                    if isActive {
                        KintsugiTabRail()
                            .matchedGeometryEffect(id: "tab-rail", in: railNamespace)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        // GAP-01 two-client merge test: tapping between tabs mid-scenario
        // (Explore → Settings) needs a stable, non-localized target — see
        // `EtudeView.kanaRow`'s identifier, added by the same effort.
        .accessibilityIdentifier("tabBar.\(String(describing: tab))")
    }

    private var japaneseLabel: String {
        switch tab {
        case .practice: return "\u{7DF4}\u{7FD2}" // 練習 — Practice (matches the IA)
        case .explore:  return "\u{5B66}\u{7FD2}" // 学習
        case .settings: return "\u{8A2D}\u{5B9A}" // 設定
        }
    }

    private var accessibilityLabel: LocalizedStringKey {
        switch tab {
        case .practice: return "Practice"
        case .explore:  return "Explore"
        case .settings: return "Settings"
        }
    }

    private var monKind: MonKind {
        switch tab {
        case .practice: return .asanoha
        case .explore:  return .kikkou
        case .settings: return .maru
        }
    }
}

// MARK: - Preview

#Preview("IkeruTabBar") {
    struct Wrapper: View {
        @State var selection: AppTab = .practice
        var body: some View {
            ZStack(alignment: .bottom) {
                IkeruScreenBackground()
                IkeruTabBar(selection: $selection, tabs: AppTab.allCases)
            }
        }
    }
    return Wrapper().preferredColorScheme(.dark)
}
