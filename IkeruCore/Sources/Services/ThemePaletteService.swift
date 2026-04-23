import Foundation

/// Pure-function service mapping a cosmetic theme item to a color palette used
/// for UI tinting (XP bar gradient, accent surfaces).
/// Themes are matched by their display name — the same name always yields the
/// same palette.
public enum ThemePaletteService {

    /// Two-stop gradient palette expressed as RRGGBB UInt32s.
    public struct Palette: Equatable, Sendable {
        public let startHex: UInt32
        public let endHex: UInt32

        public init(startHex: UInt32, endHex: UInt32) {
            self.startHex = startHex
            self.endHex = endHex
        }
    }

    /// Default palette when no theme is equipped — matches the original gold XP bar.
    public static let defaultPalette = Palette(
        startHex: IkeruTheme.Colors.primaryAccent,
        endHex: IkeruTheme.Colors.Rarity.legendary
    )

    /// Returns the palette for a given theme name, or the default if unknown/nil.
    public static func palette(forThemeName name: String?) -> Palette {
        guard let name else { return defaultPalette }
        switch name {
        case "Ink Wash":
            return Palette(startHex: 0x4A4E54, endHex: 0x8A8780)
        case "Cherry Blossom":
            return Palette(
                startHex: IkeruTheme.Colors.secondaryAccent,
                endHex: 0xF4D4D8
            )
        case "Mountain Temple":
            return Palette(
                startHex: IkeruTheme.Colors.tertiaryAccent,
                endHex: 0xA8B5A0
            )
        case "Golden Calligraphy":
            return Palette(
                startHex: IkeruTheme.Colors.Rarity.legendary,
                endHex: 0xF0D591
            )
        default:
            return defaultPalette
        }
    }
}
