import Foundation

/// Design token definitions for the Ikeru app.
/// Pure value types only - no SwiftUI dependencies.
/// SwiftUI extensions that use these values live in the app target.
public enum IkeruTheme {

    // MARK: - Colors (hex values stored as UInt32 RRGGBB)

    public enum Colors {
        public static let background: UInt32 = 0x1A1A2E
        public static let surface: UInt32 = 0x252540
        public static let primaryAccent: UInt32 = 0xFFB347
        public static let secondaryAccent: UInt32 = 0xFF6B6B
        public static let success: UInt32 = 0x4ECDC4
        public static let kanjiText: UInt32 = 0xF5F0E8
        public static let textPrimary: UInt32 = 0xFFFFFF
        public static let textSecondaryOpacity: Double = 0.6

        // MARK: SRS Stages

        public enum SRS {
            public static let apprentice: UInt32 = 0xFF9A76
            public static let guru: UInt32 = 0xFFB347
            public static let master: UInt32 = 0x4ECDC4
            public static let enlightened: UInt32 = 0xB44AFF
            public static let burned: UInt32 = 0xFFD700
        }

        // MARK: Skill Colors

        public enum Skills {
            public static let reading: UInt32 = 0x4A9EFF
            public static let writing: UInt32 = 0x4ECDC4
            public static let listening: UInt32 = 0xFFB347
            public static let speaking: UInt32 = 0xFF6B6B
        }

        // MARK: Loot Rarity

        public enum Rarity {
            public static let common: UInt32 = 0x808080
            public static let rare: UInt32 = 0x4A9EFF
            public static let epic: UInt32 = 0xB44AFF
            public static let legendary: UInt32 = 0xFFD700
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
            public static let kanjiHero: CGFloat = 64
            public static let kanjiDisplay: CGFloat = 48
            public static let kanjiMedium: CGFloat = 32
            public static let heading1: CGFloat = 28
            public static let heading2: CGFloat = 22
            public static let heading3: CGFloat = 18
            public static let body: CGFloat = 16
            public static let caption: CGFloat = 13
            public static let stats: CGFloat = 14
        }
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    // MARK: - Radius

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let full: CGFloat = 9999
    }

    // MARK: - Animation

    public enum Animation {
        public static let quickDuration: Double = 0.2
        public static let standardDuration: Double = 0.35
        public static let dramaticDuration: Double = 0.6
        public static let dramaticBounce: Double = 0.3
        public static let meshShiftDuration: Double = 4.0
    }

    // MARK: - Shadows

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
            opacity: 0.3,
            radius: 12,
            y: 4
        )

        public static let glow = Definition(
            colorHex: 0xFFB347,
            opacity: 0.3,
            radius: 16
        )

        public static let lootGlow = Definition(
            colorHex: 0xFFB347,
            opacity: 0.3,
            radius: 24
        )
    }
}
