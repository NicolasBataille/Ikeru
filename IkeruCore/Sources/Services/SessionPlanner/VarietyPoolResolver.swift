import Foundation

/// Pure: maps a learner's JLPT estimate to the eligible variety pool.
/// JLPT ordering is N5 < N4 < N3 < N2 < N1 (lower number = harder).
/// Higher levels stack onto lower levels — N4 includes N5; N3 adds more.
/// One entry, `.sakuraConversation`, does not stack on a hardcoded rung: it
/// tracks `DefaultExerciseUnlockService.sakuraConversationMinJLPT` instead
/// (see below), so at least *this pool's* threshold can't silently
/// re-diverge from the unlock gate. That does not mean Sakura conversation
/// is actually scheduled for HOME sessions today — see the note below.
public enum VarietyPoolResolver {

    /// Raw pool by JLPT level (before unlocking constraints).
    public static func pool(for level: JLPTLevel) -> Set<ExerciseType> {
        // `.grammarExercise` est au N5, pas au N4 — corrige le 2026-08-19.
        //
        // Il etait derriere `level >= .n4`, ce qui le rendait INATTEIGNABLE :
        // l'app est N5 et rien d'autre (« That is JLPT N5 and no further »,
        // README), donc aucune seance ne pouvait le programmer. Le seuil datait
        // d'une epoque ou l'exercice de grammaire n'avait ni contenu ni ecran :
        // il rendait un placeholder, et le planificateur lui passait un `UUID()`
        // fabrique. Le laisser en N4 aurait fait un exercice complet que
        // personne n'aurait jamais vu.
        //
        // Le contenu, lui, est bien du N5 : les 51 points couvrent la liste
        // officielle N5 (40/40, mesure le 2026-08-19). La porte reste tenue par
        // `ExerciseUnlockService`, qui exige les hiragana maitrises — un
        // debutant ne recoit donc pas de texte a trou avant de savoir lire.
        var result: Set<ExerciseType> = [.listeningSubtitled, .fillInBlank, .grammarExercise]
        if level >= .n4 {
            result.insert(.sentenceConstruction)
        }
        // `.writingPractice` descend au N5 — MÊME RAISONNEMENT que
        // `.grammarExercise` juste au-dessus, et mêmes préalables vérifiés
        // avant de bouger le seuil (OBS2-023) :
        //
        // 1. L'écran existe pour de vrai. `.writingPractice` est routé vers
        //    `HandwritingDrillHost` dans `ExerciseTransitionContainer` — le
        //    drill de tracé, pas un bouchon.
        // 2. La porte est tenue ailleurs. `ExerciseUnlockService` exige les
        //    hiragana ET les katakana maîtrisés : un débutant ne reçoit pas
        //    d'exercice d'écriture avant de savoir lire.
        // 3. Le contenu peut manquer proprement. `synthesise` tire une carte
        //    kanji et renvoie `nil` s'il n'y en a pas — la séance saute la
        //    tuile au lieu de servir du vide.
        //
        // À N3, dans une app qui est « N5 and no further » (README), cet
        // exercice était du code mort : construit, testé, jamais programmé.
        //
        // `.readingPassage` reste au N3 DÉLIBÉRÉMENT, et c'est le point
        // important : son écran est encore
        // `placeholderExerciseView("Reading Passage", "Read and comprehend")`,
        // avec un bouton « Complete » qui note `.good`. Descendre son seuil
        // aurait livré un bouchon auto-noté dans les séances réelles — soit
        // exactement l'erreur que le seuil du N4 évitait pour la grammaire
        // tant que son contenu n'existait pas. Il descendra quand il aura un
        // écran, pas avant.
        //
        // `.listeningUnsubtitled` reste au N3 pour une autre raison : il est
        // de toute façon retiré par `untaughtContentTypes`, décision produit
        // du 2026-07-19 qui n'est pas à moi de lever.
        result.insert(.writingPractice)
        if level >= .n3 {
            result.formUnion([.readingPassage, .listeningUnsubtitled])
        }
        if level >= .n2 {
            result.insert(.speakingPractice)
        }
        // Previously hardcoded to the same `.n2` rung as `.speakingPractice`
        // above, which was stricter than — and independent of — the actual
        // Sakura unlock gate: `DefaultExerciseUnlockService` opened Sakura at
        // N5, but this pool still withheld it from the planner until N2.
        // Reading the real gate here instead of duplicating a threshold at
        // least keeps the *eligibility rung* in sync with the unlock
        // service if its bar ever moves — but that only fixes this pool's
        // own threshold, not the end-to-end HOME scheduling gap: the
        // threshold is currently N5 (the floor), so this branch is
        // unconditionally true, yet `DefaultSessionPlanner.composeHome`
        // still subtracts `untaughtContentTypes` (which lists
        // `.sakuraConversation`) from both the booster and variety pools it
        // builds from this method's output. So HOME sessions still never
        // schedule Sakura conversation, at any JLPT level, until that
        // separate exclusion is revisited. `composeStudy` custom sessions
        // don't go through this resolver at all — they intersect the
        // user's chosen types directly with `unlockedTypes` — so Sakura
        // conversation IS reachable there once unlocked.
        if level >= DefaultExerciseUnlockService.sakuraConversationMinJLPT {
            result.insert(.sakuraConversation)
        }
        return result
    }

    /// Pool intersected with the unlocked set the learner can actually use.
    public static func effectivePool(
        for level: JLPTLevel,
        unlockedTypes: Set<ExerciseType>
    ) -> Set<ExerciseType> {
        pool(for: level).intersection(unlockedTypes)
    }
}
