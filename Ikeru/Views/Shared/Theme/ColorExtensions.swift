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

// MARK: - Convenience Theme Color Accessors

extension Color {
    static var ikeruBackground: Color {
        Color(hex: IkeruTheme.Colors.background)
    }

    static var ikeruSurface: Color {
        Color(hex: IkeruTheme.Colors.surface)
    }

    static var ikeruPrimaryAccent: Color {
        Color(hex: IkeruTheme.Colors.primaryAccent)
    }

    static var ikeruSecondaryAccent: Color {
        Color(hex: IkeruTheme.Colors.secondaryAccent)
    }

    static var ikeruSuccess: Color {
        Color(hex: IkeruTheme.Colors.success)
    }

    static var ikeruKanjiText: Color {
        Color(hex: IkeruTheme.Colors.kanjiText)
    }

    static var ikeruTextSecondary: Color {
        Color.white.opacity(IkeruTheme.Colors.textSecondaryOpacity)
    }
}
