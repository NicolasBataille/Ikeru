import SwiftUI
import IkeruCore

// MARK: - EnsoRankView
//
// Wabi-sabi rank glyph: a single brushed ink circle (enso, 円相), intentionally
// left open at the upper-right as a real brush stroke does. Replaces the
// heraldic shield badge on the Home hero card and the RPG Profile crest —
// 段 (dan) is the authentic Japanese rank word used in martial arts, go, and
// calligraphy. A brushstroke instead of heraldry.
//
// Small sizes render the ring only (label 第N段 next door carries the numeral).
// Large sizes render the numeral in a confident serif weight inside the ring.

struct EnsoRankView: View {
    /// Rank value — shown inside the ring at large sizes.
    let level: Int

    /// Side length in points. Numeral only renders at ≥ `numeralThreshold`.
    let size: CGFloat

    /// Tint for the brush stroke.
    var color: Color = .ikeruPrimaryAccent

    /// Below this size the numeral is hidden (it becomes unreadable).
    var numeralThreshold: CGFloat = 40

    var body: some View {
        ZStack {
            // Brush ring — two passes for ink pressure variation.
            EnsoBrushShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            color.opacity(0.35),
                            color,
                            color,
                            color.opacity(0.0)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round, lineJoin: .round)
                )

            // Thin inner pass — ink variation detail.
            EnsoBrushShape()
                .stroke(color.opacity(0.55),
                        style: StrokeStyle(lineWidth: size * 0.02, lineCap: .round))

            // Dry-brush wisp at the tail where the brush lifts off.
            EnsoTailWisp()
                .stroke(color.opacity(0.45),
                        style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))

            if size >= numeralThreshold {
                Text("\(level)")
                    .font(.system(size: size * 0.42, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .baselineOffset(-size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Brush Shapes

/// Hand-tuned 4-curve Bézier ring with a clear opening at upper-right.
/// Goes from upper-right, sweeps counter-clockwise all the way around, and
/// returns with a small gap — the wabi-sabi signature.
private struct EnsoBrushShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // Start near top-right (opening), swing counter-clockwise.
        p.move(to: pt(0.81, 0.19))
        p.addCurve(to: pt(0.90, 0.58),
                   control1: pt(0.90, 0.28),
                   control2: pt(0.94, 0.42))
        p.addCurve(to: pt(0.52, 0.92),
                   control1: pt(0.86, 0.78),
                   control2: pt(0.72, 0.92))
        p.addCurve(to: pt(0.10, 0.56),
                   control1: pt(0.28, 0.92),
                   control2: pt(0.10, 0.78))
        p.addCurve(to: pt(0.48, 0.12),
                   control1: pt(0.10, 0.30),
                   control2: pt(0.26, 0.12))
        p.addCurve(to: pt(0.72, 0.16),
                   control1: pt(0.58, 0.12),
                   control2: pt(0.66, 0.13))
        return p
    }
}

/// Short trailing flick where the brush leaves the paper — just above the ring's opening.
private struct EnsoTailWisp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.84, y: rect.minY + h * 0.14))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.92, y: rect.minY + h * 0.07),
            control: CGPoint(x: rect.minX + w * 0.90, y: rect.minY + h * 0.09)
        )
        return p
    }
}

// MARK: - Preview

#Preview("EnsoRankView") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                EnsoRankView(level: 3, size: 28)
                EnsoRankView(level: 3, size: 48)
                EnsoRankView(level: 3, size: 96)
            }
            EnsoRankView(level: 1, size: 140)
        }
    }
    .preferredColorScheme(.dark)
}
