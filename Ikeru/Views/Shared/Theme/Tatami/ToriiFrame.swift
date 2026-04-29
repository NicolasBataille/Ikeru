import SwiftUI

// MARK: - ToriiFrame
//
// 鳥居 (temple gate) frame. Two vertical pillars (hashira) topped by a
// horizontal kasagi crossbeam with a slight upward curve at each end, and
// a thinner nuki crossbeam below that. The host content (rank kanji)
// renders inside the negative space between the pillars.
//
// Used as the RPG profile rank crest. At sizes ≥ 80, the gate's
// architecture reads cleanly. Smaller crest uses keep `EnsoRankView`.

struct ToriiFrame<Content: View>: View {
    var color: Color = .ikeruPrimaryAccent
    var lineWidth: CGFloat = 4
    var dashed: Bool = false  // for the "next rank" teaser
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ToriiShape()
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: dashed ? [3, 4] : []
                        )
                    )
                content()
                    .frame(width: w * 0.55, height: h * 0.55)
                    .offset(y: h * 0.05) // sit slightly below the kasagi
            }
        }
    }
}

private struct ToriiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Pillar geometry
        let pillarOffset = w * 0.12
        let leftX  = rect.minX + pillarOffset
        let rightX = rect.maxX - pillarOffset
        let pillarBottom = rect.minY + h * 0.95
        let pillarTop    = rect.minY + h * 0.30
        // Kasagi (top crossbeam) — slight upward sweep at each end
        let kasagiY      = rect.minY + h * 0.18
        let kasagiLeftX  = rect.minX + w * 0.04
        let kasagiRightX = rect.maxX - w * 0.04
        let kasagiTipY   = rect.minY + h * 0.08
        // Nuki (lower crossbeam, between kasagi and pillars)
        let nukiY        = rect.minY + h * 0.32
        let nukiLeftX    = rect.minX + w * 0.18
        let nukiRightX   = rect.maxX - w * 0.18

        // Left pillar
        p.move(to: CGPoint(x: leftX, y: pillarBottom))
        p.addLine(to: CGPoint(x: leftX, y: pillarTop))
        // Right pillar
        p.move(to: CGPoint(x: rightX, y: pillarBottom))
        p.addLine(to: CGPoint(x: rightX, y: pillarTop))
        // Kasagi — left tip up, then horizontal across, then right tip up
        p.move(to: CGPoint(x: kasagiLeftX, y: kasagiTipY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: kasagiY),
            control: CGPoint(x: rect.minX + w * 0.25, y: kasagiY + 2)
        )
        p.addQuadCurve(
            to: CGPoint(x: kasagiRightX, y: kasagiTipY),
            control: CGPoint(x: rect.maxX - w * 0.25, y: kasagiY + 2)
        )
        // Nuki
        p.move(to: CGPoint(x: nukiLeftX, y: nukiY))
        p.addLine(to: CGPoint(x: nukiRightX, y: nukiY))

        return p
    }
}

#Preview("ToriiFrame") {
    HStack(spacing: 32) {
        ToriiFrame(color: .ikeruPrimaryAccent, lineWidth: 4) {
            Text("三")
                .font(.system(size: 38, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .frame(width: 96, height: 96)

        ToriiFrame(color: TatamiTokens.goldDim, lineWidth: 2.5, dashed: true) {
            Text("四")
                .font(.system(size: 22, weight: .light, design: .serif))
                .foregroundStyle(TatamiTokens.goldDim)
        }
        .frame(width: 56, height: 56)
        .opacity(0.6)
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
