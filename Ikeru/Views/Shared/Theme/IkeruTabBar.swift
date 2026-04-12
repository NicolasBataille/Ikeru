import SwiftUI
import IkeruCore

// MARK: - Custom Premium Tab Bar

/// A floating Liquid Glass tab bar that replaces the default UITabBar.
/// Features:
/// - Native iOS 26 `.glassEffect` (subtle variant) with legacy fallback
/// - Springy selection animation with matchedGeometryEffect indicator
/// - Drag-to-slide gesture: press anywhere and drag horizontally to slide
///   selection in real time; tap-only still works for single-tab selection
/// - Subtle haptic feedback on every selection change
struct IkeruTabBar: View {

    @Binding var selection: AppTab
    let tabs: [AppTab]

    @Namespace private var indicatorNamespace

    /// Horizontal inset applied to the HStack via `.padding(.horizontal, 8)`.
    /// Kept as a named constant so the drag-gesture hit-testing stays in sync
    /// with the visual layout.
    private static let horizontalInset: CGFloat = 8
    private static let verticalInset: CGFloat = 8
    private static let cellHeight: CGFloat = 44

    private static let selectionSpring: Animation =
        .spring(response: 0.42, dampingFraction: 0.78)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabCell(tab: tab)
            }
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.vertical, Self.verticalInset)
        .background(alignment: .center) { tabBarGlassBackground }
        .overlay { dragSelectionOverlay }
        .sensoryFeedback(.selection, trigger: selection)
        .shadow(color: Color.black.opacity(0.55), radius: 32, y: 16)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.bottom, 6)
    }

    // MARK: - Glass background

    @ViewBuilder
    private var tabBarGlassBackground: some View {
        if #available(iOS 26.0, *) {
            // Native iOS 26 Liquid Glass — `.clear` is the lightest/most
            // subtle variant ("léger"), letting the content show through
            // while still giving a refractive glass sensation.
            Capsule()
                .fill(Color.clear)
                .glassEffect(.clear, in: Capsule())
        } else {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.full,
                tint: .clear,
                tintOpacity: 0.0,
                highlight: 0.20,
                strokeOpacity: 0.18,
                strokeWidth: 0.8
            )
        }
    }

    // MARK: - Drag-to-slide overlay

    /// Transparent overlay that captures press + horizontal drag over the
    /// entire tab bar. A zero-distance drag behaves as a tap; moving the
    /// finger updates `selection` as it crosses cell boundaries.
    private var dragSelectionOverlay: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateSelection(
                                atLocationX: value.location.x,
                                totalWidth: proxy.size.width
                            )
                        }
                )
        }
    }

    private func updateSelection(atLocationX x: CGFloat, totalWidth: CGFloat) {
        guard !tabs.isEmpty else { return }
        let usableWidth = totalWidth - (Self.horizontalInset * 2)
        guard usableWidth > 0 else { return }
        let clampedX = min(max(x - Self.horizontalInset, 0), usableWidth - 0.001)
        let cellWidth = usableWidth / CGFloat(tabs.count)
        let rawIndex = Int(clampedX / cellWidth)
        let index = min(max(rawIndex, 0), tabs.count - 1)
        let target = tabs[index]
        if target != selection {
            withAnimation(Self.selectionSpring) {
                selection = target
            }
        }
    }

    // MARK: - Tab cell (no Button — drag gesture handles input)

    @ViewBuilder
    private func tabCell(tab: AppTab) -> some View {
        let isSelected = selection == tab

        ZStack {
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
        .frame(height: Self.cellHeight)
        .contentShape(Rectangle())
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
