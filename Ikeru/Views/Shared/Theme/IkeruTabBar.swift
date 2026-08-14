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
        // Measured, not guessed. Reference: a standard iOS tab bar is ~83pt
        // total — ~49pt of content plus the ~34pt the system reserves for the
        // home indicator. This bar sits inside the bottom safe area, so that
        // 34pt is already accounted for and must NOT be padded a second time;
        // doing exactly that (a 26pt bottom padding) is what made the bar
        // ~120pt and left a band of dead space under the labels.
        //
        // This bar owns the bottom safe area (`MainTabView` hands it over), so
        // these two values are the ENTIRE vertical budget — nothing is added
        // underneath. 8 + ~41 content + 22 = ~71pt, flush to the physical
        // bottom edge.
        //
        // The 22 is not decoration: it is the clearance the home indicator
        // needs. That indicator draws roughly 8pt from the bottom, so labels
        // must not come closer than about 20pt or they crowd it and sit in a
        // region the system treats as its own for gestures.
        //
        // If this ever needs revisiting, measure a screenshot rather than
        // nudging values — three rounds were spent adjusting by feel, and two
        // of them trimmed the wrong edge entirely.
        .padding(.top, 8)
        .padding(.bottom, 22)
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
