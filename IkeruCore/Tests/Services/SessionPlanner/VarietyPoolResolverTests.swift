import Testing
@testable import IkeruCore

@Suite("VarietyPoolResolver")
struct VarietyPoolResolverTests {

    /// `.grammarExercise` est au N5 depuis le 2026-08-19. Il etait au N4, ce qui
    /// le rendait inatteignable dans une app qui ne va pas au-dela du N5 — un
    /// exercice complet que personne n'aurait jamais vu.
    @Test("N5 pool: listening + grammaire + Sakura + ecriture")
    func n5() {
        let pool = VarietyPoolResolver.pool(for: .n5)
        #expect(pool == [
            .listeningSubtitled, .grammarExercise,
            .sakuraConversation, .writingPractice
        ])
    }

    /// `.fillInBlank` et `.readingPassage` sont RETIRÉS du produit depuis le
    /// 2026-09-09 (`ExerciseType.retired`) — retirés des pools dès le
    /// 2026-08-28, quand leur écran était encore un bouchon dont le bouton
    /// « Complete » notait `.good`. Ce test rougit si l'un des deux revient
    /// dans un pool, à n'importe quel niveau. Vu ROUGE en remettant
    /// `.readingPassage` dans l'union N3.
    @Test("Un type retiré n'est dans AUCUN pool, à AUCUN niveau")
    func retiredTypesAbsentFromEveryPool() {
        for level in JLPTLevel.allCases {
            #expect(
                VarietyPoolResolver.pool(for: level).isDisjoint(with: ExerciseType.retired),
                "un type retiré est programmable au \(level.rawValue)"
            )
        }
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
        #expect(pool.contains(.listeningUnsubtitled))
    }

    @Test("Effective pool intersects with unlocked types")
    func intersects() {
        // Le type verrouille (`.listeningUnsubtitled`) est dans le pool N3 mais
        // pas dans l'ensemble deverrouille : il doit disparaitre de l'intersection.
        let resolved = VarietyPoolResolver.effectivePool(
            for: .n3,
            unlockedTypes: [.listeningSubtitled, .grammarExercise]
        )
        #expect(resolved == [.listeningSubtitled, .grammarExercise])
        #expect(VarietyPoolResolver.pool(for: .n3).contains(.listeningUnsubtitled))
    }
}
