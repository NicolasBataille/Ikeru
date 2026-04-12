import Foundation

extension CardDTO {
    /// Mastery level computed from this card's FSRS state.
    public var masteryLevel: MasteryLevel {
        MasteryLevel.from(fsrsState: fsrsState)
    }

    /// True if the front is exactly one hiragana or katakana character.
    /// Hiragana block: U+3040–U+309F. Katakana block: U+30A0–U+30FF.
    public var isKana: Bool {
        let scalars = Array(front.unicodeScalars)
        guard scalars.count == 1 else { return false }
        let v = scalars[0].value
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v)
    }

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
