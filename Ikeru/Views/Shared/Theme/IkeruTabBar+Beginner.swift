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
            VStack(spacing: 4) {
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
    }

    private var symbolName: String {
        switch tab {
        case .companion: return "bubble.left.and.bubble.right.fill"
        case .study:     return "book.fill"
        case .home:      return "house.fill"
        case .rpg:       return "rosette"
        case .settings:  return "gearshape.fill"
        }
    }

    private var label: LocalizedStringKey {
        switch tab {
        case .companion: return "Tab.Chat"
        case .study:     return "Tab.Study"
        case .home:      return "Tab.Home"
        case .rpg:       return "Tab.Rank"
        case .settings:  return "Tab.Settings"
        }
    }
}
