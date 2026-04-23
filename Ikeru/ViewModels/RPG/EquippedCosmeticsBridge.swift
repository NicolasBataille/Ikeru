import Foundation
import IkeruCore

/// Mirrors the equipped cosmetic state from `RPGState` (SwiftData, authoritative)
/// into `UserDefaults` so lightweight views (XP bar, home header) can read them
/// via `@AppStorage` without plumbing a model container everywhere.
///
/// Writes happen from view models after any equip/unequip; reads happen via
/// `@AppStorage` in SwiftUI views.
enum EquippedCosmeticsBridge {

    enum Keys {
        static let titleName = "ikeru.equippedTitleName"
        static let themeName = "ikeru.equippedThemeName"
        static let badgeIcons = "ikeru.equippedBadgeIcons"
    }

    /// Writes the equipped cosmetic names/icons to UserDefaults so SwiftUI views
    /// bound via `@AppStorage` redraw automatically.
    static func sync(state: RPGState) {
        let defaults = UserDefaults.standard
        defaults.set(state.equippedTitle?.name ?? "", forKey: Keys.titleName)
        defaults.set(state.equippedTheme?.name ?? "", forKey: Keys.themeName)
        let icons = state.equippedBadges
            .map(\.iconName)
            .joined(separator: ",")
        defaults.set(icons, forKey: Keys.badgeIcons)
    }
}
