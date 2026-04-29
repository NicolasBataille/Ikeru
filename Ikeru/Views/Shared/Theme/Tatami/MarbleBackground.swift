import SwiftUI

// MARK: - MarbleBackground
//
// Picks a marble PNG variant by screen identifier. Five variants ship
// (`marble-1`..`marble-5`); the ID maps deterministically so the user sees
// the same marble on the same screen on every visit.
//
// Sits behind every screen as the first layer of the Tatami visual stack.

enum MarbleVariant: String, Sendable, CaseIterable {
    case home          = "marble-1"
    case session       = "marble-2"
    case summary       = "marble-3"
    case rpg           = "marble-4"
    case auxiliary     = "marble-5"  // Study, Companion, Settings, Tab-bar
}

struct MarbleBackground: View {
    let variant: MarbleVariant

    var body: some View {
        Image(variant.rawValue)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

#Preview("MarbleBackground") {
    ZStack {
        MarbleBackground(variant: .home)
        VStack(spacing: 12) {
            Text("Home").foregroundStyle(.white)
            Text("(marble-1)").foregroundStyle(.white.opacity(0.5)).font(.caption)
        }
    }
    .preferredColorScheme(.dark)
}
