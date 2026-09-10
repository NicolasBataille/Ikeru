import Testing
import Foundation
@testable import IkeruCore

@Suite("MasteryLevel")
struct MasteryLevelTests {

    @Test("reps == 0 always yields .new regardless of other fields")
    func newWhenNoReps() {
        let s = FSRSState(difficulty: 5, stability: 100, reps: 0, lapses: 3, lastReview: Date())
        #expect(MasteryLevel.from(fsrsState: s) == .new)
    }

    @Test("stability < 1.0 → .learning")
    func learningWhenLowStability() {
        let s = FSRSState(difficulty: 5, stability: 0.5, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .learning)
    }

    @Test("Single rep stays .learning even with familiar-range stability (one 'Good' press)")
    func singleGoodPressStaysLearning() {
        // One 'Good' on a new card yields stability ≈ 3.13 with reps == 1.
        let s = FSRSState(difficulty: 5, stability: 3.13, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .learning)
    }

    @Test("Single rep stays .learning even with mastered-range stability (one 'Easy' press)")
    func singleEasyPressStaysLearning() {
        // One 'Easy' on a new card yields stability ≈ 15.47 with reps == 1.
        let s = FSRSState(difficulty: 5, stability: 15.47, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .learning)
    }

    @Test("Single rep with anchored-range stability stays .learning")
    func singleRepHighStabilityStaysLearning() {
        let s = FSRSState(difficulty: 5, stability: 100.0, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .learning)
    }

    @Test("stability == 1.0 exactly with reps >= 2 → .familiar (boundary)")
    func familiarAtLowerBoundary() {
        let s = FSRSState(difficulty: 5, stability: 1.0, reps: 2, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .familiar)
    }

    @Test("reps == 2 exactly unlocks familiar-or-better tiers (boundary)")
    func repsBoundaryUnlocksFamiliarPlus() {
        let familiar = FSRSState(difficulty: 5, stability: 3.13, reps: 2, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: familiar) == .familiar)

        let mastered = FSRSState(difficulty: 5, stability: 15.47, reps: 2, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: mastered) == .mastered)

        let anchored = FSRSState(difficulty: 5, stability: 60.0, reps: 2, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: anchored) == .anchored)
    }

    @Test("stability == 7.0 exactly → .mastered (boundary)")
    func masteredAtLowerBoundary() {
        let s = FSRSState(difficulty: 5, stability: 7.0, reps: 5, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .mastered)
    }

    @Test("stability == 60.0 exactly → .anchored (boundary)")
    func anchoredAtBoundary() {
        let s = FSRSState(difficulty: 5, stability: 60.0, reps: 10, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .anchored)
    }

    // MARK: - Retrait de la règle « rechute récente » (OBS2-024 / 077 / 081)
    //
    // Ces trois tests remplacent `recentLapseDemotes` / `oldLapseDoesNotDemote`,
    // qui épinglaient le comportement retiré. Voir la note de conception sur
    // `MasteryLevel.from(fsrsState:now:)` pour le raisonnement complet.

    @Test("Une rechute ancienne au compteur ne rétrograde plus une carte stable")
    func lifetimeLapseNoLongerDemotesAStableCard() {
        // Le cas exact que le reviewer a mesuré en boîte noire : carte ratée une
        // fois dans sa vie, révisée avec SUCCÈS à l'instant. Elle affichait
        // « en apprentissage » alors que sa stabilité disait « maîtrisé ».
        let now = Date()
        let justReviewed = FSRSState(
            difficulty: 5, stability: 30.0, reps: 5, lapses: 1, lastReview: now
        )
        #expect(MasteryLevel.from(fsrsState: justReviewed, now: now) == .mastered)

        // Et le palier ne dépend plus du tout de l'horloge : même état, trois
        // dates. C'est ce qui rendait la rétrogradation permanente pour les
        // cartes à intervalle court, chaque révision réarmant la fenêtre.
        for offset in [0.0, 47 * 3600.0, 49 * 3600.0, 7 * 86_400.0] {
            #expect(
                MasteryLevel.from(fsrsState: justReviewed, now: now.addingTimeInterval(offset)) == .mastered,
                "le palier ne doit plus varier avec le temps écoulé (offset \(offset)s)"
            )
        }
    }

    @Test("Un vrai échec rétrograde toujours — par l'effondrement de stabilité")
    func aFreshFailureStillDemotesViaStability() {
        // C'est la mesure sur laquelle repose tout le retrait : si FSRS ne
        // faisait PAS redescendre le palier de lui-même, supprimer la règle
        // laisserait une carte fraîchement ratée affichée « maîtrisé ». Ce test
        // échoue si cette hypothèse cesse d'être vraie — par exemple si les
        // poids FSRS changent.
        let t0 = Date()
        for stability in [10.0, 20.0, 50.0] {
            let mastered = FSRSState(
                difficulty: 5, stability: stability, reps: 4, lapses: 0, lastReview: t0
            )
            #expect(MasteryLevel.from(fsrsState: mastered, now: t0) == .mastered)

            let afterFailure = FSRSService.schedule(
                state: mastered, grade: .again, now: t0.addingTimeInterval(86_400)
            )
            #expect(
                afterFailure.stability < mastered.stability,
                "un échec doit effondrer la stabilité (départ \(stability))"
            )
            #expect(
                MasteryLevel.from(fsrsState: afterFailure, now: t0.addingTimeInterval(86_400)) != .mastered,
                "après un échec, la carte ne doit plus être affichée « maîtrisé » (départ \(stability))"
            )
        }
    }

    @Test("Limite assumée : au-delà de ~100 de stabilité, un échec ne change pas le palier")
    func veryStableCardKeepsItsTierAfterOneFailure() {
        // Ce test ne décrit pas un défaut mais la contrepartie MESURÉE du
        // retrait, consignée pour qu'elle ne soit pas redécouverte comme une
        // régression. Ces cartes reviennent tous les plusieurs mois : la
        // fenêtre de 48 h y était un clignotement que personne ne voyait.
        let t0 = Date()
        let anchored = FSRSState(difficulty: 5, stability: 200.0, reps: 12, lapses: 0, lastReview: t0)
        #expect(MasteryLevel.from(fsrsState: anchored, now: t0) == .anchored)

        let afterFailure = FSRSService.schedule(
            state: anchored, grade: .again, now: t0.addingTimeInterval(86_400)
        )
        #expect(afterFailure.stability < anchored.stability, "la stabilité chute quand même")
        #expect(afterFailure.lapses == anchored.lapses + 1, "l'échec est bien compté")
    }

    @Test("emoji is non-empty for every case", arguments: MasteryLevel.allCases)
    func emojiNonEmpty(level: MasteryLevel) {
        #expect(!level.emoji.isEmpty)
    }

    @Test("label is non-empty for every case", arguments: MasteryLevel.allCases)
    func labelNonEmpty(level: MasteryLevel) {
        #expect(!level.label.isEmpty)
    }
}
