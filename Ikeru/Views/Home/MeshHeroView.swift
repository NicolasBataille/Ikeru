import SwiftUI
import IkeruCore

// MARK: - MeshHeroView

/// Premium hero panel with slowly drifting MeshGradient and glass overlay.
/// Color palette evolves with progression — calm blues → matcha → warm gold.
struct MeshHeroView: View {

    let level: Int
    let totalXP: Int
    let displayName: String
    let recentAchievement: String?

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated mesh gradient background
            meshGradient
                .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.55), radius: 32, y: 16)

            // Vignette overlay for content legibility
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Content overlay
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                // Top row: level eyebrow + achievement chip
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LEVEL \(level)")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.white.opacity(0.7))

                        Text(rankTitle)
                            .font(.system(size: 30, weight: .light, design: .default))
                            .ikeruTracking(.display)
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    }
                    Spacer()
                    if let achievement = recentAchievement {
                        achievementChip(achievement)
                    }
                }

                Spacer()

                // Japanese aphorism — quiet inspiration
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(currentAphorism.kanji)
                        .font(.custom(IkeruTheme.Typography.FontFamily.kanjiSerifMedium, size: 22))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(currentAphorism.romaji)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                // XP progress bar
                xpBar
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

    // MARK: - Achievement chip

    @ViewBuilder
    private func achievementChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
        }
    }

    // MARK: - XP Bar

    @ViewBuilder
    private var xpBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Experience")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text("\(totalXP) XP")
                    .font(.ikeruStats)
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xF5DBB6),
                                    Color(hex: 0xD4A574)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progressFraction)
                        .shadow(color: Color(hex: 0xD4A574, opacity: 0.5), radius: 8)
                }
            }
            .frame(height: 6)
        }
    }

    private var progressFraction: Double {
        let xpForCurrentLevel = (level - 1) * 100
        let xpForNextLevel = level * 100
        let denom = max(1, xpForNextLevel - xpForCurrentLevel)
        let inLevel = max(0, totalXP - xpForCurrentLevel)
        return min(1.0, max(0.05, Double(inLevel) / Double(denom)))
    }

    // MARK: - Rank title (varies by level)

    private var rankTitle: String {
        switch level {
        case 0...4:    return "Apprentice"
        case 5...9:    return "Student"
        case 10...14:  return "Adept"
        case 15...19:  return "Practitioner"
        case 20...24:  return "Wayfarer"
        case 25...29:  return "Sensei"
        default:       return "Master"
        }
    }

    // MARK: - Aphorism

    private struct Aphorism {
        let kanji: String
        let romaji: String
    }

    private var currentAphorism: Aphorism {
        // Stable per-level so it doesn't flicker
        let aphorisms: [Aphorism] = [
            Aphorism(kanji: "\u{4E03}\u{8EE2}\u{516B}\u{8D77}", romaji: "nana korobi ya oki — fall seven times, rise eight"),
            Aphorism(kanji: "\u{4E00}\u{671F}\u{4E00}\u{4F1A}", romaji: "ichi-go ichi-e — one time, one meeting"),
            Aphorism(kanji: "\u{6708}\u{4E0B}\u{8001}\u{4EBA}", romaji: "gekka rōjin — fated by the moon"),
            Aphorism(kanji: "\u{521D}\u{5FC3}", romaji: "shoshin — beginner's mind"),
            Aphorism(kanji: "\u{6709}\u{8A00}\u{5B9F}\u{884C}", romaji: "yūgen jikkō — words become deeds"),
        ]
        return aphorisms[max(0, level - 1) % aphorisms.count]
    }

    // MARK: - Mesh Gradient

    @ViewBuilder
    private var meshGradient: some View {
        if #available(iOS 18.0, *) {
            meshGradientIOS18
        } else {
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
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5 + 0.08 * sin(p * .pi), 0.0),
                SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5 + 0.05 * cos(p * .pi)),
                SIMD2<Float>(0.5 + 0.12 * cos(p * .pi * 2), 0.5 + 0.08 * sin(p * .pi)),
                SIMD2<Float>(1.0, 0.5 - 0.05 * sin(p * .pi)),
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5 - 0.08 * cos(p * .pi), 1.0),
                SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                palette.0, palette.1, palette.2,
                palette.1, palette.3, palette.0,
                palette.2, palette.0, palette.1,
            ],
            smoothsColors: true
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

    // MARK: - Color palette by level

    /// Returns 4 colors for the mesh gradient based on current RPG level.
    /// Palette is muted, warm-cool balanced, with depth.
    private var colorPalette: (Color, Color, Color, Color) {
        switch level {
        case 1...9:
            // Twilight blues — calm beginning
            return (
                Color(hex: 0x1A1F35),
                Color(hex: 0x2A3550),
                Color(hex: 0x1F2942),
                Color(hex: 0x344165)
            )
        case 10...19:
            // Matcha + dusk — growing exploration
            return (
                Color(hex: 0x1A2A28),
                Color(hex: 0x2C3F38),
                Color(hex: 0x223530),
                Color(hex: 0x3A4F46)
            )
        case 20...29:
            // Dusk gold — refined progression
            return (
                Color(hex: 0x2A2018),
                Color(hex: 0x3C2D1F),
                Color(hex: 0x352618),
                Color(hex: 0x4D3925)
            )
        default:
            // Kintsugi gold — mastery
            return (
                Color(hex: 0x382818),
                Color(hex: 0x55392A),
                Color(hex: 0x453020),
                Color(hex: 0x6B4830)
            )
        }
    }
}

// MARK: - MeshHeroBackground
//
// The mesh-gradient substrate from MeshHeroView, decoupled from its content
// so the wabi-sabi Home hero can use it as an animated background while
// keeping its own EnsoRank + proverb + segmented-XP overlay.

struct MeshHeroBackground: View {
    let level: Int
    var cornerRadius: CGFloat = IkeruTheme.Radius.lg

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            meshGradient
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Soft inner darkening so foreground text stays legible on the
            // brighter parts of the mesh — wabi-sabi prefers quieter contrast.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.20),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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

    @ViewBuilder
    private var meshGradient: some View {
        if #available(iOS 18.0, *) {
            meshGradientIOS18
        } else {
            linearFallback
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
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5 + 0.08 * sin(p * .pi), 0.0),
                SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5 + 0.05 * cos(p * .pi)),
                SIMD2<Float>(0.5 + 0.12 * cos(p * .pi * 2), 0.5 + 0.08 * sin(p * .pi)),
                SIMD2<Float>(1.0, 0.5 - 0.05 * sin(p * .pi)),
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5 - 0.08 * cos(p * .pi), 1.0),
                SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                palette.0, palette.1, palette.2,
                palette.1, palette.3, palette.0,
                palette.2, palette.0, palette.1,
            ],
            smoothsColors: true
        )
    }

    private var linearFallback: some View {
        let palette = colorPalette
        return LinearGradient(
            colors: [palette.0, palette.1, palette.2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var colorPalette: (Color, Color, Color, Color) {
        switch level {
        case 1...9:
            return (
                Color(hex: 0x1A1F35),
                Color(hex: 0x2A3550),
                Color(hex: 0x1F2942),
                Color(hex: 0x344165)
            )
        case 10...19:
            return (
                Color(hex: 0x1A2A28),
                Color(hex: 0x2C3F38),
                Color(hex: 0x223530),
                Color(hex: 0x3A4F46)
            )
        case 20...29:
            return (
                Color(hex: 0x2A2018),
                Color(hex: 0x3C2D1F),
                Color(hex: 0x352618),
                Color(hex: 0x4D3925)
            )
        default:
            return (
                Color(hex: 0x382818),
                Color(hex: 0x55392A),
                Color(hex: 0x453020),
                Color(hex: 0x6B4830)
            )
        }
    }
}

// MARK: - Preview

#Preview("MeshHeroView — Low Level") {
    ZStack {
        IkeruScreenBackground()
        MeshHeroView(level: 3, totalXP: 150, displayName: "Nico", recentAchievement: nil)
            .frame(height: 260)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("MeshHeroView — Mid Level") {
    ZStack {
        IkeruScreenBackground()
        MeshHeroView(level: 12, totalXP: 1240, displayName: "Nico", recentAchievement: "Listening Unlocked")
            .frame(height: 260)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("MeshHeroView — High Level") {
    ZStack {
        IkeruScreenBackground()
        MeshHeroView(level: 25, totalXP: 8000, displayName: "Nico", recentAchievement: "Sage of Languages")
            .frame(height: 260)
            .padding()
    }
    .preferredColorScheme(.dark)
}
