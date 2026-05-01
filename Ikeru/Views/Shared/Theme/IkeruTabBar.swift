import SwiftUI
import IkeruCore

// MARK: - Tatami Tab Bar
//
// Kanji-only tab bar for the Tatami direction. Replaces the previous
// SF-Symbol-based liquid-glass capsule with a flat tatami strip:
//   - Active marker: a gold MonCrest above the kanji label.
//   - Inactive cells: dim paperGhost kanji + EN caps, no mon.
//   - Background: .ultraThinMaterial behind a top FusumaRail.
//
// Selection still drives `MainTabView`'s routing — only the rendering
// changes; `AppTab` and the binding are untouched.

struct IkeruTabBar: View {

    @Binding var selection: AppTab
    let tabs: [AppTab]

    private static let tapSpring: Animation =
        .spring(response: 0.35, dampingFraction: 0.86)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TatamiTabCell(
                    tab: tab,
                    isActive: selection == tab,
                    onTap: {
                        withAnimation(Self.tapSpring) {
                            selection = tab
                        }
                    }
                )
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
}

// MARK: - Tatami Tab Cell

private struct TatamiTabCell: View {
    let tab: AppTab
    let isActive: Bool
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
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                Text(englishLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isActive ? Color.ikeruTextSecondary : TatamiTokens.paperGhost
                    )
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var englishLabel: LocalizedStringKey {
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
