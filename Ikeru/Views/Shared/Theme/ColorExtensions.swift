import SwiftUI
import IkeruCore

// MARK: - Color from Hex

extension Color {
    /// Creates a Color from a hex UInt32 value (0xRRGGBB format).
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Theme Color Accessors

extension Color {
    // Backgrounds
    static var ikeruBackground: Color { Color(hex: IkeruTheme.Colors.background) }
    static var ikeruSurface: Color { Color(hex: IkeruTheme.Colors.surface) }

    // Accents
    static var ikeruPrimaryAccent: Color { Color(hex: IkeruTheme.Colors.primaryAccent) }
    static var ikeruSecondaryAccent: Color { Color(hex: IkeruTheme.Colors.secondaryAccent) }
    static var ikeruTertiaryAccent: Color { Color(hex: IkeruTheme.Colors.tertiaryAccent) }
    static var ikeruSuccess: Color { Color(hex: IkeruTheme.Colors.success) }
    static var ikeruWarning: Color { Color(hex: IkeruTheme.Colors.warning) }
    static var ikeruDanger: Color { Color(hex: IkeruTheme.Colors.danger) }
    static var ikeruError: Color { Color(hex: IkeruTheme.Colors.danger) }

    // Text
    static var ikeruTextPrimary: Color { Color(hex: IkeruTheme.Colors.textPrimary) }
    static var ikeruTextSecondary: Color { Color(hex: IkeruTheme.Colors.textSecondary) }
    static var ikeruTextTertiary: Color { Color(hex: IkeruTheme.Colors.textTertiary) }
    static var ikeruKanjiText: Color { Color(hex: IkeruTheme.Colors.kanjiText) }
}

// MARK: - ShapeStyle Convenience Accessors

extension ShapeStyle where Self == Color {
    // Backgrounds
    static var ikeruBackground: Color { Color.ikeruBackground }
    static var ikeruSurface: Color { Color.ikeruSurface }

    // Accents
    static var ikeruPrimaryAccent: Color { Color.ikeruPrimaryAccent }
    static var ikeruSecondaryAccent: Color { Color.ikeruSecondaryAccent }
    static var ikeruTertiaryAccent: Color { Color.ikeruTertiaryAccent }
    static var ikeruSuccess: Color { Color.ikeruSuccess }
    static var ikeruWarning: Color { Color.ikeruWarning }
    static var ikeruDanger: Color { Color.ikeruDanger }
    static var ikeruError: Color { Color.ikeruError }

    // Text
    static var ikeruTextPrimary: Color { Color.ikeruTextPrimary }
    static var ikeruTextSecondary: Color { Color.ikeruTextSecondary }
    static var ikeruTextTertiary: Color { Color.ikeruTextTertiary }
    static var ikeruKanjiText: Color { Color.ikeruKanjiText }
}

// MARK: - Premium Gradients

extension LinearGradient {
    /// Subtle warm gradient for hero backgrounds.
    static var ikeruHeroWarm: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0x1A1218),
                Color(hex: 0x0F0D14),
                Color(hex: 0x0A0A0F)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Gold accent gradient for buttons and highlights.
    static var ikeruGold: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0xE5BC8A),
                Color(hex: 0xD4A574),
                Color(hex: 0xB88A5C)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Glass highlight — top edge sheen.
    static var ikeruGlassEdge: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.04),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

