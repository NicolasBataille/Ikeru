import Foundation

/// Design tokens for Ikeru — wabi-sabi inspired premium design system.
/// Pure value types only. SwiftUI extensions live in the app target.
///
/// Design philosophy:
/// - Wabi-sabi: imperfect, weathered, quiet beauty
/// - Negative space as a design element
/// - Subtle warmth over saturated brightness
/// - Movement through stillness — animations are calm and purposeful
public enum IkeruTheme {

    // MARK: - Colors (hex values stored as UInt32 RRGGBB)

    public enum Colors {
        // Backgrounds — deep, warm-cool blacks
        public static let background: UInt32 = 0x0A0A0F        // sumi (ink black)
        public static let backgroundElevated: UInt32 = 0x12121A
        public static let surface: UInt32 = 0x18181F           // raised surface
        public static let surfaceElevated: UInt32 = 0x1F1F28

        // Glass — used as Color.white opacities for translucent layers
        public static let glassFillOpacity: Double = 0.06
        public static let glassStrokeOpacity: Double = 0.12
        public static let glassHighlightOpacity: Double = 0.18

        // Accents — refined, less saturated than typical
        public static let primaryAccent: UInt32 = 0xD4A574     // warm gold (kintsugi)
        public static let secondaryAccent: UInt32 = 0xE8B4B8   // sakura (powdered pink)
        public static let tertiaryAccent: UInt32 = 0x7A8471    // matcha (sage green)
        public static let success: UInt32 = 0x8FBCA0           // moss
        public static let warning: UInt32 = 0xE0A062           // amber
        public static let danger: UInt32 = 0xC97064            // terracotta

        // Text — warm whites, never pure
        public static let textPrimary: UInt32 = 0xF5F2EC       // washi paper
        public static let textSecondary: UInt32 = 0xB8B5B0     // muted
        public static let textTertiary: UInt32 = 0x7A7770      // disabled

        // Legacy alias retained for compatibility (kanji on light surfaces)
        public static let kanjiText: UInt32 = 0xF5F2EC
        public static let textSecondaryOpacity: Double = 0.70

        // MARK: SRS Stages — soft palette
        public enum SRS {
            public static let apprentice: UInt32 = 0xC97064   // terracotta
            public static let guru: UInt32 = 0xD4A574         // gold
            public static let master: UInt32 = 0x7A8471       // matcha
            public static let enlightened: UInt32 = 0x9580B5  // murasaki (purple)
            public static let burned: UInt32 = 0xE8B4B8       // sakura
        }

        // MARK: Skill Colors — coordinated, less neon
        public enum Skills {
            public static let reading: UInt32 = 0x6B92B5      // dusk blue
            public static let writing: UInt32 = 0x7A8471      // matcha
            public static let listening: UInt32 = 0xD4A574    // gold
            public static let speaking: UInt32 = 0xC97064     // terracotta
        }

        // MARK: Loot Rarity
        public enum Rarity {
            public static let common: UInt32 = 0x8A8780
            public static let rare: UInt32 = 0x6B92B5
            public static let epic: UInt32 = 0x9580B5
            public static let legendary: UInt32 = 0xD4A574
        }
    }

    // MARK: - Typography

    public enum Typography {
        public enum FontFamily {
            public static let kanjiSerif = "NotoSerifJP-Bold"
            public static let kanjiSerifMedium = "NotoSerifJP-Medium"
            public static let system = "SFPro"
            public static let mono = "SFMono"
        }

        public enum Size {
            // Display — for hero moments
            public static let displayLarge: CGFloat = 56
            public static let displayMedium: CGFloat = 44
            public static let displaySmall: CGFloat = 36

            // Kanji
            public static let kanjiHero: CGFloat = 96
            public static let kanjiDisplay: CGFloat = 64
            public static let kanjiMedium: CGFloat = 40
            public static let kanjiInline: CGFloat = 24

            // Headings
            public static let heading1: CGFloat = 32
            public static let heading2: CGFloat = 24
            public static let heading3: CGFloat = 19

            // Body
            public static let bodyLarge: CGFloat = 17
            public static let body: CGFloat = 15
            public static let bodySmall: CGFloat = 13

            public static let caption: CGFloat = 12
            public static let micro: CGFloat = 11

            public static let stats: CGFloat = 14
        }

        public enum Tracking {
            public static let display: CGFloat = -1.2
            public static let heading: CGFloat = -0.6
            public static let body: CGFloat = -0.2
            public static let caption: CGFloat = 0.4
            public static let micro: CGFloat = 0.8
        }
    }

    // MARK: - Spacing — generous, breathing

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 36
        public static let xxl: CGFloat = 56
        public static let xxxl: CGFloat = 80
    }

    // MARK: - Radius — softer corners

    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 18
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 44
        public static let full: CGFloat = 9999
    }

    // MARK: - Animation — calm, purposeful

    public enum Animation {
        public static let quickDuration: Double = 0.18
        public static let standardDuration: Double = 0.32
        public static let dramaticDuration: Double = 0.55
        public static let dramaticBounce: Double = 0.28
        public static let meshShiftDuration: Double = 8.0

        // Spring response/damping pairs
        public static let snappyResponse: Double = 0.28
        public static let snappyDamping: Double = 0.86

        public static let smoothResponse: Double = 0.45
        public static let smoothDamping: Double = 0.92

        public static let bouncyResponse: Double = 0.55
        public static let bouncyDamping: Double = 0.72
    }

    // MARK: - Shadows — soft, warm

    public enum Shadow {
        public struct Definition: Sendable, Equatable {
            public let colorHex: UInt32
            public let opacity: Double
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat

            public init(colorHex: UInt32, opacity: Double, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
                self.colorHex = colorHex
                self.opacity = opacity
                self.radius = radius
                self.x = x
                self.y = y
            }
        }

        public static let card = Definition(
            colorHex: 0x000000,
            opacity: 0.45,
            radius: 24,
            y: 8
        )

        public static let glow = Definition(
            colorHex: 0xD4A574,
            opacity: 0.25,
            radius: 32
        )

        public static let lootGlow = Definition(
            colorHex: 0xD4A574,
            opacity: 0.35,
            radius: 40
        )

        public static let elevated = Definition(
            colorHex: 0x000000,
            opacity: 0.6,
            radius: 40,
            y: 12
        )
    }
}
