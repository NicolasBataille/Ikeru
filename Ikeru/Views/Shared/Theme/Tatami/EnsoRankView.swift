import SwiftUI

// MARK: - EnsoRankView
//
// 円相 (ensō) — the hand-drawn "circle of enlightenment," traditionally left
// intentionally open. Used as rank/level chrome: an incomplete brush-stroke
// ring framing the current level in Noto Serif JP. Lighter-weight than
// `ToriiFrame`, which needs size ≥ 80 to read cleanly as architecture — this
// is the small-crest alternative referenced there.

struct EnsoRankView: View {
    let level: Int
    var size: CGFloat = 96
    var color: Color = .ikeruPrimaryAccent
    var lineWidth: CGFloat? = nil

    var body: some View {
        ZStack {
            EnsoRingShape()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth ?? size * 0.045, lineCap: .round))
            SerifNumeral(level, size: size * 0.4, weight: .light, color: color)
        }
        .frame(width: size, height: size)
        // The ring is ornament; the level is the information — group both
        // into a single label so VoiceOver reads "Rank N" once rather than
        // announcing the ring and the numeral as two separate elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank") + Text(verbatim: " \(level)"))
    }
}

/// A hand-drawn-style incomplete circle, left open near the top — the
/// traditional gap where the brush lifts off the paper.
private struct EnsoRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: center,
            radius: r,
            startAngle: .degrees(-98),
            endAngle: .degrees(238),
            clockwise: false
        )
        return path
    }
}

#Preview("EnsoRankView") {
    HStack(spacing: 24) {
        EnsoRankView(level: 3, size: 72)
        EnsoRankView(level: 12, size: 96, color: TatamiTokens.goldDim)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
