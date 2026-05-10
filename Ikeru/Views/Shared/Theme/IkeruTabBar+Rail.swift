import SwiftUI
import IkeruCore

/// Sliding kintsugi-gold rail that marks the active tab. Lives below each
/// tab cell. Uses a `matchedGeometryEffect` source on the active cell;
/// only one rail instance is rendered for the whole tab bar.
struct KintsugiTabRail: View {

    let width: CGFloat
    let height: CGFloat
    /// Soft outer glow opacity, 0–1.
    let glowOpacity: CGFloat

    init(width: CGFloat = 28, height: CGFloat = 3, glowOpacity: CGFloat = 0.55) {
        self.width = width
        self.height = height
        self.glowOpacity = glowOpacity
    }

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.541, green: 0.427, blue: 0.290).opacity(0.0),
                        Color.ikeruPrimaryAccent,
                        Color(red: 0.541, green: 0.427, blue: 0.290).opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .shadow(
                color: Color.ikeruPrimaryAccent.opacity(glowOpacity),
                radius: 8,
                x: 0,
                y: 0
            )
            .accessibilityHidden(true)
    }
}

#Preview("KintsugiTabRail") {
    KintsugiTabRail()
        .padding(40)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
}
