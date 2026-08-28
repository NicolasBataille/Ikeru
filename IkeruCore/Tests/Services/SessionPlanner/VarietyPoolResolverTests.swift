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

    /// `.fillInBlank` a ete RETIRE de tous les pools le 2026-08-28 : son ecran
    /// est un bouchon dont le bouton « Complete » note `.good`. Il etait servi
    /// en seance d'accueil, donc un apprenant reel recoltait une reussite pour
    /// un exercice inexistant. Ce test rougit si on le remet sans ecran.
    @Test("Le texte a trou n'est dans AUCUN pool tant qu'il n'a pas d'ecran")
    func fillInBlankAbsentFromEveryPool() {
        for level in JLPTLevel.allCases {
            #expect(
                !VarietyPoolResolver.pool(for: level).contains(.fillInBlank),
                "fillInBlank ne doit pas etre programmable au \(level.rawValue)"
            )
        }
    }

    /// `.writingPractice` est descendu au N5 le 2026-08-28 (OBS2-023), meme
    /// raisonnement que la grammaire : a N3, dans une app « N5 and no
    /// further », l'exercice de trace etait du code mort — un ecran reel
    /// (`HandwritingDrillHost`) que le planificateur ne pouvait jamais
    /// programmer.
    @Test("L'ecriture est atteignable des le N5")
    func writingReachableAtN5() {
        #expect(VarietyPoolResolver.pool(for: .n5).contains(.writingPractice))
    }

    /// Contrepartie du test precedent, et c'est LUI qui compte : la lecture
    /// NE DOIT PAS descendre tant que `.readingPassage` est rendu par
    /// `placeholderExerciseView` — un bouchon dont le bouton « Complete »
    /// note `.good`. Ce test rougit si quelqu'un applique le precedent de la
    /// grammaire sans verifier que l'ecran existe.
    @Test("La lecture NE descend PAS au N5 : son ecran est encore un bouchon")
    func readingStaysGatedUntilItHasAScreen() {
        #expect(!VarietyPoolResolver.pool(for: .n5).contains(.readingPassage))
        #expect(VarietyPoolResolver.pool(for: .n3).contains(.readingPassage))
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
        // Le type verrouille (`.readingPassage`) est dans le pool N3 mais pas
        // dans l'ensemble deverrouille : il doit disparaitre de l'intersection.
        let resolved = VarietyPoolResolver.effectivePool(
            for: .n3,
            unlockedTypes: [.listeningSubtitled, .grammarExercise]
        )
        #expect(resolved == [.listeningSubtitled, .grammarExercise])
        #expect(VarietyPoolResolver.pool(for: .n3).contains(.readingPassage))
    }
}
