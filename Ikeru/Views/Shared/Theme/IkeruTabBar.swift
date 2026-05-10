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
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            FusumaRail(opacity: 0.7)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tap(_ tab: AppTab) {
        withAnimation(Self.tapSpring) { selection = tab }
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
            VStack(spacing: 4) {
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
                    Color.clear.frame(height: 5)
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
        case .home:      return "稽古"
        case .study:     return "辞書"
        case .companion: return "対話"
        case .rpg:       return "段位"
        case .settings:  return "設定"
        }
    }

    private var accessibilityLabel: LocalizedStringKey {
        switch tab {
        case .home:      return "Practice"
        case .study:     return "Study"
        case .companion: return "Talk"
        case .rpg:       return "Profile"
        case .settings:  return "Settings"
        }
    }

    private var monKind: MonKind {
        switch tab {
        case .home:      return .asanoha
        case .study:     return .kikkou
        case .companion: return .genji
        case .rpg:       return .maru
        case .settings:  return .kikkou  // shares with Study but never both active simultaneously
        }
    }
}

// MARK: - Preview

#Preview("IkeruTabBar") {
    struct Wrapper: View {
        @State var selection: AppTab = .home
        var body: some View {
            ZStack(alignment: .bottom) {
                IkeruScreenBackground()
                IkeruTabBar(selection: $selection, tabs: AppTab.allCases)
            }
        }
    }
    return Wrapper().preferredColorScheme(.dark)
}
