import SwiftUI

// MARK: - Ikebana Brushstroke Logo
//
// A true 3-element ikebana composition (shin / soe / hikae = 天 / 人 / 地),
// crowned by a single open bloom with filled petals — not radial strokes.
//
//   • Shin   (主, heaven) — tallest curving branch, thickest stroke, drawn first.
//   • Soe    (副, man)    — medium counter-curving branch, drawn second.
//   • Hikae  (控, earth)  — short low accent grounding the base, drawn third.
//   • Leaves — 2 small filled almond shapes along shin, drawn fourth.
//   • Bloom  — 6 filled teardrop petals that scale-pop in sequence, then a
//              small darker center dot punches in at the very end.
//
// Asymmetric, off-center, wabi-sabi. Energy rises upward.

// MARK: - Geometry constants
//
// Everything is defined against a unit square (rect of width/height) so the
// mark stays crisp at any size. The bloom center is the anchor point for the
// petal animation and is referenced by several shapes.

private enum Ikebana {
    // Unified pivot — all 3 branches emerge from this single "vase mouth".
    static let pivot = CGPoint(x: 0.42, y: 0.86)
    // Top of shin — where the bloom sits.
    static let bloomCenter = CGPoint(x: 0.60, y: 0.20)
    static let bloomRadius: CGFloat = 0.13   // was 0.11 — slightly larger so it reads
}

// MARK: - Shin (heaven) — main branch

struct IkebanaShinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // Pronounced S-curve: pivot bends gently leftward through mid, then
        // sweeps back right to the bloom. Two cubic segments for real flex.
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.34, 0.55),
            control1: p(0.46, 0.76),
            control2: p(0.34, 0.66)
        )
        path.addCurve(
            to: p(Ikebana.bloomCenter.x, Ikebana.bloomCenter.y),
            control1: p(0.34, 0.42),
            control2: p(0.54, 0.28)
        )
        return path
    }
}

// MARK: - Soe (man) — secondary branch

struct IkebanaSoeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // Curvy ascending counter-branch: rises near-vertically from the pivot,
        // then arcs sharply left into a long graceful sweep.
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.12, 0.38),
            control1: p(0.46, 0.62),
            control2: p(0.22, 0.40)
        )
        return path
    }
}

// MARK: - Hikae (earth) — low accent

struct IkebanaHikaeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // Curvy low accent: arcs out to the right, dipping just barely
        // before lifting back up to anchor the right side of the composition.
        path.move(to: p(Ikebana.pivot.x, Ikebana.pivot.y))
        path.addCurve(
            to: p(0.82, 0.74),
            control1: p(0.56, 0.94),
            control2: p(0.74, 0.86)
        )
        return path
    }
}

// MARK: - Leaf (filled almond/lens)

struct IkebanaLeafShape: Shape {
    /// Anchor center on the shin branch (unit coords).
    let center: CGPoint
    /// Length in unit coords (short axis).
    let length: CGFloat
    /// Rotation in radians.
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let cx = rect.minX + w * center.x
        let cy = rect.minY + h * center.y
        let side = min(w, h)
        let len = side * length
        let thick = len * 0.32

        // Almond via two arcs: construct in local space then rotate.
        let cosR = CGFloat(cos(rotation))
        let sinR = CGFloat(sin(rotation))
        func tx(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(x: cx + lx * cosR - ly * sinR,
                    y: cy + lx * sinR + ly * cosR)
        }

        path.move(to: tx(-len / 2, 0))
        path.addQuadCurve(to: tx(len / 2, 0), control: tx(0, -thick))
        path.addQuadCurve(to: tx(-len / 2, 0), control: tx(0, thick))
        path.closeSubpath()
        return path
    }
}

// MARK: - Petal (filled teardrop)

/// A single filled teardrop petal pointing along `angle` from a center.
struct IkebanaPetalShape: Shape {
    let angle: Double
    let length: CGFloat     // fraction of min(w,h)
    let width: CGFloat      // fraction of length (lateral thickness)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let side = min(w, h)
        let cx = rect.minX + w * Ikebana.bloomCenter.x
        let cy = rect.minY + h * Ikebana.bloomCenter.y
        let len = side * length
        let half = len * width * 0.5

        let cosA = CGFloat(cos(angle))
        let sinA = CGFloat(sin(angle))
        // Local frame: x along petal, y perpendicular.
        func tx(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(x: cx + lx * cosA - ly * sinA,
                    y: cy + lx * sinA + ly * cosA)
        }

        // Teardrop: base at center (pointy-ish), belly bulging outward,
        // rounded tip at `len`.
        path.move(to: tx(0, 0))
        path.addCurve(
            to: tx(len, 0),
            control1: tx(len * 0.15, -half),
            control2: tx(len * 0.85, -half * 0.9)
        )
        path.addCurve(
            to: tx(0, 0),
            control1: tx(len * 0.85, half * 0.9),
            control2: tx(len * 0.15, half)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Stroke timing

private struct StrokeWindow {
    let start: Double
    let end: Double

    func localProgress(_ progress: Double) -> Double {
        guard end > start else { return progress >= end ? 1 : 0 }
        let raw = (progress - start) / (end - start)
        return min(max(raw, 0), 1)
    }
}

private enum LogoTiming {
    static let shin   = StrokeWindow(start: 0.00, end: 0.30)
    static let soe    = StrokeWindow(start: 0.25, end: 0.45)
    static let hikae  = StrokeWindow(start: 0.42, end: 0.55)
    static let leaves = StrokeWindow(start: 0.50, end: 0.65)
    // Each petal gets its own ~0.06 window inside 0.65 → 0.96.
    static let bloomStart: Double = 0.65
    static let bloomEnd:   Double = 0.96
    static let center = StrokeWindow(start: 0.95, end: 1.00)

    static func petalWindow(index: Int, count: Int) -> StrokeWindow {
        let span = bloomEnd - bloomStart
        let step = span / Double(count)
        let s = bloomStart + step * Double(index) * 0.75  // slight overlap
        return StrokeWindow(start: s, end: s + step)
    }
}

// MARK: - Petal layout
//
// 6 petals fanning asymmetrically around the bloom center.
// Upper hemisphere biased — the flower opens upward/outward.

private struct PetalSpec {
    let angle: Double
    let length: CGFloat
    let width: CGFloat
}

private let petalSpecs: [PetalSpec] = [
    PetalSpec(angle: -.pi * 0.95, length: 0.18, width: 0.55),  // far left
    PetalSpec(angle: -.pi * 0.70, length: 0.22, width: 0.60),  // upper-left
    PetalSpec(angle: -.pi * 0.48, length: 0.24, width: 0.62),  // top
    PetalSpec(angle: -.pi * 0.25, length: 0.21, width: 0.58),  // upper-right
    PetalSpec(angle: -.pi * 0.02, length: 0.18, width: 0.54),  // right
    PetalSpec(angle:  .pi * 0.25, length: 0.15, width: 0.50)   // lower-right
]

private let leafSpecs: [IkebanaLeafShape] = [
    // Leaf along shin (mid-height), oriented along shin's tangent (~45° up-right)
    IkebanaLeafShape(
        center: CGPoint(x: 0.51, y: 0.58),
        length: 0.20,
        rotation: -Double.pi / 3.5
    ),
    // Leaf #2 — on soe's upper portion, oriented along soe's tangent
    IkebanaLeafShape(
        center: CGPoint(x: 0.22, y: 0.55),
        length: 0.17,
        rotation: -Double.pi * 0.62
    )
]

// MARK: - Composed logo view

public struct IkeruLogoView: View {
    /// Draw progress in [0, 1]. 0 = invisible, 1 = fully drawn.
    public var progress: Double
    /// Base stroke width — interpreted as a fraction of the view's shorter side.
    /// The legacy name is kept for API compatibility, but values are unitless.
    public var baseStrokeWidth: CGFloat
    /// Accent color for the mark (internal — defaults to the Ikeru warm gold).
    var tint: Color = .ikeruPrimaryAccent

    public init(
        progress: Double = 1.0,
        baseStrokeWidth: CGFloat = 5.5
    ) {
        self.progress = progress
        self.baseStrokeWidth = baseStrokeWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // Scale the stroke with the canvas. `baseStrokeWidth` acts as a
            // reference for a ~120pt canvas; scale proportionally.
            let baseWidth = max(side * 0.055, baseStrokeWidth * side / 120.0)

            ZStack {
                // Anchor knot — visually unifies the 3 branches at the pivot.
                Circle()
                    .fill(tint)
                    .frame(width: side * 0.045, height: side * 0.045)
                    .position(
                        x: side * Ikebana.pivot.x,
                        y: side * Ikebana.pivot.y
                    )
                    .opacity(min(progress / 0.10, 1.0))

                // Warm ink-bleed glow underneath.
                composition(baseWidth: baseWidth, bleed: true)
                    .blur(radius: baseWidth * 1.4)
                    .opacity(0.4)
                    .blendMode(.plusLighter)

                // Sharp top layer.
                composition(baseWidth: baseWidth, bleed: false)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Composition

    @ViewBuilder
    private func composition(baseWidth: CGFloat, bleed: Bool) -> some View {
        let shinWidth  = baseWidth * 0.95
        let soeWidth   = baseWidth * 0.72
        let hikaeWidth = baseWidth * 0.55
        let widthMul: CGFloat = bleed ? 1.6 : 1.0

        ZStack {
            // Shin — thickest brushstroke.
            IkebanaShinShape()
                .trim(from: 0, to: LogoTiming.shin.localProgress(progress))
                .stroke(tint, style: StrokeStyle(
                    lineWidth: shinWidth * widthMul,
                    lineCap: .round, lineJoin: .round
                ))

            // Soe — medium, counter-curving.
            IkebanaSoeShape()
                .trim(from: 0, to: LogoTiming.soe.localProgress(progress))
                .stroke(tint, style: StrokeStyle(
                    lineWidth: soeWidth * widthMul,
                    lineCap: .round, lineJoin: .round
                ))

            // Hikae — short grounding accent.
            IkebanaHikaeShape()
                .trim(from: 0, to: LogoTiming.hikae.localProgress(progress))
                .stroke(tint, style: StrokeStyle(
                    lineWidth: hikaeWidth * widthMul,
                    lineCap: .round, lineJoin: .round
                ))

            // Leaves — filled almond shapes, fade+scale in.
            ForEach(Array(leafSpecs.enumerated()), id: \.offset) { idx, leaf in
                let local = LogoTiming.leaves.localProgress(
                    progress - Double(idx) * 0.03
                )
                leaf
                    .fill(tint)
                    .scaleEffect(CGFloat(local), anchor: .center)
                    .opacity(local)
            }

            // Bloom petals — filled teardrops, each scale-pops from the
            // bloom center in sequence, giving a true blooming feel.
            ForEach(Array(petalSpecs.enumerated()), id: \.offset) { idx, spec in
                let window = LogoTiming.petalWindow(index: idx, count: petalSpecs.count)
                let local = window.localProgress(progress)
                IkebanaPetalShape(
                    angle: spec.angle,
                    length: spec.length,
                    width: spec.width
                )
                .fill(tint)
                .scaleEffect(
                    CGFloat(easeOutBack(local)),
                    anchor: bloomAnchor
                )
                .opacity(local)
            }

            // Bloom center dot — slightly more saturated, punches in last.
            BloomCenter()
                .fill(tint.opacity(0.95))
                .scaleEffect(
                    CGFloat(LogoTiming.center.localProgress(progress)),
                    anchor: bloomAnchor
                )
                .opacity(LogoTiming.center.localProgress(progress))
        }
    }

    // Anchor for petal scaling: the bloom center expressed in unit-square
    // coordinates, which matches SwiftUI's UnitPoint space for the ZStack.
    private var bloomAnchor: UnitPoint {
        UnitPoint(x: Ikebana.bloomCenter.x, y: Ikebana.bloomCenter.y)
    }

    /// A gentle overshoot to give the petals a lively pop.
    private func easeOutBack(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let c1 = 1.40
        let c3 = c1 + 1.0
        let x = t - 1.0
        return 1.0 + c3 * x * x * x + c1 * x * x
    }
}

// MARK: - Bloom center dot

private struct BloomCenter: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let side = min(w, h)
        let r = side * 0.035
        let c = CGPoint(
            x: rect.minX + w * Ikebana.bloomCenter.x,
            y: rect.minY + h * Ikebana.bloomCenter.y
        )
        return Path(ellipseIn: CGRect(
            x: c.x - r, y: c.y - r, width: r * 2, height: r * 2
        ))
    }
}

// MARK: - Preview

#Preview("Ikeru Logo — progress stages") {
    ZStack {
        LinearGradient.ikeruHeroWarm
            .ignoresSafeArea()

        VStack(spacing: 32) {
            HStack(spacing: 24) {
                IkeruLogoView(progress: 0.0)
                    .frame(width: 120, height: 120)
                IkeruLogoView(progress: 0.5)
                    .frame(width: 120, height: 120)
                IkeruLogoView(progress: 1.0)
                    .frame(width: 120, height: 120)
            }

            IkeruLogoView(progress: 1.0)
                .frame(width: 240, height: 240)
        }
    }
}
