import SwiftUI
import IkeruCore

// MARK: - LevelUpView

/// Full-screen celebration overlay displayed when the user levels up.
/// Features a dramatic spring animation, haptic crescendo, and auto-dismisses after 2 seconds.
struct LevelUpView: View {

    /// The new level the user reached.
    let newLevel: Int

    /// Callback when the celebration is dismissed.
    var onDismiss: (() -> Void)?

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var labelOffset: CGFloat = 30
    @State private var hapticStage1 = false
    @State private var hapticStage2 = false
    @State private var hapticStage3 = false
    @State private var hapticSuccess = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .opacity(opacity)

            VStack(spacing: IkeruTheme.Spacing.lg) {
                // Star burst icon
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
                    .scaleEffect(scale)

                // "LEVEL UP!" text
                Text("LEVEL UP!")
                    .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .black))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
                    .offset(y: labelOffset)
                    .opacity(opacity)

                // Level number
                Text("Level \(newLevel)")
                    .font(.system(size: IkeruTheme.Typography.Size.kanjiDisplay, weight: .bold))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
                    .shadow(
                        color: Color(hex: IkeruTheme.Colors.Rarity.legendary).opacity(0.5),
                        radius: 12
                    )
                    .scaleEffect(scale)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticStage1)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticStage2)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticStage3)
        .sensoryFeedback(.success, trigger: hapticSuccess)
        .onAppear {
            playEntrance()
        }
    }

    // MARK: - Animation Sequence

    private func playEntrance() {
        // Dramatic spring animation
        withAnimation(
            .spring(
                duration: IkeruTheme.Animation.dramaticDuration,
                bounce: IkeruTheme.Animation.dramaticBounce
            )
        ) {
            scale = 1.0
            opacity = 1.0
            labelOffset = 0
        }

        // Haptic crescendo: 3x .impact(.medium) then .notification(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hapticStage1.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            hapticStage2.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            hapticStage3.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            hapticSuccess.toggle()
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
                scale = 1.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss?()
            }
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
