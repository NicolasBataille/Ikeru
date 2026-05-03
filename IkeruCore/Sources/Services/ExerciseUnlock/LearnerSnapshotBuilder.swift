import Foundation

/// Builds a `LearnerSnapshot` from real, ambient state (cards, RPG, etc).
/// Pure (no I/O) — caller is responsible for fetching data.
public enum LearnerSnapshotBuilder {

    public static let hiraganaRange: ClosedRange<UInt32> = 0x3042...0x3093
    public static let katakanaRange: ClosedRange<UInt32> = 0x30A2...0x30F3
    public static let kanaSyllabaryCount = 46

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

            switch card.type {
            case .vocabulary:
                if familiarPlus { vocab += 1 }
            case .kanji:
                let firstScalar = card.front.unicodeScalars.first?.value ?? 0
                if hiraganaRange.contains(firstScalar) {
                    if familiarPlus { hiraganaFamiliarFronts.insert(card.front) }
                } else if katakanaRange.contains(firstScalar) {
                    if familiarPlus { katakanaFamiliarFronts.insert(card.front) }
                } else if familiarPlus {
                    kanji += 1
                }
            case .grammar, .listening:
                break
            }
        }

        return LearnerSnapshot(
            jlptLevel: jlptLevel,
            vocabularyMasteredFamiliarPlus: vocab,
            kanjiMasteredFamiliarPlus: kanji,
            hiraganaMastered: hiraganaFamiliarFronts.count >= kanaSyllabaryCount,
            katakanaMastered: katakanaFamiliarFronts.count >= kanaSyllabaryCount,
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
