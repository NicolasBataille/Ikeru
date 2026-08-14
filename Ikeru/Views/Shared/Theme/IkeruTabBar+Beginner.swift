import SwiftUI
import IkeruCore

/// Beginner-mode tab cell: SF Symbol on top, localized FR/EN label
/// underneath. Selected state tinted with `ikeruPrimaryAccent`.
struct BeginnerTabCell: View {

    let tab: AppTab
    let isActive: Bool
    let railNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // spacing 2, and a 3pt rail well: an SF Symbol at size 22 renders
            // a glyph box closer to 26pt tall, so the icon already brings its
            // own breathing room. See `IkeruTabBar`'s padding comment for the
            // 83pt budget these numbers add up to.
            VStack(spacing: 2) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(
                        isActive ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost
                    )
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
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
    }

    private var symbolName: String {
        switch tab {
        case .explore:  return "book.fill"
        case .practice: return "house.fill"
        case .settings: return "gearshape.fill"
        }
    }

    private var label: LocalizedStringKey {
        switch tab {
        case .explore:  return "Tab.Study"
        case .practice: return "Tab.Practice"
        case .settings: return "Tab.Settings"
        }
    }
}
