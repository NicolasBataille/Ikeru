import Testing
@testable import IkeruCore

@Suite("JLPTReadinessFormula.compute")
struct JLPTReadinessFormulaTests {

    private func snap(
        hiraganaMastered: Bool = false,
        katakanaMastered: Bool = false,
        listenAccuracy: Double = 0,
        listenRecall: Double = 0,
        vocabAtOrBelow: [JLPTLevel: Int] = [:],
        kanjiAtOrBelow: [JLPTLevel: Int] = [:],
        grammarAtOrBelow: [JLPTLevel: Int] = [:]
    ) -> LearnerSnapshot {
        LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: hiraganaMastered,
            katakanaMastered: katakanaMastered,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: listenAccuracy,
            listeningRecallLast30Days: listenRecall,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil,
            vocabularyMasteredAtOrBelow: vocabAtOrBelow,
            kanjiMasteredAtOrBelow: kanjiAtOrBelow,
            grammarPointsMasteredAtOrBelow: grammarAtOrBelow
        )
    }

    @Test("Fresh profile (no kana, no cards) reads bestFit=N5, confidence=0")
    func freshProfile() {
        let report = JLPTReadinessFormula.compute(snapshot: snap())
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence == 0.0)
    }

    @Test("Hiragana-only profile (Spec A bug regression) reads <= 5% N5 confidence")
    func kanaOnlyDoesNotSpike() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(hiraganaMastered: true))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence <= 0.05)
    }

    @Test("Full N5 prereqs read bestFit=N5, confidence >= 0.85")
    func fullN5() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            listenAccuracy: 0.60,
            vocabAtOrBelow: [.n5: 100, .n4: 100, .n3: 100, .n2: 100, .n1: 100],
            kanjiAtOrBelow:  [.n5: 50,  .n4: 50,  .n3: 50,  .n2: 50,  .n1: 50],
            grammarAtOrBelow: [.n5: 5, .n4: 5, .n3: 5, .n2: 5, .n1: 5]
        ))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence >= 0.85)
    }

    @Test("N5 prereqs but 0% listening: bestFit=N5, confidence < 0.85")
    func zeroListeningDragsDown() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            listenAccuracy: 0.0,
            vocabAtOrBelow: [.n5: 100], kanjiAtOrBelow: [.n5: 50], grammarAtOrBelow: [.n5: 5]
        ))
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence < 0.85)
    }

    @Test("All N3 axes met EXCEPT recall (25% vs 30%) -> bestFit <= N4")
    func n3WeakRecall() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: true,
            katakanaMastered: true,
            listenAccuracy: 0.65,
            listenRecall: 0.25,
            vocabAtOrBelow:  [.n3: 650, .n2: 650, .n1: 650, .n4: 650, .n5: 650],
            kanjiAtOrBelow:  [.n3: 300, .n2: 300, .n1: 300, .n4: 300, .n5: 300],
            grammarAtOrBelow:[.n3: 100, .n2: 100, .n1: 100, .n4: 100, .n5: 100]
        ))
        #expect(report.bestFit < .n3)
    }

    @Test("Missing hiragana hard-gates to 0 readiness")
    func hardKanaGate() {
        let report = JLPTReadinessFormula.compute(snapshot: snap(
            hiraganaMastered: false,
            listenAccuracy: 1.0,
            vocabAtOrBelow:  [.n5: 1000], kanjiAtOrBelow: [.n5: 1000], grammarAtOrBelow: [.n5: 1000]
        ))
        #expect((report.perLevel[.n5] ?? 0) == 0)
    }
}
