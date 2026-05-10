import Testing
@testable import IkeruCore

@Suite("LearnerSnapshot per-level mastery dicts")
struct LearnerSnapshotPerLevelTests {

    @Test("Defaults to empty dicts when not provided")
    func emptyByDefault() {
        let snap = LearnerSnapshot.empty
        #expect(snap.vocabularyMasteredAtOrBelow.isEmpty)
        #expect(snap.kanjiMasteredAtOrBelow.isEmpty)
        #expect(snap.grammarPointsMasteredAtOrBelow.isEmpty)
    }

    @Test("Stores per-level counts")
    func storesCounts() {
        let snap = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 100,
            kanjiMasteredFamiliarPlus: 50,
            hiraganaMastered: true,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 5,
            listeningAccuracyLast30: 0.6,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil,
            vocabularyMasteredAtOrBelow: [.n5: 100, .n4: 100, .n3: 100, .n2: 100, .n1: 100],
            kanjiMasteredAtOrBelow: [.n5: 50],
            grammarPointsMasteredAtOrBelow: [.n5: 5]
        )
        #expect(snap.vocabularyMasteredAtOrBelow[.n5] == 100)
        #expect(snap.kanjiMasteredAtOrBelow[.n5] == 50)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n5] == 5)
    }
}
