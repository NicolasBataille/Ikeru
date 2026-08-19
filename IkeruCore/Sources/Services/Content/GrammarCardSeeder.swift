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
/// Seeding real cards is what turns all three from dead branches into live
/// ones.
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
