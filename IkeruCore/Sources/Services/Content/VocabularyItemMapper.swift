import Foundation

// MARK: - VocabularyItemMapper

/// Adapts `ContentRepository`'s static `Vocabulary` rows into the
/// `VocabularyItem` shape the Shadowing / Listening drill view models consume.
///
/// The two types carry the same learning payload under different field names
/// (`Vocabulary.word` ↔ `VocabularyItem.japanese`) and differ in identity:
/// `Vocabulary.id` is the SQLite `INTEGER PRIMARY KEY`, while `VocabularyItem`
/// uses a `UUID`. There is no persisted UUID for a content row, so each mapped
/// item gets a fresh `UUID` (drills only ever `.randomElement()` / generate
/// from the pool — they never look an item up by id, so a non-stable id is
/// harmless here). `kanjiCharacter` and `exampleSentences` have no counterpart
/// on `VocabularyItem` and are intentionally dropped.
///
/// Pure and `Sendable`-safe — no I/O, no shared state — so it is trivially
/// unit-testable in isolation from the SQLite layer.
public enum VocabularyItemMapper {

    /// Maps a single content `Vocabulary` row to a drill `VocabularyItem`.
    public static func map(_ vocabulary: Vocabulary) -> VocabularyItem {
        VocabularyItem(
            japanese: vocabulary.word,
            reading: vocabulary.reading,
            meaning: vocabulary.meaning,
            jlptLevel: vocabulary.jlptLevel
        )
    }

    /// Maps a batch of content `Vocabulary` rows to drill `VocabularyItem`s,
    /// preserving order.
    public static func map(_ vocabulary: [Vocabulary]) -> [VocabularyItem] {
        vocabulary.map(map)
    }
}
