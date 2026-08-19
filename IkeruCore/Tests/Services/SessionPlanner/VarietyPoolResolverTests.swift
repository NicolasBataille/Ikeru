import Testing
@testable import IkeruCore

@Suite("VarietyPoolResolver")
struct VarietyPoolResolverTests {

    /// `.grammarExercise` est au N5 depuis le 2026-08-19. Il etait au N4, ce qui
    /// le rendait inatteignable dans une app qui ne va pas au-dela du N5 — un
    /// exercice complet que personne n'aurait jamais vu.
    @Test("N5 pool: listening + fill-in-blank + grammaire + Sakura")
    func n5() {
        let pool = VarietyPoolResolver.pool(for: .n5)
        #expect(pool == [.listeningSubtitled, .fillInBlank, .grammarExercise, .sakuraConversation])
    }

    @Test("N4 ajoute la construction de phrase, la grammaire etant deja la")
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
