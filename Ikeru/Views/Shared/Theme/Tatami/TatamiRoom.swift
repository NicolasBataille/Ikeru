import SwiftUI

// MARK: - TatamiRoom
//
// The card-equivalent of the Tatami direction: solid fill (no rounded
// corners), top + bottom fusuma rails, and four sumi corners. Replaces
// `IkeruCard` everywhere in the per-screen restyle.
//
// Variants:
//   .standard — quiet ink fill, dim-gold rails and corners
//   .accent   — warmer fill (ink with a faint gold tint), full-gold rails
//   .glass    — translucent Liquid-Glass surface used SPARINGLY on hero
//               cards (Home hero, SRS card, JLPT estimate, RPG hero,
//               Conversation hero). Honors the design's "selective glass"
//               principle.

enum TatamiRoomVariant: Sendable {
    case standard
    case accent
    case glass     // accent + glass
}

struct TatamiRoomModifier: ViewModifier {
    let variant: TatamiRoomVariant
    let padding: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(roomBackground)
            .overlay(alignment: .top) { FusumaRail(gold: railGold, opacity: railOpacity) }
            .overlay(alignment: .bottom) { FusumaRail(gold: railGold, opacity: railOpacity, inverted: true) }
            .sumiCorners(color: cornerColor, size: 10, weight: 1.5)
    }

    @ViewBuilder
    private var roomBackground: some View {
        switch variant {
        case .standard:
            // Slight transparency so the marble paper grain + gold veins
            // still read through every card. The marble PNG asset itself
            // is now bright enough that the card can be mostly opaque
            // for legible text without losing the Tatami signature.
            Rectangle().fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.78)) // #1A1A22 ~78%
        case .accent:
            LinearGradient(
                colors: [
                    Color(red: 0.122, green: 0.102, blue: 0.071, opacity: 0.82),  // #1F1A12 ~82%
                    Color(red: 0.102, green: 0.086, blue: 0.071, opacity: 0.82)   // #1A1612 ~82%
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.157, green: 0.118, blue: 0.071, opacity: 0.5),
                        Color(red: 0.110, green: 0.086, blue: 0.071, opacity: 0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial)
            }
        }
    }

    private var railGold: Color {
        switch variant {
        case .standard: return TatamiTokens.goldDim
        case .accent, .glass: return .ikeruPrimaryAccent
        }
    }

    private var railOpacity: Double {
        switch variant {
        case .standard: return 0.7
        case .accent, .glass: return 1.0
        }
    }

    private var cornerColor: Color {
        switch variant {
        case .standard: return TatamiTokens.goldDim
        case .accent, .glass: return .ikeruPrimaryAccent
        }
    }
}

extension View {
    /// Wrap a view in a Tatami room (fusuma rails + sumi corners + solid fill).
    /// - Parameters:
    ///   - variant: visual treatment
    ///   - padding: inner padding (defaults to 18 on all sides)
    func tatamiRoom(
        _ variant: TatamiRoomVariant = .standard,
        padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    ) -> some View {
        modifier(TatamiRoomModifier(variant: variant, padding: padding))
    }

    /// Convenience: uniform padding.
    func tatamiRoom(
        _ variant: TatamiRoomVariant = .standard,
        padding: CGFloat
    ) -> some View {
        modifier(TatamiRoomModifier(
            variant: variant,
            padding: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        ))
    }
}

#Preview("TatamiRoom") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Standard").foregroundStyle(.white)
                .tatamiRoom(.standard)
            Text("Accent").foregroundStyle(.white)
                .tatamiRoom(.accent)
            Text("Glass").foregroundStyle(.white)
                .tatamiRoom(.glass)
        }
        .padding(20)
    }
    .background(MarbleBackground(variant: .home))
    .preferredColorScheme(.dark)
}
