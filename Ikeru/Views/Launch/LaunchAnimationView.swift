import SwiftUI

// MARK: - Launch Animation
//
// Sumi Drop + Flower Blossom combo. Plays once on cold start. ~2.4s total:
//   0.00s → warm dark background, logo invisible
//   0.05s → single gold ink drop falls from top-center under easing gravity
//   0.55s → drop "lands" at the logo's bloom center; soft impact flash
//   0.55s → three concentric ripples expand outward from the impact point
//   0.60s → existing flower-blossom draw begins from the impact point
//           (stem → leaves → petals, same geometry as IkeruLogoView)
//   1.90s → warm glow pulse + subtle scale breathe
//   2.20s → fade out, caller transitions to main UI
//
// The Sumi Drop prefixes and seeds the blossom: the drop becomes the bloom
// center dot, the ripples wash the scene into existence, and the first brush
// strokes emerge from where the ink landed. One narrative, not two sequential
// animations glued together.

enum LaunchPhase {
    case initial
    case dropping   // gold drop falling from top
    case impact     // ripples + blossom begins drawing
    case breathing  // glow pulse + scale
    case fadingOut
}

struct LaunchAnimationView: View {
    let onFinished: () -> Void

    @State private var phase: LaunchPhase = .initial

    // Drop state — the ink droplet falls under a tuned gravity curve.
    @State private var dropOffsetY: CGFloat = -260      // starts above screen
    @State private var dropOpacity: Double = 0.0
    @State private var dropScale: CGFloat = 1.0
    @State private var dropDeformation: CGFloat = 0.0   // 0 = round, 1 = stretched

    // Impact ripple state — three concentric rings expand + fade.
    @State private var ripple1Scale: CGFloat = 0.1
    @State private var ripple1Opacity: Double = 0.0
    @State private var ripple2Scale: CGFloat = 0.1
    @State private var ripple2Opacity: Double = 0.0
    @State private var ripple3Scale: CGFloat = 0.1
    @State private var ripple3Opacity: Double = 0.0

    // Logo/blossom state — same properties the old animation drove.
    @State private var drawProgress: Double = 0.0
    @State private var glowOpacity: Double = 0.0
    @State private var scale: CGFloat = 0.96
    @State private var contentOpacity: Double = 1.0

    // Timing constants (seconds).
    private let fallDuration: Double = 0.50
    private let rippleDuration: Double = 0.65
    private let drawDuration: Double = 1.30
    private let breatheDuration: Double = 0.30
    private let fadeDuration: Double = 0.30

    // Logo frame — used to position ripples/drop at the bloom center.
    // IkeruLogoView's bloom sits at (0.60, 0.20) of a 220pt canvas.
    private let logoSide: CGFloat = 220
    private var bloomOffset: CGSize {
        CGSize(
            width: (0.60 - 0.5) * logoSide,
            height: (0.20 - 0.5) * logoSide
        )
    }

    var body: some View {
        ZStack {
            LinearGradient.ikeruHeroWarm
                .ignoresSafeArea()

            // Warm radial glow behind the mark — pulses in the breathe phase.
            RadialGradient(
                colors: [
                    Color(hex: 0xD4A574, opacity: 0.45),
                    Color(hex: 0xD4A574, opacity: 0.0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .opacity(glowOpacity)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Concentric ripples emanating from the impact point. Layered
            // behind the logo so the blossom draws ON TOP of them as they
            // fade, creating a single continuous "from the drop" gesture.
            ZStack {
                ripple(scale: ripple3Scale, opacity: ripple3Opacity, lineWidth: 1.2)
                ripple(scale: ripple2Scale, opacity: ripple2Opacity, lineWidth: 1.5)
                ripple(scale: ripple1Scale, opacity: ripple1Opacity, lineWidth: 1.8)
            }
            .offset(bloomOffset)
            .allowsHitTesting(false)

            // The logo blossom — draws from the bloom center outward.
            IkeruLogoView(progress: drawProgress)
                .frame(width: logoSide, height: logoSide)
                .scaleEffect(scale)

            // The falling ink drop. Rendered on top; fades out the instant
            // it "impacts" (coincides with ripple start + blossom start), so
            // visually it becomes the bloom center dot.
            inkDrop
                .offset(x: bloomOffset.width, y: dropOffsetY)
                .opacity(dropOpacity)
        }
        .opacity(contentOpacity)
        .task {
            await runSequence()
        }
    }

    // MARK: - Ink Drop

    @ViewBuilder
    private var inkDrop: some View {
        Capsule()
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
            // Tear-drop shape: squish taller as it accelerates, round on impact.
            .frame(width: 18, height: 18 + dropDeformation * 18)
            .scaleEffect(dropScale)
            .shadow(color: Color(hex: 0xD4A574, opacity: 0.7), radius: 12)
    }

    // MARK: - Ripple helper

    @ViewBuilder
    private func ripple(scale: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: 0xD4A574, opacity: 0.0),
                        Color(hex: 0xD4A574, opacity: opacity),
                        Color(hex: 0xD4A574, opacity: 0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
            .frame(width: 40, height: 40)
            .scaleEffect(scale)
    }

    // MARK: - Sequence

    @MainActor
    private func runSequence() async {
        // 0.00 → 0.05s hold.
        try? await Task.sleep(nanoseconds: 50_000_000)

        // 0.05 → 0.55s: drop falls from top under gentle easing gravity.
        phase = .dropping
        withAnimation(.easeIn(duration: fallDuration)) {
            dropOffsetY = bloomOffset.height
            dropOpacity = 1.0
            dropDeformation = 0.35   // stretch as it accelerates
        }
        try? await Task.sleep(nanoseconds: UInt64(fallDuration * 1_000_000_000))

        // 0.55s: impact. Drop snaps round, absorbs into the surface, and the
        // ripples + blossom fire simultaneously — the ink that just landed
        // IS the bloom center dot, and the brushwork emerges from it.
        phase = .impact

        // Absorb the drop into the mark.
        withAnimation(.easeOut(duration: 0.18)) {
            dropDeformation = 0.0
            dropScale = 1.4
            dropOpacity = 0.0
        }

        // Fire three ripples with staggered delays.
        withAnimation(.easeOut(duration: rippleDuration)) {
            ripple1Scale = 4.0
            ripple1Opacity = 0.0
        }
        ripple1Opacity = 0.55 // initial visible state; interpolates to 0 above
        withAnimation(.easeOut(duration: rippleDuration).delay(0.10)) {
            ripple2Scale = 5.2
            ripple2Opacity = 0.0
        }
        ripple2Opacity = 0.35
        withAnimation(.easeOut(duration: rippleDuration).delay(0.20)) {
            ripple3Scale = 6.4
            ripple3Opacity = 0.0
        }
        ripple3Opacity = 0.22

        // Draw the mark — starts with the drop impact, so the blossom
        // visually emerges from where the ink landed.
        withAnimation(.easeOut(duration: drawDuration)) {
            drawProgress = 1.0
        }

        // Wait for the draw to finish (ripples finish earlier; that's fine).
        try? await Task.sleep(nanoseconds: UInt64(drawDuration * 1_000_000_000))

        // Breathe: glow pulse + gentle 1.05x scale.
        phase = .breathing
        withAnimation(.easeInOut(duration: breatheDuration)) {
            glowOpacity = 1.0
            scale = 1.05
        }
        try? await Task.sleep(nanoseconds: UInt64(breatheDuration * 1_000_000_000))

        // Fade out.
        phase = .fadingOut
        withAnimation(.easeInOut(duration: fadeDuration)) {
            contentOpacity = 0.0
            glowOpacity = 0.0
        }
        try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))

        onFinished()
    }
}

// MARK: - Preview

#Preview("Launch animation") {
    LaunchAnimationView(onFinished: {})
}
