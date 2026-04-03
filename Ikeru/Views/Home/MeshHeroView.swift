import SwiftUI
import IkeruCore

// MARK: - MeshHeroView

/// Animated MeshGradient hero section for the home screen.
/// Colors shift slowly based on RPG level:
/// - Low levels (1-9): blues (calm, beginning)
/// - Mid levels (10-19): teals (growing, exploration)
/// - High levels (20+): golds (mastery, achievement)
struct MeshHeroView: View {

    /// Current RPG level (determines color palette).
    let level: Int

    /// Total XP for the XP bar.
    let totalXP: Int

    /// Display name for greeting.
    let displayName: String

    /// Recent achievement text (e.g., "Unlocked Listening!").
    let recentAchievement: String?

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated mesh gradient background
            meshGradient
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg))

            // Content overlay
            VStack(spacing: IkeruTheme.Spacing.sm) {
                // Greeting
                Text(greetingText)
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4)

                Text("Level \(level)")
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 2)

                // XP Bar
                XPBarView(totalXP: totalXP, level: level, variant: .full)
                    .padding(.horizontal, IkeruTheme.Spacing.lg)

                // Recent achievement badge
                if let achievement = recentAchievement {
                    HStack(spacing: IkeruTheme.Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.ikeruCaption)
                        Text(achievement)
                            .font(.ikeruCaption)
                    }
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.legendary))
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, IkeruTheme.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                    )
                }
            }
            .padding(IkeruTheme.Spacing.lg)
        }
        .onAppear {
            withAnimation(
                .linear(duration: IkeruTheme.Animation.meshShiftDuration)
                    .repeatForever(autoreverses: true)
            ) {
                animationPhase = 1
            }
        }
    }

    // MARK: - Greeting

    private var greetingText: String {
        if !displayName.isEmpty {
            return "Welcome, \(displayName)!"
        }
        return "Welcome!"
    }

    // MARK: - Mesh Gradient

    @ViewBuilder
    private var meshGradient: some View {
        if #available(iOS 18.0, *) {
            meshGradientIOS18
        } else {
            // Fallback for iOS 17
            linearGradientFallback
        }
    }

    @available(iOS 18.0, *)
    private var meshGradientIOS18: some View {
        let palette = colorPalette
        let p = Float(animationPhase)

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                // Row 0
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5 + 0.1 * sin(p * .pi), 0.0),
                SIMD2<Float>(1.0, 0.0),
                // Row 1
                SIMD2<Float>(0.0, 0.5 + 0.05 * cos(p * .pi)),
                SIMD2<Float>(0.5 + 0.15 * cos(p * .pi * 2), 0.5 + 0.1 * sin(p * .pi)),
                SIMD2<Float>(1.0, 0.5 - 0.05 * sin(p * .pi)),
                // Row 2
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5 - 0.1 * cos(p * .pi), 1.0),
                SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                palette.0, palette.1, palette.2,
                palette.1, palette.3, palette.0,
                palette.2, palette.0, palette.1,
            ]
        )
    }

    private var linearGradientFallback: some View {
        let palette = colorPalette
        return LinearGradient(
            colors: [palette.0, palette.1, palette.2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Color Palette by Level

    /// Returns 4 colors for the mesh gradient based on current RPG level.
    private var colorPalette: (Color, Color, Color, Color) {
        switch level {
        case 1...9:
            // Blues — calm beginning
            return (
                Color(red: 0.1, green: 0.15, blue: 0.35),
                Color(red: 0.15, green: 0.25, blue: 0.5),
                Color(red: 0.1, green: 0.2, blue: 0.45),
                Color(red: 0.2, green: 0.3, blue: 0.55)
            )
        case 10...19:
            // Teals — growing exploration
            return (
                Color(red: 0.1, green: 0.25, blue: 0.3),
                Color(red: 0.15, green: 0.35, blue: 0.35),
                Color(red: 0.1, green: 0.3, blue: 0.35),
                Color(red: 0.2, green: 0.4, blue: 0.4)
            )
        default:
            // Golds — mastery
            return (
                Color(red: 0.3, green: 0.22, blue: 0.1),
                Color(red: 0.4, green: 0.3, blue: 0.12),
                Color(red: 0.35, green: 0.25, blue: 0.1),
                Color(red: 0.45, green: 0.35, blue: 0.15)
            )
        }
    }
}

// MARK: - Preview

#Preview("MeshHeroView — Low Level") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        MeshHeroView(level: 3, totalXP: 150, displayName: "Nico", recentAchievement: nil)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("MeshHeroView — Mid Level") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        MeshHeroView(level: 12, totalXP: 2500, displayName: "Nico", recentAchievement: "Unlocked Listening!")
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("MeshHeroView — High Level") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        MeshHeroView(level: 25, totalXP: 8000, displayName: "Nico", recentAchievement: "Sage of Languages")
            .padding()
    }
    .preferredColorScheme(.dark)
}
