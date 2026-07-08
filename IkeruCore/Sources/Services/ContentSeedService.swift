import Foundation
import os

/// Seeds initial kana content for day-1 beginners.
/// This is a stateless utility — all methods are static.
public enum ContentSeedService {

    /// The five foundational hiragana vowels seeded for beginners.
    public static let beginnerHiragana: [(character: String, romanization: String)] = [
        ("あ", "a"),
        ("い", "i"),
        ("う", "u"),
        ("え", "e"),
        ("お", "o"),
    ]

    /// Seeds beginner hiragana cards into the given repository if no cards exist yet.
    /// - Parameters:
    ///   - repository: The card repository to seed into.
    ///   - existingCardCount: The current number of cards (pass 0 to force seeding).
    /// - Returns: The seeded card DTOs, or an empty array if cards already exist.
    @discardableResult
    public static func seedBeginnerKanaIfNeeded(
        repository: CardRepository,
        existingCardCount: Int
    ) async -> [CardDTO] {
        guard existingCardCount == 0 else {
            Logger.content.debug("Cards already exist (\(existingCardCount)), skipping seed")
            return []
        }

        Logger.content.info("Seeding \(beginnerHiragana.count) beginner hiragana cards")

        // Skip any vowel that already exists so a second (racing) seed can't
        // create a duplicate — defends the unique-front invariant the kana
        // mastery aggregation relies on.
        let existingFronts = Set(await repository.allCards().map { $0.front })
        var seededCards: [CardDTO] = []
        for kana in beginnerHiragana where !existingFronts.contains(kana.character) {
            let card = await repository.createCard(
                front: kana.character,
                back: kana.romanization,
                type: .kanji,
                dueDate: Date()
            )
            seededCards.append(card)
        }

        Logger.content.info("Seeded \(seededCards.count) hiragana cards successfully")
        return seededCards
    }
}
