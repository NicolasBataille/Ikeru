import SwiftUI

// MARK: - Launch Animation
//
// Plays once on cold start. ~2.0s contemplative pacing:
//   0.0s → logo invisible, dark warm background
//   0.1s → stem draws bottom-to-top (ease-out)
//   0.5s → leaves draw
//   0.9s → bloom petals open
//   1.4s → warm glow pulse + 1.05x scale breathe
//   1.7s → fade out, caller transitions to main UI
//
// Orchestrated via a `@State phase: LaunchPhase` enum driving per-property
// `withAnimation` blocks — clean, precise, no `phaseAnimator` magic.

enum LaunchPhase {
    case initial
    case drawing   // stem → leaves → bloom
    case breathing // glow pulse + scale
    case fadingOut
}

struct LaunchAnimationView: View {
    let onFinished: () -> Void

    @State private var phase: LaunchPhase = .initial
    @State private var drawProgress: Double = 0.0
    @State private var glowOpacity: Double = 0.0
    @State private var scale: CGFloat = 0.96
    @State private var contentOpacity: Double = 1.0

    // Timing constants (seconds from phase start).
    private let drawDuration: Double = 1.3
    private let breatheDuration: Double = 0.3
    private let fadeDuration: Double = 0.3

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

            IkeruLogoView(progress: drawProgress)
                .frame(width: 220, height: 220)
                .scaleEffect(scale)
        }
        .opacity(contentOpacity)
        .task {
            await runSequence()
        }
    }

    // MARK: - Sequence

    @MainActor
    private func runSequence() async {
        // 0.0 → 0.1s hold (background only).
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 0.1s → draw the mark. All strokes animate via a single shared
        // `drawProgress` variable; each stroke's own timing window lives
        // inside IkeruLogoView.
        phase = .drawing
        withAnimation(.easeOut(duration: drawDuration)) {
            drawProgress = 1.0
        }

        // Wait for draw to finish (~1.4s mark).
        try? await Task.sleep(nanoseconds: UInt64(drawDuration * 1_000_000_000))

        // 1.4s → breathe: glow pulse + gentle 1.05x scale.
        phase = .breathing
        withAnimation(.easeInOut(duration: breatheDuration)) {
            glowOpacity = 1.0
            scale = 1.05
        }

        try? await Task.sleep(nanoseconds: UInt64(breatheDuration * 1_000_000_000))

        // 1.7s → fade out.
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
