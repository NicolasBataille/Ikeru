import Testing
@testable import IkeruCore

@Suite("JLPTReadinessRequirements")
struct JLPTReadinessRequirementsTests {

    @Test("N5 requires 100 vocab, 50 kanji, 5 grammar, hiragana, 60% listening, no recall floor")
    func n5() {
        let r = JLPTReadinessRequirements.requirements(for: .n5)
        #expect(r.vocab == 100)
        #expect(r.kanji == 50)
        #expect(r.grammar == 5)
        #expect(r.requiresHiragana == true)
        #expect(r.requiresKatakana == false)
        #expect(r.listenAccuracy == 0.60)
        #expect(r.listenRecall == nil)
    }

    @Test("N3 requires both kana, listening recall floor 30%")
    func n3() {
        let r = JLPTReadinessRequirements.requirements(for: .n3)
        #expect(r.requiresKatakana == true)
        #expect(r.listenRecall == 0.30)
    }

    @Test("N1 requires 2000 vocab, 1000 kanji, 75% listening, 70% recall")
    func n1() {
        let r = JLPTReadinessRequirements.requirements(for: .n1)
        #expect(r.vocab == 2000)
        #expect(r.kanji == 1000)
        #expect(r.listenAccuracy == 0.75)
        #expect(r.listenRecall == 0.70)
    }

    @Test("Vocab requirements are monotonic across levels")
    func vocabMonotonic() {
        let levels: [JLPTLevel] = [.n5, .n4, .n3, .n2, .n1]
        let vocabs = levels.map { JLPTReadinessRequirements.requirements(for: $0).vocab }
        for i in 1..<vocabs.count {
            #expect(vocabs[i] > vocabs[i - 1])
        }
    }
}
