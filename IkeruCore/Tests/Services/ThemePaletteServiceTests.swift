import Testing
@testable import IkeruCore

@Suite("ThemePaletteService")
struct ThemePaletteServiceTests {

    @Test("Default palette matches the ungated ProgressBar tokens (no visual regression)")
    func defaultPaletteMatchesProgressBarTokens() {
        #expect(ThemePaletteService.defaultPalette.startHex == IkeruTheme.Colors.ProgressBar.filledStart)
        #expect(ThemePaletteService.defaultPalette.endHex == IkeruTheme.Colors.ProgressBar.filledEnd)
    }

    @Test("A nil theme name resolves to the default palette")
    func nilThemeNameResolvesToDefault() {
        #expect(ThemePaletteService.palette(forThemeName: nil) == ThemePaletteService.defaultPalette)
    }

    @Test("An unknown theme name resolves to the default palette")
    func unknownThemeNameResolvesToDefault() {
        #expect(ThemePaletteService.palette(forThemeName: "Nonexistent Theme") == ThemePaletteService.defaultPalette)
    }

    @Test("Every known theme name returns a distinct, valid palette")
    func knownThemeNamesReturnDistinctPalettes() {
        let names = ["Ink Wash", "Cherry Blossom", "Mountain Temple", "Golden Calligraphy"]
        let palettes = names.map { ThemePaletteService.palette(forThemeName: $0) }
        #expect(Set(palettes).count == names.count)
    }
}
