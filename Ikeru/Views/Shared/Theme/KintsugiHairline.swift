import SwiftUI
import IkeruCore

// MARK: - KintsugiHairline
//
// A thin gold gradient separator that fades from transparent on both ends —
// the literal "kintsugi repair seam" used on the Card Answer screen to
// separate the kana from the romaji, and anywhere else a subtle gold divide
// carries narrative weight (question → answer, before → after, etc.).

struct KintsugiHairline: View {
    var height: CGFloat = 1
    var color: Color = .ikeruPrimaryAccent
    var maxOpacity: Double = 0.85

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.0),
                        color.opacity(maxOpacity),
                        color.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
    }
}

#Preview("KintsugiHairline") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        VStack(spacing: 24) {
            KintsugiHairline()
            KintsugiHairline(height: 2)
        }
        .padding(.horizontal, 60)
    }
    .preferredColorScheme(.dark)
}
