import SwiftUI
import Observation

// MARK: - LanguagePreference

enum LanguagePreference: String, Sendable, CaseIterable {
    case system  // auto-detect from device
    case en      // force English
    case fr      // force French
}

// MARK: - AppLocale
//
// Source of truth for the UI language. Reads `@AppStorage` and exposes a
// `currentLocale: Locale` to inject via `\.locale` at the root view. The
// auto-detection rule: if any of the device's preferred languages start
// with `"fr"`, default to French; otherwise English.

@Observable
final class AppLocale {
    static let storageKey = "ikeru.uiLanguage"

    private(set) var preference: LanguagePreference {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Self.storageKey) }
    }

    init(preference: LanguagePreference? = nil) {
        if let preference {
            self.preference = preference
        } else if
            let raw = UserDefaults.standard.string(forKey: Self.storageKey),
            let stored = LanguagePreference(rawValue: raw)
        {
            self.preference = stored
        } else {
            self.preference = .system
        }
    }

    /// Update the preference and persist it.
    func setPreference(_ new: LanguagePreference) { preference = new }

    /// Resolve the locale to inject into `\.environment(\.locale, _)`.
    var currentLocale: Locale {
        Self.resolve(preference: preference, preferredLanguages: Locale.preferredLanguages)
    }

    /// Le bundle de strings de CETTE langue, pour le texte runtime (`String`)
    /// qui doit suivre l'interface et non l'appareil.
    ///
    /// `String(localized:)` seul lit `Bundle.main` dans la langue système, et
    /// son paramètre `locale:` ne choisit PAS le `.lproj` (mesuré le
    /// 2026-09-10 : `String(localized: "Again", locale: en)` rendait « Encore »
    /// sur un simulateur en français). Il faut ouvrir le `.lproj` de la langue
    /// et le passer en `bundle:`. Repli sur `Bundle.main` si la langue n'a
    /// pas de dossier.
    static func bundle(for locale: Locale) -> Bundle {
        guard
            let code = locale.language.languageCode?.identifier,
            let url = Bundle.main.url(forResource: code, withExtension: "lproj"),
            let bundle = Bundle(url: url)
        else { return .main }
        return bundle
    }

    // MARK: - Pure helpers (testable)

    /// Resolve a locale given a preference and the device's preferred-language list.
    static func resolve(preference: LanguagePreference, preferredLanguages: [String]) -> Locale {
        switch preference {
        case .en: return Locale(identifier: "en")
        case .fr: return Locale(identifier: "fr")
        case .system: return resolveSystem(preferredLanguages: preferredLanguages)
        }
    }

    /// Auto-detect rule: French if any preferred language begins with "fr",
    /// otherwise English. Used when the user's preference is `.system`.
    static func resolveSystem(preferredLanguages: [String]) -> Locale {
        if preferredLanguages.contains(where: { $0.lowercased().hasPrefix("fr") }) {
            return Locale(identifier: "fr")
        }
        return Locale(identifier: "en")
    }
}
