import Foundation

/// One bundled example sentence, paired with its translation in the learner's
/// language.
///
/// ## Why this exists next to `Vocabulary.exampleSentences`
///
/// `Vocabulary.exampleSentences` is `[String]` — Japanese only. The bundle has
/// carried `sentences.french` and `sentences.english` for a while, and nothing
/// read either (the doc comment on `ContentRepository` said so in as many
/// words). A Japanese sentence with no gloss is not an example a beginner can
/// use, so the reader this type serves pairs the two.
///
/// It is deliberately a *new* type rather than a widening of
/// `exampleSentences`. That property feeds two views which nothing
/// instantiates today (`VocabularyStudyView`, `VocabularyExamplesView` — see
/// the PR that added this file); changing its element type would have dragged
/// dead code into a wiring change.
///
/// ## `translation` is never empty, and never the wrong language
///
/// A row whose translation is missing in the learner's language is **dropped**
/// by `ContentRepository.exampleSentences(for:limit:)` rather than surfaced
/// with a blank line or with the other language's text. That matters more than
/// it looks: measured 2026-08-16, the Tatoeba half of the corpus is
/// **French-only** — 239 of 335 rows then, 536 of 632 now, carry no English at
/// all, because the corpus was selected from Tatoeba's jpn↔fra links. Falling
/// back the way vocabulary meanings do (French missing → serve English) is the
/// wrong direction here and would put French sentences under an English UI.
public struct SentenceExample: Sendable, Equatable, Identifiable, Hashable {

    /// The Japanese sentence, verbatim from the bundle.
    public let japanese: String

    /// The same sentence with furigana, as `水(みず)を飲(の)みたいです。` — the
    /// shape `KanaRubyText` parses. Empty when the bundle predates the column;
    /// callers fall back to `japanese`, which reads correctly, just unaided.
    ///
    /// Generated and **reviewed** by `scripts/furigana/generate-furigana.py`.
    /// It refuses to guess: a run it cannot resolve ships unannotated rather
    /// than annotated wrongly, because a learner copies a wrong reading.
    public let furigana: String

    /// The translation in the learner's language. Guaranteed non-empty.
    public let translation: String

    /// Stable within a word's example list — the Japanese text is unique per
    /// row by construction (`build-corpus.py` collapses near-duplicates).
    public var id: String { japanese }

    public init(japanese: String, translation: String, furigana: String = "") {
        self.japanese = japanese
        self.translation = translation
        self.furigana = furigana
    }

    /// The furigana form when the bundle carries one, else the plain sentence.
    public var displayText: String { furigana.isEmpty ? japanese : furigana }
}
