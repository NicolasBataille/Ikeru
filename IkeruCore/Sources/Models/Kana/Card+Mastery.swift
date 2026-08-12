import Foundation

extension CardDTO {
    /// Mastery level computed from this card's FSRS state.
    public var masteryLevel: MasteryLevel {
        MasteryLevel.from(fsrsState: fsrsState)
    }

    /// True if the front is exactly one character from the kana catalog: a base
    /// hiragana/katakana character, or a combined yōon digraph (base kana + small ゃ/ゅ/ょ,
    /// e.g. きゃ). Checked against the `KanaGroup` catalog rather than unicode ranges alone,
    /// because plain unicode-range membership can't distinguish yōon (2 scalars, both kana)
    /// from an ordinary kana-written vocabulary word of the same shape (いぬ, ねこ) — kana
    /// cards and vocab cards share the same `CardDTO`/`.vocabulary` type, so catalog
    /// membership is the only thing that tells them apart.
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
