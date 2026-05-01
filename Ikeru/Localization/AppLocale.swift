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
