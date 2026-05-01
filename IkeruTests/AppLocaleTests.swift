import Testing
import Foundation
@testable import Ikeru

@Suite("AppLocale")
struct AppLocaleTests {
    @Test("System preference picks French when device prefers any French variant")
    func systemPicksFrench() {
        let cases = ["fr", "fr-FR", "fr-CA", "fr-BE"]
        for variant in cases {
            let resolved = AppLocale.resolveSystem(preferredLanguages: [variant, "en-US"])
            #expect(resolved.identifier.hasPrefix("fr"),
                    "preferredLanguages = [\(variant)] should resolve to French")
        }
    }

    @Test("System preference falls back to English for non-French locales")
    func systemFallsBackToEnglish() {
        let cases = ["en", "en-US", "ja-JP", "de", "es-ES"]
        for variant in cases {
            let resolved = AppLocale.resolveSystem(preferredLanguages: [variant])
            #expect(resolved.identifier.hasPrefix("en"),
                    "preferredLanguages = [\(variant)] should resolve to English")
        }
    }

    @Test("Empty preferred languages defaults to English")
    func emptyDefaultsToEnglish() {
        let resolved = AppLocale.resolveSystem(preferredLanguages: [])
        #expect(resolved.identifier.hasPrefix("en"))
    }

    @Test("Preference 'en' overrides device locale")
    func enPreferenceOverrides() {
        let pref = LanguagePreference.en
        let resolved = AppLocale.resolve(preference: pref, preferredLanguages: ["fr-FR"])
        #expect(resolved.identifier.hasPrefix("en"))
    }

    @Test("Preference 'fr' overrides device locale")
    func frPreferenceOverrides() {
        let pref = LanguagePreference.fr
        let resolved = AppLocale.resolve(preference: pref, preferredLanguages: ["en-US"])
        #expect(resolved.identifier.hasPrefix("fr"))
    }
}
