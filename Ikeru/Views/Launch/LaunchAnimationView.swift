import SwiftUI

// MARK: - Launch Animation
//
// "Sumi Drop — drop from the Dynamic Island." Full rebuild per the approved
// Claude Design spec (launch-animation-rebuild-spec.md, design import
// 2026-07-18; owner decision same day keeps hikae with a redesigned path +
// a 3rd leaf, overriding the design's omission).
//
// A gold ink bead forms under the Dynamic Island, falls under honest
// gravity, and visually BECOMES the bloom-center dot on impact. Petals
// bloom out of that dot, then the ink runs DOWN the stem from the impact
// point, branches spread from the pivot, leaves pop along the way.
//
// ONE linear master clock (`LaunchClock`) drives every phase as a pure
// function of elapsed seconds via a single `TimelineView(.animation)`. No
// Task.sleep chains, no withAnimation sequencing — every value below is
// f(elapsed), recomputed every frame. This fixes, by construction, all 5
// bugs documented against the previous implementation:
//   1. Ripple opacity is part of the same pure function as radius — it
//      always reaches exactly 0, never freezes.
//   2. Ripples are explicitly gated to 0 opacity before their own start —
//      no more "ring 3 as a dot" before its window begins.
//   3. There's no separate outer easing layered on top of each element's
//      own local-progress window — every element eases its own progress
//      exactly once.
//   4. The falling bead visually BECOMES the bloom-center dot: bead
//      opacity fades to 0 over 0.68–0.80s while the dot pops in via
//      backOut over the same window, both anchored at the same point.
//   5. Timing lives entirely in `LaunchClock` below — no Task.sleep, and
//      `IkeruApp` no longer layers a second cross-fade on top.
//
// Timeline (seconds, elapsed ∈ [0, 3.3], IMPACT = 0.68):
//   0.00–0.35  bead forms under the Dynamic Island
//   0.35–0.68  bead falls (honest gravity, teardrop)
//   0.68–0.80  impact squash + bead fade
//   0.68+0.35  bloom-center dot pops (backOut) — the drop IS the dot
//   0.68+i·.12 ×3 ripples expand + fade to zero
//   0.68+.45   ×4 splash droplets arc out (parabola) + fade
//   0.80+i·.07 ×5 petals bloom out of the dot
//   1.10+0.65  stem draws REVERSED, top (bloom center) down to the pivot
//   1.68+0.18  pivot knot pops (scales, not just fades)
//   1.78+0.40  soe branch draws outward from the pivot
//   1.76/2.00  shin- and soe-side leaves pop (own-center anchored)
//   2.14+0.32  hikae branch draws outward — redesigned 2026-07-18
//   2.40+0.28  hikae's tip leaf pops (new, 2026-07-18)
//   2.55+0.35  breathe: whole mark scale 1→1.02 + bloom glow
//   3.00+0.30  single exit fade of the whole layer; onComplete at 3.30
//
// Reduce Motion: renders a static "settled" frame (elapsed = 2.90 — every
// draw/pop phase is done, bead/ripples/splash are long gone, fade hasn't
// started) with a simple ≤0.4s fade-in, then onComplete. No live clock.

struct LaunchAnimationView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isPaused = false
    @State private var didFinish = false
    @State private var reducedMotionOpacity: Double = 0

    /// A point late enough that every draw/pop phase has settled but the
    /// exit fade (3.00s) hasn't started yet.
    private static let reducedMotionSnapshot: Double = 2.90

    var body: some View {
        Group {
            if reduceMotion {
                reducedMotionView
            } else {
                animatedView
            }
        }
    }

    // MARK: - Master-clock path

    @ViewBuilder
    private var animatedView: some View {
        TimelineView(.animation(paused: isPaused)) { context in
            GeometryReader { geo in
                let elapsed = min(max(context.date.timeIntervalSince(startDate), 0), LaunchClock.total)
                LaunchScene(elapsed: elapsed, geo: geo)
                    .onChange(of: elapsed >= LaunchClock.total) { _, reachedEnd in
                        guard reachedEnd else { return }
                        isPaused = true
                        finish()
                    }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Reduce Motion path

    @ViewBuilder
    private var reducedMotionView: some View {
        GeometryReader { geo in
            LaunchScene(elapsed: Self.reducedMotionSnapshot, geo: geo)
        }
        .ignoresSafeArea()
        .opacity(reducedMotionOpacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                reducedMotionOpacity = 1.0
            } completion: {
                finish()
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

// MARK: - Master clock

/// Pure time → progress helpers. `seg` mirrors the design's
/// `seg(t,start,dur,fn) = fn(clamp((t-start)/dur))`, minus the easing
/// (callers apply `IkebanaEasing` themselves so every phase reads as
/// "local progress, then ease").
private enum LaunchClock {
    static let impact: Double = 0.68
    static let total: Double = 3.30

    /// Clamped linear local progress of `elapsed` within `[start, start+dur)`.
    /// Returns 0 before `start` and 1 at/after `start + dur`.
    static func seg(_ elapsed: Double, _ start: Double, _ dur: Double) -> Double {
        guard dur > 0 else { return elapsed >= start ? 1 : 0 }
        return min(max((elapsed - start) / dur, 0), 1)
    }

    static func fadeOpacity(elapsed: Double) -> Double {
        1 - IkebanaEasing.easeInCubic(seg(elapsed, 3.00, 0.30))
    }
}

// MARK: - Bead (fall → impact → becomes the dot)

private struct BeadFrame {
    let rx: CGFloat
    let ry: CGFloat
    let center: CGPoint
    let opacity: Double
    let neckOpacity: Double
    let neckWidth: CGFloat
    let neckTop: CGFloat

    static func make(elapsed: Double, bloom: CGPoint, safeTop: CGFloat, scale: CGFloat) -> BeadFrame {
        let formP = IkebanaEasing.easeInOutCubic(LaunchClock.seg(elapsed, 0.00, 0.35))
        let baseR: CGFloat = 6 * scale

        func hangY(_ formProgress: Double) -> CGFloat {
            // Real-device analog of the design's "ISLAND_B+5+4·formP": the
            // bead hangs a few points below the actual safe-area top (the
            // Dynamic Island bottom), not a hardcoded canvas offset.
            safeTop + (5 + 4 * CGFloat(formProgress)) * scale
        }

        let fallLocal = LaunchClock.seg(elapsed, 0.35, 0.33)
        let fallP = fallLocal * fallLocal // honest gravity: x·x
        let squashLocal = LaunchClock.seg(elapsed, LaunchClock.impact, 0.12)
        let fadeLocal = LaunchClock.seg(elapsed, 0.70, 0.10)

        let y: CGFloat
        let rx: CGFloat
        let ry: CGFloat
        if elapsed < 0.35 {
            let r = baseR * CGFloat(formP)
            y = hangY(formP)
            rx = r
            ry = r
        } else if elapsed < LaunchClock.impact {
            y = hangY(1) + (bloom.y - hangY(1)) * CGFloat(fallP)
            rx = baseR
            ry = baseR * 1.3 // teardrop while falling
        } else {
            y = bloom.y
            rx = baseR
            ry = baseR * (1 - 0.6 * CGFloat(squashLocal))
        }

        let opacity: Double = elapsed < 0.70 ? 1.0 : max(1.0 - fadeLocal, 0)

        return BeadFrame(
            rx: rx,
            ry: ry,
            center: CGPoint(x: bloom.x, y: y),
            opacity: opacity,
            neckOpacity: elapsed < 0.35 ? 0.8 : 0.0,
            neckWidth: 2.8 * scale * (1 - CGFloat(formP) * 0.5),
            neckTop: safeTop
        )
    }
}

// MARK: - Ripples (expand AND fade to zero)

private struct RippleFrame: Identifiable {
    let id: Int
    let radius: CGFloat
    let opacity: Double
    let lineWidth: CGFloat

    static func make(elapsed: Double, scale: CGFloat) -> [RippleFrame] {
        (0..<3).map { i in
            let start = LaunchClock.impact + Double(i) * 0.12
            // One eased local per ring, shared by radius AND opacity — the
            // design's `p = seg(t, start, 0.70, easeOutCubic)`.
            let eased = IkebanaEasing.easeOutCubic(LaunchClock.seg(elapsed, start, 0.70))
            let radius = (8.0 + (70.0 + 24.0 * Double(i)) * eased) * Double(scale)
            let rawOpacity = (1 - eased) * (0.5 - 0.14 * Double(i))
            // Gated to 0 before `start` — the shipped bug let ring 3 sit as
            // a visible dot 200ms before its own window began.
            let opacity = elapsed < start ? 0 : max(rawOpacity, 0)
            let lineWidth = (2.2 - 0.5 * Double(i)) * Double(scale)
            return RippleFrame(id: i, radius: CGFloat(radius), opacity: opacity, lineWidth: CGFloat(lineWidth))
        }
    }
}

// MARK: - Splash droplets (parabolic arc, fade at both ends)

private struct SplashFrame: Identifiable {
    let id: Int
    let point: CGPoint
    let radius: CGFloat
    let opacity: Double

    static func make(elapsed: Double, bloom: CGPoint, scale: CGFloat) -> [SplashFrame] {
        let dirs: [Double] = [-1, -0.5, 0.5, 1]
        let local = LaunchClock.seg(elapsed, LaunchClock.impact, 0.45)
        let easedX = IkebanaEasing.easeOutCubic(local)
        return dirs.enumerated().map { i, dir in
            let x = bloom.x + CGFloat(dir * 30 * easedX) * scale
            let parabola = (1 - dir * dir * 0.3) * 4 * local * (1 - local)
            let y = bloom.y - CGFloat(30 * parabola) * scale
            let radius = (2.2 - abs(dir) * 0.8) * Double(scale)
            let rawOpacity = 0.85 * (1 - local)
            let opacity = (local <= 0 || local >= 1) ? 0 : rawOpacity
            return SplashFrame(id: i, point: CGPoint(x: x, y: y), radius: CGFloat(radius), opacity: opacity)
        }
    }
}

// MARK: - Petals (bloom out of the dot)

private struct PetalFrame: Identifiable {
    let id: Int
    let spec: PetalSpec
    let scale: CGFloat
    let opacity: Double

    static func make(elapsed: Double) -> [PetalFrame] {
        petalSpecs.enumerated().map { idx, spec in
            let start = 0.80 + Double(idx) * 0.07
            let local = LaunchClock.seg(elapsed, start, 0.45)
            return PetalFrame(
                id: idx,
                spec: spec,
                scale: CGFloat(IkebanaEasing.backOut(local)),
                opacity: min(local / 0.3, 1)
            )
        }
    }
}

// MARK: - Mark (stem, soe, hikae, leaves, knot, dot)

private struct MarkFrame {
    let shinLocal: Double
    let soeLocal: Double
    let hikaeLocal: Double
    let knotP: Double
    let dotP: Double
    /// backOut-eased local progress per leaf — the spec's window easing is
    /// backOut and "opacity = same local", so scale and opacity share this
    /// one value: [shin-side, soe-side, hikae-tip].
    let leafLocals: [Double]

    static func make(elapsed: Double) -> MarkFrame {
        MarkFrame(
            shinLocal: IkebanaEasing.easeInOutCubic(LaunchClock.seg(elapsed, 1.10, 0.65)),
            soeLocal: IkebanaEasing.easeInOutCubic(LaunchClock.seg(elapsed, 1.78, 0.40)),
            hikaeLocal: IkebanaEasing.easeInOutCubic(LaunchClock.seg(elapsed, 2.14, 0.32)),
            knotP: IkebanaEasing.backOut(LaunchClock.seg(elapsed, 1.68, 0.18)),
            dotP: IkebanaEasing.backOut(LaunchClock.seg(elapsed, LaunchClock.impact, 0.35)),
            leafLocals: [
                IkebanaEasing.backOut(LaunchClock.seg(elapsed, 1.76, 0.30)),  // shin-side leaf ("right")
                IkebanaEasing.backOut(LaunchClock.seg(elapsed, 2.00, 0.32)),  // soe-side leaf ("left")
                IkebanaEasing.backOut(LaunchClock.seg(elapsed, 2.40, 0.28))   // hikae-tip leaf (new 2026-07-18)
            ]
        )
    }
}

// MARK: - Breathe (scale + bloom glow)

private struct BreatheFrame {
    let scale: CGFloat
    let glowOpacity: Double
    let glowRadius: CGFloat

    static func make(elapsed: Double, dotP: Double, canvasScale: CGFloat) -> BreatheFrame {
        let local = LaunchClock.seg(elapsed, 2.55, 0.35)
        let glowP = IkebanaEasing.smooth(local)
        return BreatheFrame(
            scale: CGFloat(1.0 + 0.02 * glowP),
            glowOpacity: 0.30 * glowP + 0.10 * dotP * (1 - glowP),
            glowRadius: 260 * canvasScale
        )
    }
}

// MARK: - Scene (renders one frame — a pure function of `elapsed`)

private struct LaunchScene: View {
    let elapsed: Double
    let geo: GeometryProxy

    fileprivate static let markSide: CGFloat = 220
    private static let markBaseWidth: CGFloat = max(markSide * 0.068, 5.5 * markSide / 120.0)
    private static let shinWidth = markBaseWidth * 1.10
    private static let soeWidth = markBaseWidth * 0.55
    private static let hikaeWidth = markBaseWidth * 0.401

    // Design canvas is 300×640; a device-height-derived scale keeps the
    // "atmospheric" effects (bead, ripples, splash, glow) proportional
    // across devices. The mark itself stays a fixed 220pt frame, matching
    // the app's existing convention (see `IkeruLogoView`).
    private var canvasScale: CGFloat { geo.size.height / 640.0 }
    private var screenCenter: CGPoint { CGPoint(x: geo.size.width / 2, y: geo.size.height / 2) }
    private var safeTop: CGFloat { geo.safeAreaInsets.top }

    /// The real bloom-center screen point — the logo frame stays centered
    /// and fixed at 220pt, so this is the same math the shipped view used.
    private var bloomPoint: CGPoint {
        CGPoint(
            x: screenCenter.x + (Ikebana.bloomCenter.x - 0.5) * Self.markSide,
            y: screenCenter.y + (Ikebana.bloomCenter.y - 0.5) * Self.markSide
        )
    }

    var body: some View {
        let bead = BeadFrame.make(elapsed: elapsed, bloom: bloomPoint, safeTop: safeTop, scale: canvasScale)
        let ripples = RippleFrame.make(elapsed: elapsed, scale: canvasScale)
        let splashes = SplashFrame.make(elapsed: elapsed, bloom: bloomPoint, scale: canvasScale)
        let petals = PetalFrame.make(elapsed: elapsed)
        let mark = MarkFrame.make(elapsed: elapsed)
        let breathe = BreatheFrame.make(elapsed: elapsed, dotP: mark.dotP, canvasScale: canvasScale)
        let fade = LaunchClock.fadeOpacity(elapsed: elapsed)

        return ZStack {
            LinearGradient.ikeruHeroWarm

            glow(breathe)

            ForEach(ripples) { ripple in
                rippleShape(ripple).position(bloomPoint)
            }

            ForEach(splashes) { splash in
                Circle()
                    .fill(Color.ikeruPrimaryAccent.opacity(splash.opacity))
                    .frame(width: splash.radius * 2, height: splash.radius * 2)
                    .position(splash.point)
            }

            markLayer(mark: mark, petals: petals)
                .frame(width: Self.markSide, height: Self.markSide)
                // Scale BEFORE positioning so the breathe scales about the
                // mark's own center regardless of sibling layout (review
                // finding: the reverse order only worked because the
                // background gradient happened to force full-size bounds).
                .scaleEffect(breathe.scale)
                .position(screenCenter)

            beadView(bead)
        }
        .opacity(fade)
    }

    // MARK: Bead

    @ViewBuilder
    private func beadView(_ bead: BeadFrame) -> some View {
        if bead.opacity > 0 {
            ZStack {
                if bead.neckOpacity > 0 {
                    Rectangle()
                        .fill(Color(hex: 0xD4A574, opacity: bead.neckOpacity))
                        .frame(width: bead.neckWidth, height: max(bead.center.y - bead.neckTop, 0))
                        .position(x: bead.center.x, y: (bead.neckTop + bead.center.y) / 2)
                }
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF0D7A8), Color(hex: 0xD4A574)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: bead.rx * 2, height: bead.ry * 2)
                    .position(bead.center)
            }
            .opacity(bead.opacity)
        }
    }

    // MARK: Ripple + glow

    @ViewBuilder
    private func rippleShape(_ ripple: RippleFrame) -> some View {
        Circle()
            .stroke(Color(hex: 0xD4A574, opacity: ripple.opacity), lineWidth: ripple.lineWidth)
            .frame(width: ripple.radius * 2, height: ripple.radius * 2)
    }

    @ViewBuilder
    private func glow(_ breathe: BreatheFrame) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: 0xD4A574, opacity: breathe.glowOpacity),
                        Color(hex: 0xD4A574, opacity: 0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: breathe.glowRadius
                )
            )
            .frame(width: breathe.glowRadius * 2, height: breathe.glowRadius * 2)
            .position(bloomPoint)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: Mark (ink-bleed pass behind a sharp pass — existing IkeruLogoView pattern)

    @ViewBuilder
    private func markLayer(mark: MarkFrame, petals: [PetalFrame]) -> some View {
        ZStack {
            elementsGroup(mark: mark, petals: petals, widthMul: 1.6, petalScaleMul: 1.05)
                // Flatten the ~10 shapes into one layer BEFORE blurring
                // (review finding): a single-layer blur is much cheaper at
                // the 120Hz TimelineView cadence and avoids per-shape blur
                // seams during the 3.3s launch window.
                .compositingGroup()
                .blur(radius: Self.markBaseWidth * 1.4)
                .opacity(0.4)
                .blendMode(.plusLighter)

            elementsGroup(mark: mark, petals: petals, widthMul: 1.0, petalScaleMul: 1.0)
        }
    }

    @ViewBuilder
    private func elementsGroup(
        mark: MarkFrame,
        petals: [PetalFrame],
        widthMul: CGFloat,
        petalScaleMul: CGFloat
    ) -> some View {
        ZStack {
            // Stem — drawn REVERSED: the visible trim range always includes
            // the path's END (bloom center) and grows backward toward the
            // pivot as `shinLocal` increases, so the ink visually runs DOWN
            // from the impact point.
            IkebanaShinShape()
                .trim(from: 1 - CGFloat(mark.shinLocal), to: 1)
                .stroke(Color.ikeruPrimaryAccent, style: StrokeStyle(
                    lineWidth: Self.shinWidth * widthMul, lineCap: .round, lineJoin: .round
                ))

            IkebanaSoeShape()
                .trim(from: 0, to: CGFloat(mark.soeLocal))
                .stroke(Color.ikeruPrimaryAccent, style: StrokeStyle(
                    lineWidth: Self.soeWidth * widthMul, lineCap: .round, lineJoin: .round
                ))

            IkebanaHikaeShape()
                .trim(from: 0, to: CGFloat(mark.hikaeLocal))
                .stroke(Color.ikeruPrimaryAccent, style: StrokeStyle(
                    lineWidth: Self.hikaeWidth * widthMul, lineCap: .round, lineJoin: .round
                ))

            ForEach(Array(zip(leafSpecs, mark.leafLocals).enumerated()), id: \.offset) { _, item in
                let (leaf, local) = item
                // `local` is already backOut-eased (see MarkFrame); scale
                // and opacity share it per the spec ("opacity = same local"
                // — the tiny >1 overshoot clamps harmlessly on opacity).
                leaf
                    .fill(Color.ikeruPrimaryAccent)
                    .scaleEffect(
                        CGFloat(local),
                        anchor: UnitPoint(x: leaf.center.x, y: leaf.center.y)
                    )
                    .opacity(local)
            }

            ForEach(petals) { petal in
                IkebanaPetalShape(angle: petal.spec.angle, length: petal.spec.length, width: petal.spec.width)
                    .fill(Color.ikeruPrimaryAccent)
                    .scaleEffect(
                        petal.scale * petalScaleMul,
                        anchor: UnitPoint(x: Ikebana.bloomCenter.x, y: Ikebana.bloomCenter.y)
                    )
                    .opacity(petal.opacity)
            }

            Circle()
                .fill(Color.ikeruPrimaryAccent)
                .frame(width: Self.markSide * 0.045, height: Self.markSide * 0.045)
                .scaleEffect(CGFloat(mark.knotP))
                .position(x: Self.markSide * Ikebana.pivot.x, y: Self.markSide * Ikebana.pivot.y)

            BloomCenter()
                .fill(Color.ikeruPrimaryAccent.opacity(0.95))
                .scaleEffect(
                    CGFloat(mark.dotP),
                    anchor: UnitPoint(x: Ikebana.bloomCenter.x, y: Ikebana.bloomCenter.y)
                )
        }
    }
}

// MARK: - Preview

#Preview("Launch animation") {
    LaunchAnimationView(onFinished: {})
}
