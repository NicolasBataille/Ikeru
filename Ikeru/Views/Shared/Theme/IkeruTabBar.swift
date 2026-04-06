import SwiftUI
import IkeruCore

// MARK: - Custom Premium Tab Bar

/// A floating Liquid Glass tab bar that replaces the default UITabBar.
/// Features:
/// - Glass material with edge highlight and warm tint behind selected item
/// - Springy selection animation with scale + opacity transitions
/// - Selection indicator that morphs between tabs
/// - Subtle haptic feedback on selection
struct IkeruTabBar: View {

    @Binding var selection: AppTab
    let tabs: [AppTab]

    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.full,
                tint: .clear,
                tintOpacity: 0.0,
                highlight: 0.20,
                strokeOpacity: 0.18,
                strokeWidth: 0.8
            )
        }
        .shadow(color: Color.black.opacity(0.55), radius: 32, y: 16)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func tabButton(tab: AppTab) -> some View {
        let isSelected = selection == tab

        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selection = tab
            }
        } label: {
            ZStack {
                // Selection indicator (animated background pill)
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xE5BC8A, opacity: 0.32),
                                    Color(hex: 0xD4A574, opacity: 0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                Color(hex: 0xE5BC8A, opacity: 0.45),
                                lineWidth: 0.8
                            )
                        )
                        .matchedGeometryEffect(id: "tab.indicator", in: indicatorNamespace)
                }

                Image(systemName: isSelected ? tab.iconSelected : tab.icon)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.ikeruPrimaryAccent : Color.ikeruTextSecondary
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - AppTab icon helpers

extension AppTab {
    var iconSelected: String {
        switch self {
        case .home:      return "house.fill"
        case .study:     return "book.closed.fill"
        case .companion: return "bubble.left.and.text.bubble.right.fill"
        case .rpg:       return "shield.lefthalf.filled"
        case .settings:  return "gearshape.fill"
        }
    }

    var iconUnselected: String {
        switch self {
        case .home:      return "house"
        case .study:     return "book.closed"
        case .companion: return "bubble.left"
        case .rpg:       return "shield"
        case .settings:  return "gearshape"
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
