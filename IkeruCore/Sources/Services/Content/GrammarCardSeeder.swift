import Foundation
import os

// MARK: - GrammarCardSeeder

/// Creates one FSRS card per bundled grammar point, so grammar is **scheduled**
/// like kanji and vocabulary rather than merely readable.
///
/// ## Why this exists
///
/// Measured 2026-08-19: `CardType.grammar` had existed in the model since the
/// first content build and **no card of that type was ever created**, anywhere.
/// The consequences ran all the way up:
///
/// - a session's `.grammarExercise` carried a fabricated `UUID()` pointing at
///   no point at all, and rendered a placeholder card reading
///   "Grammar Exercise / Grammar point";
/// - `LearnerSnapshotBuilder` has a `.grammar` branch that could never fire;
/// - `HomeViewModel` passed `grammarPointsFamiliarPlus: 0` hardcoded, so the
///   JLPT-readiness formula ignored grammar entirely.
///
/// ⚠️ **Rien n'appelle ce semeur aujourd'hui, et c'est delibere.** Il a d'abord
/// ete branche au lancement de l'app, apres l'initialisation du profil. Mesure
/// le 2026-08-19, ca cassait deux choses d'un coup :
///
/// - les 51 cartes naissaient **dues immediatement**, donc un profil « rien
///   n'est du » ne l'etait plus jamais et la proposition « tout est a jour »
///   disparaissait. C'est aussi exactement ce que la decision produit 1 refuse :
///   remplir la file sans que personne l'ait demande ;
/// - le `Task` de semis **coursait** l'initialisation du profil : sur un
///   profil de fixture, les 92 kana disparaissaient et il ne restait que les
///   51 cartes de grammaire (capture a l'appui).
///
/// La suite UI l'a attrape (`testTappingAnOfferStartsASession` : « No caught-up
/// offer was available to tap »).
///
/// Le bon declencheur reste a concevoir : une carte creee **quand l'apprenant
/// repond a l'exercice de ce point**, incrementale, jamais en bloc. L'exercice
/// lui-meme n'en depend pas — il lit `grammarClozes` depuis le bundle — donc il
/// fonctionne sans, ce qui manque est la planification.
///
/// ## Idempotent on `front`
///
/// The front is the point's title, which is unique per point. Seeding skips any
/// front already present, so a second call — a racing launch, a re-seed after a
/// profile wipe — cannot create duplicates. That matters more than it looks:
/// the kana seeder learned the same lesson, and its doc comment says so.
public enum GrammarCardSeeder {

    /// Seeds a card per grammar point that has none yet.
    ///
    /// - Parameters:
    ///   - points: The bundled grammar points, in display order.
    ///   - repository: Where cards live.
    ///   - existingFronts: Fronts already present, so this stays a pure
    ///     decision the caller can test without a database.
    /// - Returns: The points that a card was created for.
    public static func pointsNeedingCards(
        _ points: [GrammarPoint],
        existingFronts: Set<String>
    ) -> [GrammarPoint] {
        points.filter { !$0.title.isEmpty && !existingFronts.contains($0.title) }
    }

    /// Seeds the missing grammar cards and returns what it created.
    @discardableResult
    public static func seedIfNeeded(
        points: [GrammarPoint],
        repository: CardRepository
    ) async -> [CardDTO] {
        let existingFronts = Set(await repository.allCards().map(\.front))
        let missing = pointsNeedingCards(points, existingFronts: existingFronts)
        guard !missing.isEmpty else { return [] }

        Logger.content.info("Seeding \(missing.count) grammar cards")
        var created: [CardDTO] = []
        for point in missing {
            // Front = le titre (« てもいい (Permission) »), dos = l'explication.
            // L'exercice a trou n'utilise ni l'un ni l'autre — il lit
            // `grammarClozes` — mais la carte doit rester lisible telle quelle
            // si elle tombe dans une revue générique.
            let card = await repository.createCard(
                front: point.title,
                back: point.explanation,
                type: .grammar,
                dueDate: Date()
            )
            created.append(card)
        }
        return created
    }
}
