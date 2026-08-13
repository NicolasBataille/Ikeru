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

    /// Count of characters that have been reviewed at least once but have not
    /// yet crossed into `.familiar` (`MasteryLevel.learning`) — the
    /// intermediate rung. A beginner's very first session can NEVER move
    /// `hiraganaMastered`/`katakanaMastered` off zero: `MasteryLevel.from`
    /// deliberately requires `reps >= 2` before anything counts as familiar+
    /// (a single "Easy" tap would otherwise inflate mastery and unlock gates
    /// off one rating). That gate is correct, but it left the "X/92" line
    /// silent for an entire first session — this field is the trace that
    /// makes the session visible without weakening the gate (2026-08-10
    /// review, "erreur de conception #4": the anti-burnout removal needs a
    /// mirror, not just the absence of a whip).
    public let hiraganaLearning: Int
    public let katakanaLearning: Int

    public init(
        hiraganaMastered: Int,
        katakanaMastered: Int,
        hiraganaLearning: Int = 0,
        katakanaLearning: Int = 0
    ) {
        self.hiraganaMastered = hiraganaMastered
        self.katakanaMastered = katakanaMastered
        self.hiraganaLearning = hiraganaLearning
        self.katakanaLearning = katakanaLearning
    }

    /// Familiar-or-better count across both scripts.
    public var total: Int { hiraganaMastered + katakanaMastered }

    /// In-progress count across both scripts (reviewed, not yet familiar+).
    public var learningTotal: Int { hiraganaLearning + katakanaLearning }

    public static let hiraganaTotal = LearnerSnapshotBuilder.baseHiragana.count
    public static let katakanaTotal = LearnerSnapshotBuilder.baseKatakana.count

    /// Fixed denominator for the "X / 92" display.
    public static var grandTotal: Int { hiraganaTotal + katakanaTotal }

    /// Count familiar-or-better AND in-progress kana in `cards`, bucketed by
    /// script via the shared base sets. Non-kana cards and untouched (`.new`)
    /// kana are ignored.
    public static func from(cards: [CardDTO], now: Date = Date()) -> KanaProgress {
        var hiraMastered = 0
        var kataMastered = 0
        var hiraLearning = 0
        var kataLearning = 0
        for card in cards {
            let isHiragana = LearnerSnapshotBuilder.baseHiragana.contains(card.front)
            let isKatakana = !isHiragana && LearnerSnapshotBuilder.baseKatakana.contains(card.front)
            guard isHiragana || isKatakana else { continue }

            switch MasteryLevel.from(fsrsState: card.fsrsState, now: now) {
            case .new:
                continue
            case .learning:
                if isHiragana { hiraLearning += 1 } else { kataLearning += 1 }
            case .familiar, .mastered, .anchored:
                if isHiragana { hiraMastered += 1 } else { kataMastered += 1 }
            }
        }
        return KanaProgress(
            hiraganaMastered: hiraMastered,
            katakanaMastered: kataMastered,
            hiraganaLearning: hiraLearning,
            katakanaLearning: kataLearning
        )
    }
}
