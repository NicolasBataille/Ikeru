import SwiftUI

// MARK: - MarbleBackground
//
// Procedural kintsugi-marble background rendered entirely in SwiftUI.
// Five deterministic variants (one per screen group) replace the former
// PNG approach, which produced thin, hair-like veins on dark backgrounds.
//
// Visual recipe:
//   1. Deep ink gradient base  (#0A0A0F → #14141A)
//   2. 2–3 wide Bézier veins per variant — gold (#D4A574 → #8A6D4A),
//      variable stroke width (2–6 pt), soft glow (blur 3 pt), low opacity
//   3. Subtle angular-gradient noise veil at ~0.03 opacity
//
// API is identical to the old Image-based implementation so all call sites
// remain untouched. The PNG assets are intentionally left in the asset
// catalogue; they are simply no longer referenced here.

// MARK: - Public API

public enum MarbleVariant: String, Sendable, CaseIterable {
    case home       = "marble-1"
    case session    = "marble-2"
    case summary    = "marble-3"
    case rpg        = "marble-4"
    case auxiliary  = "marble-5"  // Study, Companion, Settings, Tab-bar
}

public struct MarbleBackground: View {
    public let variant: MarbleVariant

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(variant: MarbleVariant) {
        self.variant = variant
    }

    public var body: some View {
        // The veins drift very slowly, so a high refresh rate (up to 120 Hz on
        // ProMotion) would burn battery for no visible gain — throttle to ~20fps.
        // Fully paused (and frozen at t=0) under Reduce Motion.
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // 1. Ink base gradient
                drawBase(context: context, size: size)

                // 2. Kintsugi veins (blurred, wide, gold) — gently undulating
                for (index, vein) in KintsugiVeinLibrary.veins(for: variant).enumerated() {
                    drawVein(
                        vein, context: context, size: size,
                        time: time, phase: Double(index) * 1.7
                    )
                }

                // 3. Grain veil — angular gradient overlay at ~0.03 opacity
                drawGrainVeil(context: context, size: size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // NOTE: no .drawingGroup() here — it rasterises the Canvas into a
            // cached layer that doesn't refresh per TimelineView tick, which
            // froze the animation. Canvas is already GPU-backed.
        }
    }

    // MARK: Private drawing helpers

    private func drawBase(context: GraphicsContext, size: CGSize) {
        // Deep ink gradient: sumi black → slightly lighter
        var ctx = context
        let rect = CGRect(origin: .zero, size: size)
        let gradient = Gradient(stops: [
            .init(color: Color(hex: 0x0A0A0F), location: 0.0),
            .init(color: Color(hex: 0x0E0E14), location: 0.45),
            .init(color: Color(hex: 0x14141A), location: 1.0)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                gradient,
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )
    }

    private func drawVein(
        _ vein: KintsugiVein, context: GraphicsContext, size: CGSize,
        time: Double, phase: Double
    ) {
        // Fluid drift: nudge the Bézier handles along slow sines so the belly of
        // each vein undulates, while the endpoints stay anchored to the screen
        // edges. ~4–5 % of the screen over a slow (~12–16 s) cycle — perceptible
        // as a gentle living flow, not a wobble.
        let sway: CGFloat = 0.045
        let drift: CGFloat = 0.030
        let a = CGFloat(sin(time * 0.50 + phase))
        let b = CGFloat(cos(time * 0.38 + phase * 1.3))

        // Scale normalised control points [0..1] to actual pixel coords
        let p0 = vein.p0.scaled(to: size)
        let cp1 = CGPoint(x: vein.cp1.x + sway * a, y: vein.cp1.y + drift * b).scaled(to: size)
        let cp2 = CGPoint(x: vein.cp2.x - sway * b, y: vein.cp2.y + drift * a).scaled(to: size)
        let p3 = vein.p3.scaled(to: size)

        var path = Path()
        path.move(to: p0)
        path.addCurve(to: p3, control1: cp1, control2: cp2)

        // Outer glow pass — wider, more transparent. The glow must inherit
        // the vein's opacity (further dimmed) or it reads as a solid bright
        // band instead of a faint halo.
        let glowWidth = vein.strokeWidth * 3.0
        var glowCtx = context
        glowCtx.opacity = vein.opacity * 0.55
        glowCtx.addFilter(.blur(radius: 4))
        glowCtx.stroke(
            path,
            with: .linearGradient(
                vein.gradient,
                startPoint: p0,
                endPoint: p3
            ),
            style: StrokeStyle(
                lineWidth: glowWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        // Core vein pass — sharp, slightly narrower
        var coreCtx = context
        coreCtx.addFilter(.blur(radius: 1.5))
        coreCtx.opacity = vein.opacity
        coreCtx.stroke(
            path,
            with: .linearGradient(
                vein.gradient,
                startPoint: p0,
                endPoint: p3
            ),
            style: StrokeStyle(
                lineWidth: vein.strokeWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func drawGrainVeil(context: GraphicsContext, size: CGSize) {
        // Very subtle angular grain to break the pure-digital look
        var ctx = context
        ctx.opacity = 0.03
        let rect = CGRect(origin: .zero, size: size)
        let grain = Gradient(colors: [
            Color(hex: 0xD4A574),
            Color(hex: 0x0A0A0F),
            Color(hex: 0xD4A574),
            Color(hex: 0x0A0A0F),
            Color(hex: 0xD4A574)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                grain,
                startPoint: CGPoint(x: 0, y: size.height),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )
    }
}

// MARK: - Vein data model

/// One Bézier vein. All control points in normalised [0..1] space.
struct KintsugiVein: Sendable {
    /// Normalised start / end points and Bézier handles
    let p0: CGPoint
    let cp1: CGPoint
    let cp2: CGPoint
    let p3: CGPoint

    /// Base stroke width at full size (points, pre-canvas-scale)
    let strokeWidth: CGFloat

    /// Alpha for the core pass
    let opacity: Double

    /// Gold gradient along the vein
    let gradient: Gradient
}

// MARK: - Deterministic vein library

enum KintsugiVeinLibrary {
    // Shared gold gradient palette
    private static let brightGold = Color(hex: 0xD4A574)   // IkeruTheme primaryAccent
    private static let midGold    = Color(hex: 0xC09060)
    private static let dimGold    = Color(hex: 0x8A6D4A)   // TatamiTokens.goldDim

    private static func vein(
        _ p0: CGPoint, _ cp1: CGPoint, _ cp2: CGPoint, _ p3: CGPoint,
        width: CGFloat = 3.5,
        opacity: Double = 0.18,
        gradient: Gradient? = nil
    ) -> KintsugiVein {
        KintsugiVein(
            p0: p0, cp1: cp1, cp2: cp2, p3: p3,
            strokeWidth: width,
            opacity: opacity,
            gradient: gradient ?? Gradient(colors: [dimGold, brightGold, midGold])
        )
    }

    static func veins(for variant: MarbleVariant) -> [KintsugiVein] {
        switch variant {

        // MARK: .home — grand diagonal + subtle cross-vein
        case .home:
            return [
                // Primary diagonal — top-left to bottom-right, sweeping arc
                vein(
                    CGPoint(x: -0.02, y: 0.08),
                    CGPoint(x: 0.35,  y: 0.05),
                    CGPoint(x: 0.65,  y: 0.90),
                    CGPoint(x: 1.03,  y: 0.88),
                    width: 5.0, opacity: 0.20,
                    gradient: Gradient(colors: [dimGold, brightGold, brightGold, dimGold])
                ),
                // Secondary, thinner — enters from right edge, exits bottom-left
                vein(
                    CGPoint(x: 1.02, y: 0.32),
                    CGPoint(x: 0.72, y: 0.38),
                    CGPoint(x: 0.30, y: 0.62),
                    CGPoint(x: 0.10, y: 1.02),
                    width: 2.5, opacity: 0.12,
                    gradient: Gradient(colors: [dimGold, midGold, dimGold])
                )
            ]

        // MARK: .session — flowing S-curve, top-right to bottom-left
        case .session:
            return [
                // Main flowing S
                vein(
                    CGPoint(x: 0.85, y: -0.02),
                    CGPoint(x: 0.90, y: 0.40),
                    CGPoint(x: 0.15, y: 0.60),
                    CGPoint(x: 0.20, y: 1.02),
                    width: 6.0, opacity: 0.17,
                    gradient: Gradient(colors: [dimGold, brightGold, brightGold, dimGold])
                ),
                // Thin accent — near-horizontal crossing
                vein(
                    CGPoint(x: -0.02, y: 0.45),
                    CGPoint(x: 0.25,  y: 0.42),
                    CGPoint(x: 0.70,  y: 0.55),
                    CGPoint(x: 1.02,  y: 0.52),
                    width: 2.0, opacity: 0.10
                )
            ]

        // MARK: .summary — gentle arc, lower third
        case .summary:
            return [
                // Long gentle arc from bottom-left to top-right
                vein(
                    CGPoint(x: -0.02, y: 0.75),
                    CGPoint(x: 0.30,  y: 0.60),
                    CGPoint(x: 0.70,  y: 0.28),
                    CGPoint(x: 1.02,  y: 0.18),
                    width: 5.5, opacity: 0.19,
                    gradient: Gradient(colors: [dimGold, midGold, brightGold, dimGold])
                ),
                // Short accent near top — enters left, curves upward
                vein(
                    CGPoint(x: -0.02, y: 0.22),
                    CGPoint(x: 0.18,  y: 0.18),
                    CGPoint(x: 0.40,  y: 0.10),
                    CGPoint(x: 0.65,  y: -0.02),
                    width: 2.5, opacity: 0.11
                )
            ]

        // MARK: .rpg — bold crossing pair, dramatic feel
        case .rpg:
            return [
                // Diagonal 1 — top-right corner to centre-bottom
                vein(
                    CGPoint(x: 0.78, y: -0.02),
                    CGPoint(x: 0.75, y: 0.35),
                    CGPoint(x: 0.55, y: 0.65),
                    CGPoint(x: 0.42, y: 1.02),
                    width: 5.0, opacity: 0.22,
                    gradient: Gradient(colors: [dimGold, brightGold, brightGold, dimGold])
                ),
                // Diagonal 2 — sweeps from left edge across
                vein(
                    CGPoint(x: -0.02, y: 0.55),
                    CGPoint(x: 0.30,  y: 0.45),
                    CGPoint(x: 0.65,  y: 0.30),
                    CGPoint(x: 1.02,  y: 0.12),
                    width: 3.0, opacity: 0.14
                ),
                // Micro vein — very thin, adds depth
                vein(
                    CGPoint(x: 0.10, y: -0.02),
                    CGPoint(x: 0.12, y: 0.30),
                    CGPoint(x: 0.08, y: 0.60),
                    CGPoint(x: 0.18, y: 1.02),
                    width: 1.5, opacity: 0.08
                )
            ]

        // MARK: .auxiliary (Study, Companion, Settings) — calm single arc
        case .auxiliary:
            return [
                // Single wide, calm diagonal
                vein(
                    CGPoint(x: -0.02, y: 0.35),
                    CGPoint(x: 0.28,  y: 0.28),
                    CGPoint(x: 0.68,  y: 0.72),
                    CGPoint(x: 1.02,  y: 0.65),
                    width: 4.5, opacity: 0.16,
                    gradient: Gradient(colors: [dimGold, brightGold, dimGold])
                ),
                // Complementary, subtle — top area
                vein(
                    CGPoint(x: 0.40, y: -0.02),
                    CGPoint(x: 0.50, y: 0.15),
                    CGPoint(x: 0.72, y: 0.20),
                    CGPoint(x: 1.02, y: 0.28),
                    width: 2.0, opacity: 0.10
                )
            ]
        }
    }
}

// MARK: - CGPoint normalised scaling

private extension CGPoint {
    /// Scale normalised [0..1] coordinates to actual canvas size.
    func scaled(to size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}


// MARK: - Preview

#Preview("MarbleBackground — all variants") {
    ScrollView {
        VStack(spacing: 2) {
            ForEach(MarbleVariant.allCases, id: \.rawValue) { variant in
                ZStack {
                    MarbleBackground(variant: variant)
                        .frame(height: 220)
                    VStack(spacing: 6) {
                        Text(variant.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.93))
                        Text("Kintsugi marble — procedural")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.72, green: 0.71, blue: 0.69))
                    }
                }
                .clipped()
            }
        }
    }
    .preferredColorScheme(.dark)
}
