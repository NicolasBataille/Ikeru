import SwiftUI

// MARK: - FusumaRail
//
// Paired-hairline rail. Comes from sliding-door rail joinery — a 1px gold
// line on top, a 1px transparent gap, a 1px ink-shadow line below. Total
// thickness 3px. Used wherever a 1px border would normally go.

struct FusumaRail: View {
    enum Orientation { case horizontal, vertical }

    var orientation: Orientation = .horizontal
    var gold: Color = .ikeruPrimaryAccent
    var shadow: Color = .black.opacity(0.7)
    var opacity: Double = 1
    /// When true, the gold line is on the bottom (ink top). Use this on the
    /// bottom rail of a TatamiRoom so the gleaming line frames the contents
    /// from above.
    var inverted: Bool = false

    var body: some View {
        let topColor = inverted ? shadow : gold
        let bottomColor = inverted ? gold : shadow
        let stops: [Gradient.Stop] = [
            .init(color: topColor.opacity(opacity), location: 0),
            .init(color: topColor.opacity(opacity), location: 1.0/3.0),
            .init(color: .clear, location: 1.0/3.0),
            .init(color: .clear, location: 2.0/3.0),
            .init(color: bottomColor.opacity(opacity), location: 2.0/3.0),
            .init(color: bottomColor.opacity(opacity), location: 1)
        ]
        let gradient = LinearGradient(
            stops: stops,
            startPoint: orientation == .horizontal ? .top : .leading,
            endPoint: orientation == .horizontal ? .bottom : .trailing
        )
        Rectangle()
            .fill(gradient)
            .frame(
                width: orientation == .vertical ? 3 : nil,
                height: orientation == .horizontal ? 3 : nil
            )
            .allowsHitTesting(false)
    }
}

#Preview("FusumaRail") {
    VStack(spacing: 24) {
        FusumaRail(orientation: .horizontal)
        FusumaRail(orientation: .horizontal, inverted: true)
        HStack { FusumaRail(orientation: .vertical).frame(height: 80); Spacer() }
    }
    .padding(40)
    .background(Color.ikeruSurface)
    .preferredColorScheme(.dark)
}
