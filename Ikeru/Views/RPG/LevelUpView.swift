import SwiftUI
import IkeruCore

// MARK: - LevelUpView

/// Full-screen celebration overlay displayed when the user levels up.
/// Tatami DA: ToriiFrame + serif grade kanji, gold-ink palette, kintsugi seam trace,
/// contained scale animation. Auto-dismisses after 2 seconds.
struct LevelUpView: View {

    /// The new level the user reached.
    let newLevel: Int

    /// Callback when the celebration is dismissed.
    var onDismiss: (() -> Void)?

    @State private var overlayOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0
    @State private var seamProgress: CGFloat = 0      // kintsugi seam draw progress [0..1]
    @State private var subtitleOpacity: Double = 0

    // Haptic triggers
    @State private var hapticStage1 = false
    @State private var hapticStage2 = false
    @State private var hapticStage3 = false
    @State private var hapticSuccess = false

    var body: some View {
        ZStack {
            // Dimmed ink background
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .opacity(overlayOpacity)

            VStack(spacing: IkeruTheme.Spacing.lg) {
                // ToriiFrame rank crest — hero moment
                ToriiFrame(color: .ikeruPrimaryAccent, lineWidth: 4) {
                    Text(rankKanji(newLevel))
                        .font(.system(size: 44, weight: .light, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                .frame(width: 120, height: 120)

                // Kintsugi seam — animated gold trace beneath the crest
                KintsugiSeamView(progress: seamProgress)
                    .frame(width: 160, height: 18)

                // 段 grade label (e.g. "第五段")
                Text("第\(kanjiNumeral(newLevel))段")
                    .font(.system(size: IkeruTheme.Typography.Size.displaySmall, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .tracking(IkeruTheme.Typography.Tracking.display)

                // Subtitle
                Text("New rank achieved")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
                    .tracking(IkeruTheme.Typography.Tracking.caption)
                    .opacity(subtitleOpacity)
            }
            .padding(IkeruTheme.Spacing.xl)
            .background(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.122, green: 0.102, blue: 0.071, opacity: 0.95),
                                Color(red: 0.08, green: 0.07, blue: 0.05, opacity: 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(alignment: .top) { FusumaRail(gold: .ikeruPrimaryAccent, opacity: 1.0) }
            .overlay(alignment: .bottom) { FusumaRail(gold: .ikeruPrimaryAccent, opacity: 1.0, inverted: true) }
            .sumiCorners(color: .ikeruPrimaryAccent, size: 12, weight: 2.0)
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
            .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticStage1)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticStage2)
        .sensoryFeedback(.impact(weight: .heavy), trigger: hapticStage3)
        .sensoryFeedback(.success, trigger: hapticSuccess)
        .onAppear {
            playEntrance()
        }
    }

    // MARK: - Animation Sequence

    private func playEntrance() {
        // Background fade in
        withAnimation(.easeIn(duration: 0.25)) {
            overlayOpacity = 1
        }

        // Card settle — contained, dignified (no overshooting spring)
        withAnimation(.spring(duration: 0.45, bounce: 0.10)) {
            cardScale = 1.0
            cardOpacity = 1.0
        }

        // Haptic crescendo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { hapticStage1.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { hapticStage2.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hapticStage3.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { hapticSuccess.toggle() }

        // Kintsugi seam draws after card arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.7)) {
                seamProgress = 1.0
            }
        }

        // Subtitle fades in after seam
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeIn(duration: 0.4)) {
                subtitleOpacity = 1.0
            }
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                overlayOpacity = 0
                cardOpacity = 0
                cardScale = 1.04
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss?()
            }
        }
    }

    // MARK: - Helpers

    /// Daiji numeral for ranks 1–10, fallback to arabic for higher.
    private func rankKanji(_ n: Int) -> String {
        let lookup: [Int: String] = [
            1: "一", 2: "二", 3: "三", 4: "四", 5: "五",
            6: "六", 7: "七", 8: "八", 9: "九", 10: "十"
        ]
        return lookup[n] ?? "\(n)"
    }

    /// Kanji numeral for the 第N段 label (same as rankKanji but exposed for interpolation).
    private func kanjiNumeral(_ n: Int) -> String {
        rankKanji(n)
    }
}

// MARK: - KintsugiSeamView

/// Animated gold seam that draws in from centre outward, evoking kintsugi repair.
/// `progress` drives the stroke trim from 0 (hidden) to 1 (fully revealed).
private struct KintsugiSeamView: View {
    let progress: CGFloat   // [0..1]

    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            let w = size.width

            // Draw two seam branches: left branch and right branch, from centre out
            let midX = w * 0.5

            // Left arm: midX → 0
            let leftProgress = min(progress * 2, 1.0)   // leads first half
            let rightProgress = max((progress - 0.5) * 2, 0.0) // follows second half

            // Seam path — a shallow double-arc evoking a cracked repair
            var seamPath = Path()
            // Left branch (draw from centre to left)
            if leftProgress > 0 {
                let targetX = midX - (midX * leftProgress)
                seamPath.move(to: CGPoint(x: midX, y: midY))
                seamPath.addQuadCurve(
                    to: CGPoint(x: targetX, y: midY),
                    control: CGPoint(x: midX - (midX * leftProgress * 0.5), y: midY - 4)
                )
            }
            // Right branch (draw from centre to right)
            if rightProgress > 0 {
                let targetX = midX + ((w - midX) * rightProgress)
                seamPath.move(to: CGPoint(x: midX, y: midY))
                seamPath.addQuadCurve(
                    to: CGPoint(x: targetX, y: midY),
                    control: CGPoint(x: midX + ((w - midX) * rightProgress * 0.5), y: midY + 3)
                )
            }

            // Glow pass
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 3))
            glowCtx.opacity = 0.5
            glowCtx.stroke(
                seamPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hex: 0x8A6D4A, opacity: 0),
                        Color(hex: 0xE5BC8A),
                        Color(hex: 0x8A6D4A, opacity: 0)
                    ]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: w, y: midY)
                ),
                lineWidth: 4
            )

            // Core seam
            context.stroke(
                seamPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hex: 0x8A6D4A, opacity: 0),
                        Color(hex: 0xD4A574),
                        Color(hex: 0x8A6D4A, opacity: 0)
                    ]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: w, y: midY)
                ),
                lineWidth: 1.2
            )
        }
    }
}

// MARK: - Level Up Overlay Modifier

/// View modifier that shows the level-up celebration as a full-screen overlay.
struct LevelUpOverlayModifier: ViewModifier {

    /// Binding to the new level to celebrate. Set to nil to hide.
    @Binding var levelUpLevel: Int?

    func body(content: Content) -> some View {
        content.overlay {
            if let level = levelUpLevel {
                LevelUpView(newLevel: level) {
                    levelUpLevel = nil
                }
                .transition(.opacity)
            }
        }
    }
}

extension View {
    /// Shows a full-screen level-up celebration when levelUpLevel is non-nil.
    func levelUpOverlay(level: Binding<Int?>) -> some View {
        modifier(LevelUpOverlayModifier(levelUpLevel: level))
    }
}

// MARK: - Preview

#Preview("LevelUpView") {
    LevelUpView(newLevel: 5)
        .preferredColorScheme(.dark)
}

#Preview("LevelUpView — rank 3") {
    LevelUpView(newLevel: 3)
        .preferredColorScheme(.dark)
}
