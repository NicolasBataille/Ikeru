// IkeruCore/Sources/Services/ExerciseUnlock/LearnerSnapshotBuilder.swift
import Foundation

/// Builds a `LearnerSnapshot` from real, ambient state (cards, RPG, etc).
/// Pure (no I/O) — caller is responsible for fetching data.
public enum LearnerSnapshotBuilder {

    /// The 46 base hiragana characters (gojūon — no dakuten / handakuten /
    /// small / extended). Mastery of all 46 is the threshold for
    /// `hiraganaMastered`. Counting `Set<String>` of `card.front` against
    /// this set tolerates duplicate cards and excludes voiced/extended kana.
    public static let baseHiragana: Set<String> = [
        "\u{3042}", "\u{3044}", "\u{3046}", "\u{3048}", "\u{304A}", // あいうえお
        "\u{304B}", "\u{304D}", "\u{304F}", "\u{3051}", "\u{3053}", // かきくけこ
        "\u{3055}", "\u{3057}", "\u{3059}", "\u{305B}", "\u{305D}", // さしすせそ
        "\u{305F}", "\u{3061}", "\u{3064}", "\u{3066}", "\u{3068}", // たちつてと
        "\u{306A}", "\u{306B}", "\u{306C}", "\u{306D}", "\u{306E}", // なにぬねの
        "\u{306F}", "\u{3072}", "\u{3075}", "\u{3078}", "\u{307B}", // はひふへほ
        "\u{307E}", "\u{307F}", "\u{3080}", "\u{3081}", "\u{3082}", // まみむめも
        "\u{3084}", "\u{3086}", "\u{3088}",                          // やゆよ
        "\u{3089}", "\u{308A}", "\u{308B}", "\u{308C}", "\u{308D}", // らりるれろ
        "\u{308F}", "\u{3092}", "\u{3093}",                          // わをん
    ]

    /// The 46 base katakana characters (mirror of `baseHiragana`).
    public static let baseKatakana: Set<String> = [
        "\u{30A2}", "\u{30A4}", "\u{30A6}", "\u{30A8}", "\u{30AA}", // アイウエオ
        "\u{30AB}", "\u{30AD}", "\u{30AF}", "\u{30B1}", "\u{30B3}", // カキクケコ
        "\u{30B5}", "\u{30B7}", "\u{30B9}", "\u{30BB}", "\u{30BD}", // サシスセソ
        "\u{30BF}", "\u{30C1}", "\u{30C4}", "\u{30C6}", "\u{30C8}", // タチツテト
        "\u{30CA}", "\u{30CB}", "\u{30CC}", "\u{30CD}", "\u{30CE}", // ナニヌネノ
        "\u{30CF}", "\u{30D2}", "\u{30D5}", "\u{30D8}", "\u{30DB}", // ハヒフヘホ
        "\u{30DE}", "\u{30DF}", "\u{30E0}", "\u{30E1}", "\u{30E2}", // マミムメモ
        "\u{30E4}", "\u{30E6}", "\u{30E8}",                          // ヤユヨ
        "\u{30E9}", "\u{30EA}", "\u{30EB}", "\u{30EC}", "\u{30ED}", // ラリルレロ
        "\u{30EF}", "\u{30F2}", "\u{30F3}",                          // ワヲン
    ]

    public static func build(
        cards: [CardDTO],
        jlptLevel: JLPTLevel,
        grammarPointsFamiliarPlus: Int,
        listeningAccuracyLast30: Double,
        listeningRecallLast30Days: Double,
        skillBalances: [SkillType: Double],
        hasNewContentQueued: Bool,
        lastSessionAt: Date?,
        now: Date
    ) -> LearnerSnapshot {

        var vocab = 0
        var kanji = 0
        var hiraganaFamiliarFronts: Set<String> = []
        var katakanaFamiliarFronts: Set<String> = []
        var due = 0

        for card in cards {
            let mastery = MasteryLevel.from(fsrsState: card.fsrsState, now: now)
            let familiarPlus = mastery.rawValue >= MasteryLevel.familiar.rawValue
            if card.dueDate <= now { due += 1 }

            // Kana detection is independent of `card.type` because the
            // production seeder (`KanaCardRepository.seedIfNeeded`) emits
            // kana cards as `CardType.vocabulary`, not `.kanji`. Match
            // explicitly against the 46 base hiragana / katakana sets so
            // dakuten and small/extended kana don't falsely satisfy the
            // 46-character mastery threshold.
            if baseHiragana.contains(card.front) {
                if familiarPlus { hiraganaFamiliarFronts.insert(card.front) }
                continue
            }
            if baseKatakana.contains(card.front) {
                if familiarPlus { katakanaFamiliarFronts.insert(card.front) }
                continue
            }

            switch card.type {
            case .vocabulary:
                if familiarPlus { vocab += 1 }
            case .kanji:
                if familiarPlus { kanji += 1 }
            case .grammar, .listening:
                break
            }
        }

        return LearnerSnapshot(
            jlptLevel: jlptLevel,
            vocabularyMasteredFamiliarPlus: vocab,
            kanjiMasteredFamiliarPlus: kanji,
            hiraganaMastered: hiraganaFamiliarFronts.count >= baseHiragana.count,
            katakanaMastered: katakanaFamiliarFronts.count >= baseKatakana.count,
            grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
            listeningAccuracyLast30: listeningAccuracyLast30,
            listeningRecallLast30Days: listeningRecallLast30Days,
            skillBalances: skillBalances,
            dueCardCount: due,
            hasNewContentQueued: hasNewContentQueued,
            lastSessionAt: lastSessionAt
        )
    }
}
