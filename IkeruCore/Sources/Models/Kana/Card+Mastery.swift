import Foundation

extension CardDTO {
    /// Mastery level computed from this card's FSRS state.
    public var masteryLevel: MasteryLevel {
        MasteryLevel.from(fsrsState: fsrsState)
    }

    /// True if the front is a registered `KanaGroup` entry: a base hiragana/katakana
    /// character, a dakuten (voiced) character, or a combined yōon digraph (base kana +
    /// small ゃ/ゅ/ょ, e.g. きゃ).
    ///
    /// This used to be a unicode-range test (`0x3040...0x309F` / `0x30A0...0x30FF`, one
    /// scalar). That broke down for yōon: a digraph like きゃ is 2 scalars, so a
    /// single-scalar range test could never match any of the 66 yōon fronts, making them
    /// invisible to every isKana-filtered query. The catalog is authoritative now, not the
    /// range, for two reasons: (1) it naturally covers multi-scalar yōon, and (2) plain
    /// unicode-range membership can't distinguish a kana-written vocabulary word of the same
    /// shape (いぬ, ねこ) from a real kana card — kana cards and vocab cards share the same
    /// `CardDTO`/`.vocabulary` type, so catalog membership is the only thing that tells them
    /// apart.
    ///
    /// One behavioural consequence: single-scalar characters that sit inside the kana
    /// Unicode blocks but were never added to `KanaGroup` (e.g. ゐ U+3090, ヴ U+30F4 — not
    /// part of the modern gojūon/dakuten/yōon curriculum) now read as **not** kana, where the
    /// old range test would have said they were. See `CardMasteryIsKanaTests` for the pinned
    /// cases (base / dakuten / yōon / non-kana / block-member-outside-catalog).
    public var isKana: Bool {
        CardDTO.kanaCatalog.contains(front)
    }

    /// Every front registered across all `KanaGroup`s (base, dakuten, yōon; both scripts).
    /// Built once and reused — `isKana` is called per-card in hot query paths
    /// (`KanaCardRepository.cardsForGroups`/`dueCardsForGroups`), so this trades a small
    /// one-time set build for O(1) membership checks instead of re-scanning `KanaGroup.allCases`
    /// on every call.
    private static let kanaCatalog: Set<String> = Set(
        KanaGroup.allCases.flatMap { $0.characters.map(\.character) }
    )

    /// The KanaGroup this card's front belongs to, if any.
    public var kanaGroup: KanaGroup? {
        guard isKana else { return nil }
        for group in KanaGroup.allCases {
            if group.characters.contains(where: { $0.character == front }) {
                return group
            }
        }
        return nil
    }
}
