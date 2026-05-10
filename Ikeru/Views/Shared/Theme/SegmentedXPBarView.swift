import SwiftUI
import IkeruCore

// MARK: - SegmentedXPBarView
//
// 12-tick segmented XP bar — replaces the thin gradient bar in the Home hero
// card. "Feels carved, not drawn." Each tick fills independently so progress
// reads as intentional increments rather than a vague continuous smear.

struct SegmentedXPBarView: View {
    /// Progress 0…1.
    let progress: Double

    /// Number of segments. 12 is the design default — reads as quarters and
    /// clean thirds without over-fragmenting at small sizes.
    var segments: Int = 12

    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let pct = max(0, min(1, progress))
            let filledSegments = pct * Double(segments)
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { i in
                    let local = max(0, min(1, filledSegments - Double(i)))
                    segment(width: (geo.size.width - 3 * CGFloat(segments - 1)) / CGFloat(segments),
                            fill: local)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
    }

    private func segment(width: CGFloat, fill: Double) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: max(width, 0), height: height)

            if fill > 0 {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xE8C89A),
                                Color(hex: 0xD4A574),
                                Color(hex: 0xB88B5C)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(width * CGFloat(fill), 0), height: height)
                    .shadow(color: Color(hex: 0xD4A574, opacity: 0.35), radius: 3)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Preview

#Preview("SegmentedXPBarView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        VStack(spacing: 20) {
            SegmentedXPBarView(progress: 0.0).padding()
            SegmentedXPBarView(progress: 0.35).padding()
            SegmentedXPBarView(progress: 0.65).padding()
            SegmentedXPBarView(progress: 1.0).padding()
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
