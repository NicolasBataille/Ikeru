import Testing
@testable import IkeruCore

@Suite("VarietyPoolResolver")
struct VarietyPoolResolverTests {

    @Test("N5 pool: subtitled listening + fill-in-blank")
    func n5() {
        let pool = VarietyPoolResolver.pool(for: .n5)
        #expect(pool == [.listeningSubtitled, .fillInBlank])
    }

    @Test("N4 adds grammar + sentence construction")
    func n4() {
        let pool = VarietyPoolResolver.pool(for: .n4)
        #expect(pool.contains(.grammarExercise))
        #expect(pool.contains(.sentenceConstruction))
        #expect(pool.contains(.listeningSubtitled))
    }

    @Test("N1 contains all pool entries")
    func n1() {
        let pool = VarietyPoolResolver.pool(for: .n1)
        #expect(pool.contains(.speakingPractice))
        #expect(pool.contains(.sakuraConversation))
        #expect(pool.contains(.readingPassage))
    }

    @Test("Effective pool intersects with unlocked types")
    func intersects() {
        let resolved = VarietyPoolResolver.effectivePool(
            for: .n3,
            unlockedTypes: [.listeningSubtitled, .fillInBlank, .grammarExercise]
        )
        #expect(resolved == [.listeningSubtitled, .fillInBlank, .grammarExercise])
    }
}
