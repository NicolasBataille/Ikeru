import SwiftUI
import IkeruCore

/// Minimal on-brand color tokens for the Watch and Widget companion surfaces.
///
/// `IkeruWatch` and `IkeruWidget` compile as separate targets from the main `Ikeru`
/// app target, so they can't reach `Ikeru/Views/Shared/Theme/ColorExtensions.swift`
/// (app-target only). Both already link `IkeruCore` as an SPM dependency, so this
/// file re-derives the same hex → `Color` conversion from `IkeruTheme` and exposes
/// just the handful of accents these companion surfaces need — keeping them aligned
/// with the main app's wabi-sabi palette instead of falling back to raw system
/// colors (`.orange`, `.red`, `.black`, ...).
///
/// This file's physical source lives outside both targets' own directories and is
/// added to the Sources build phase of `IkeruWatch` and `IkeruWidget` in the pbxproj.
enum IkeruPlatformTheme {
    /// Sumi ink black — background / neutral dark fills.
    static var ink: Color { Color(ikeruHex: IkeruTheme.Colors.background) }
    /// Kintsugi gold — primary accent, replaces ad-hoc `.orange` / `.blue` tints.
    static var gold: Color { Color(ikeruHex: IkeruTheme.Colors.primaryAccent) }
    /// Terracotta — error / incorrect-answer state, replaces ad-hoc `.red`.
    static var danger: Color { Color(ikeruHex: IkeruTheme.Colors.danger) }
}

private extension Color {
    /// Local hex → `Color` helper (duplicated from the app target's
    /// `ColorExtensions.swift`, which isn't part of the Watch/Widget target
    /// memberships). `private` keeps it scoped to this file only.
    init(ikeruHex hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}
