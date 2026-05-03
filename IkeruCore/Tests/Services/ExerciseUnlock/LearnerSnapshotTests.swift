import Testing
import Foundation
@testable import IkeruCore

@Suite("LearnerSnapshot")
struct LearnerSnapshotTests {

    @Test("Empty snapshot defaults to N5 + zero counts")
    func empty() {
        let s = LearnerSnapshot.empty
        #expect(s.jlptLevel == .n5)
        #expect(s.vocabularyMasteredFamiliarPlus == 0)
        #expect(s.kanjiMasteredFamiliarPlus == 0)
        #expect(s.hiraganaMastered == false)
        #expect(s.katakanaMastered == false)
        #expect(s.dueCardCount == 0)
    }

    @Test("Skill imbalance ratio uses (max - min) / max")
    func imbalance() {
        let s = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 80, .listening: 70, .writing: 65, .speaking: 68],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        #expect(abs(s.skillImbalance - 0.1875) < 0.0001)
    }

    @Test("Skill imbalance is 0 when all balances are equal")
    func balanced() {
        let s = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        #expect(s.skillImbalance == 0)
    }
}
