import Foundation
import IkeruCore
import os

/// One place that opens the shipped `n5-content.sqlite`, in the learner's
/// language.
///
/// ## Why this exists
///
/// Three views each carried their own copy of "find the bundle, log if it's
/// missing, open it" (`HomeView`, `EtudeView`,
/// `ExerciseTransitionContainer`) — and **every one of them opened it in
/// English**. `ContentRepository.init` defaults to `.english` on purpose (its
/// doc comment: "an unwired caller gets complete content, never a silent
/// locale guess"), and no caller had ever been wired.
///
/// The consequence, measured 2026-08-16: the whole French half of the content
/// bundle was dormant. `meaning_fr`, `meanings_fr`, `title_fr`,
/// `explanation_fr`, `examples_fr` and `sentences.french` are all populated by
/// `scripts/apply-content-fr.py`, and `ContentRepositoryLanguageTests` proves
/// the selection mechanism works — it was simply never switched on. A French
/// learner read English glosses throughout.
///
/// It bites hardest on example sentences: the Tatoeba half of the corpus is
/// French-only (536 of 632 rows carry no English), so in English those rows
/// have no translation at all and are dropped by
/// `ContentRepository.exampleSentences(for:limit:)`.
///
/// ## Locale, not `String(localized:)`
///
/// The language comes from `AppLocale`, the app's own preference — the same
/// resolution the UI uses — not from `Locale.current`. A learner who forces
/// French in Réglages while the device is English must get French content;
/// reading the system locale would ignore that override. `AppLocale` reads its
/// stored preference from `UserDefaults`, so constructing one here is cheap and
/// gives the same answer as the instance `MainTabView` injects.
enum BundledContent {

    private static let logger = Logger(subsystem: "com.ikeru", category: "content")

    /// The content language for the learner's current preference.
    static var language: ContentLanguage {
        ContentLanguage(locale: AppLocale().currentLocale)
    }

    /// Opens the shipped JMdict dictionary — the one « apporte ton propre
    /// texte » reads.
    ///
    /// Separate from the curated bundle above, and deliberately **not
    /// localised at open time**: JMdict carries both glosses on the same row,
    /// and `DictionaryEntry` exposes `glossFR` as an optional so the view layer
    /// can label an English gloss as English. Only 7 % of entries carry French
    /// (43 % among the common ones), so hiding the distinction here would mean
    /// lying quietly about a quarter of the words in a real text.
    ///
    /// Same fail-safe contract as `makeRepository()`: a missing resource logs
    /// and returns `nil`, and the feature says out loud that it cannot look
    /// anything up rather than failing word by word.
    static func makeDictionary() -> DictionaryRepository? {
        guard let url = Bundle.main.url(forResource: "jmdict", withExtension: "sqlite") else {
            logger.error("jmdict.sqlite not found in bundle — text import unavailable")
            return nil
        }
        return DictionaryRepository(bundleURL: url)
    }

    /// Opens the bundled content database in the learner's language.
    ///
    /// Fail-safe by design, matching what the three call sites did before:
    /// a missing resource logs and returns `nil` so the feature that needed it
    /// degrades (no stroke trace, no reading validation, no examples) instead
    /// of taking the screen down with it.
    static func makeRepository() -> ContentRepository? {
        guard let url = Bundle.main.url(forResource: "n5-content", withExtension: "sqlite") else {
            logger.error("n5-content.sqlite not found in bundle — bundled content unavailable")
            return nil
        }
        return ContentRepository(bundleURL: url, language: language)
    }
}
