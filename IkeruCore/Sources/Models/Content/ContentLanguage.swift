import Foundation

// MARK: - ContentLanguage

/// Language in which the curated N5 bundle serves its learner-facing text
/// (vocabulary meanings, kanji meanings, grammar titles/explanations/examples).
///
/// The Japanese is never localized — it *is* the content. Only the glosses and
/// explanations have a French variant, stored in `_fr`-suffixed columns of
/// `n5-content.sqlite` (see `scripts/apply-content-fr.py`).
///
/// ## Why this is a parameter and not a lookup
///
/// `String(localized:)` inside IkeruCore resolves the wrong bundle and ignores
/// the app's `AppLocale` override (see CLAUDE.md › Localisation), and reading
/// `Locale.current` here would silently disagree with the language the learner
/// picked in Settings. So Core never guesses: the app target resolves the
/// language once, from `AppLocale`, and hands it to `ContentRepository`.
public enum ContentLanguage: String, Sendable, CaseIterable {

    /// The bundle's authoritative language — every row has it.
    case english

    /// French glosses, with a per-row fallback to English when a translation
    /// is missing (see `ContentRepository`).
    case french

    /// Maps a locale to a bundle language.
    ///
    /// Only French is distinguished — the same FR/EN split as
    /// `AppLocale.resolveSystem` and `ConversationService.isFrench`: anything
    /// that isn't French resolves to English.
    public init(locale: Locale) {
        self = locale.language.languageCode?.identifier == "fr" ? .french : .english
    }
}
