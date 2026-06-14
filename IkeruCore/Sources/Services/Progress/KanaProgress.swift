import Foundation

/// Pure aggregation of kana mastery, for calm progress display ("46 / 92
/// learned"). Counts hiragana and katakana that have reached familiar-or-
/// better, measured against the 46 + 46 base character sets shared with
/// `LearnerSnapshotBuilder`. Dakuten/yōon are not part of the base pool,
/// so the denominator is a fixed 92 — a fixed, reachable beginner goal.
///
/// No I/O: feed it the card pool (`CardRepository.allCards()`).
public struct KanaProgress: Equatable, Sendable {
    public let hiraganaMastered: Int
    public let katakanaMastered: Int

    public init(hiraganaMastered: Int, katakanaMastered: Int) {
        self.hiraganaMastered = hiraganaMastered
        self.katakanaMastered = katakanaMastered
    }

    /// Familiar-or-better count across both scripts.
    public var total: Int { hiraganaMastered + katakanaMastered }

    public static let hiraganaTotal = LearnerSnapshotBuilder.baseHiragana.count
    public static let katakanaTotal = LearnerSnapshotBuilder.baseKatakana.count

    /// Fixed denominator for the "X / 92" display.
    public static var grandTotal: Int { hiraganaTotal + katakanaTotal }

    /// Count familiar-or-better kana in `cards`, bucketed by script via the
    /// shared base sets. Non-kana cards and sub-familiar kana are ignored.
    public static func from(cards: [CardDTO], now: Date = Date()) -> KanaProgress {
        let threshold = MasteryLevel.familiar.rawValue
        var hira = 0
        var kata = 0
        for card in cards {
            guard MasteryLevel.from(fsrsState: card.fsrsState, now: now).rawValue >= threshold else {
                continue
            }
            if LearnerSnapshotBuilder.baseHiragana.contains(card.front) {
                hira += 1
            } else if LearnerSnapshotBuilder.baseKatakana.contains(card.front) {
                kata += 1
            }
        }
        return KanaProgress(hiraganaMastered: hira, katakanaMastered: kata)
    }
}
