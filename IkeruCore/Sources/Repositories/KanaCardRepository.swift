import Foundation
import os

/// Aggregate mastery summary for a single KanaGroup.
public struct GroupMastery: Sendable, Equatable {
    public let group: KanaGroup
    public let totalCards: Int
    public let levelDistribution: [MasteryLevel: Int]
    public let aggregatePercent: Double
    public let nextDueDate: Date?

    public init(
        group: KanaGroup,
        totalCards: Int,
        levelDistribution: [MasteryLevel: Int],
        aggregatePercent: Double,
        nextDueDate: Date?
    ) {
        self.group = group
        self.totalCards = totalCards
        self.levelDistribution = levelDistribution
        self.aggregatePercent = aggregatePercent
        self.nextDueDate = nextDueDate
    }
}

/// Kana-specific queries layered on top of `CardRepository`.
///
/// Kana cards are detected via `CardDTO.isKana` (single char in the
/// hiragana/katakana Unicode blocks). This removes any need for a schema
/// migration — kana just reuses the existing Card model with type
/// `.vocabulary`.
public actor KanaCardRepository {

    private let cardRepository: CardRepository

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    // MARK: - Seeding

    /// Idempotent: creates a Card for every base kana that doesn't already exist.
    ///
    /// Existence is detected by `front` string among current kana cards, not
    /// by UUID (CardRepository generates its own UUIDs on insert).
    public func seedIfNeeded() async {
        let existingFronts = Set(await allKanaCards().map { $0.front })

        var created = 0
        for kana in KanaGroup.allBaseCharacters where !existingFronts.contains(kana.character) {
            _ = await cardRepository.createCard(
                front: kana.character,
                back: kana.romaji,
                type: .vocabulary,
                dueDate: Date()
            )
            created += 1
        }

        if created > 0 {
            Logger.srs.info("KanaCardRepository seeded \(created) new kana cards")
        }
    }

    // MARK: - Queries

    public func allKanaCards() async -> [CardDTO] {
        let all = await cardRepository.allCards()
        return all.filter { $0.isKana }
    }

    public func cardsForGroups(_ groups: Set<KanaGroup>) async -> [CardDTO] {
        guard !groups.isEmpty else { return [] }
        let wanted: Set<String> = Set(groups.flatMap { $0.characters.map(\.character) })
        let all = await cardRepository.allCards()
        return all.filter { $0.isKana && wanted.contains($0.front) }
    }

    public func dueCardsForGroups(_ groups: Set<KanaGroup>, now: Date = Date()) async -> [CardDTO] {
        let cards = await cardsForGroups(groups)
        return cards.filter { $0.dueDate <= now }
    }

    /// Cards in the given groups whose mastery is `<= .learning` OR whose
    /// lapse/review ratio exceeds 30%.
    public func weakCardsForGroups(_ groups: Set<KanaGroup>) async -> [CardDTO] {
        let cards = await cardsForGroups(groups)
        return cards.filter { card in
            if card.masteryLevel.rawValue <= MasteryLevel.learning.rawValue {
                return true
            }
            let reps = card.fsrsState.reps
            guard reps > 0 else { return false }
            let errorRate = Double(card.fsrsState.lapses) / Double(reps)
            return errorRate > 0.30
        }
    }

    // MARK: - Aggregation

    public func mastery(for group: KanaGroup) async -> GroupMastery {
        let cards = await cardsForGroups([group])
        return Self.aggregate(group: group, cards: cards)
    }

    public func mastery(for groups: Set<KanaGroup>) async -> [KanaGroup: GroupMastery] {
        let all = await cardsForGroups(groups)
        let byFront: [String: CardDTO] = Dictionary(uniqueKeysWithValues: all.map { ($0.front, $0) })

        var result: [KanaGroup: GroupMastery] = [:]
        for group in groups {
            let groupCards = group.characters.compactMap { byFront[$0.character] }
            result[group] = Self.aggregate(group: group, cards: groupCards)
        }
        return result
    }

    // MARK: - Aggregation helpers

    private static func aggregate(group: KanaGroup, cards: [CardDTO]) -> GroupMastery {
        let total = cards.count
        var distribution: [MasteryLevel: Int] = [:]
        for level in MasteryLevel.allCases {
            distribution[level] = 0
        }

        var weightedSum = 0
        var nextDue: Date? = nil

        for card in cards {
            let level = card.masteryLevel
            distribution[level, default: 0] += 1
            weightedSum += level.rawValue

            if let current = nextDue {
                if card.dueDate < current { nextDue = card.dueDate }
            } else {
                nextDue = card.dueDate
            }
        }

        let maxPossible = 4 * max(total, 1)
        let percent: Double = total == 0 ? 0 : (Double(weightedSum) / Double(maxPossible)) * 100.0

        return GroupMastery(
            group: group,
            totalCards: total,
            levelDistribution: distribution,
            aggregatePercent: percent,
            nextDueDate: nextDue
        )
    }
}
