import Foundation
import os

/// Pure-function service for lootbox generation and milestone detection.
/// Lootboxes are earned through session milestones and opened via challenges.
public enum LootBoxService {

    // MARK: - Milestone Detection

    /// Session milestones that award lootboxes.
    /// These map to cumulative session counts.
    static let milestoneSessions: Set<Int> = [5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500]

    /// Checks if a total session count hits a lootbox milestone.
    /// - Parameter totalSessions: Total completed sessions (cumulative).
    /// - Returns: True if this session count earns a lootbox.
    public static func isLootBoxMilestone(totalSessions: Int) -> Bool {
        milestoneSessions.contains(totalSessions)
    }

    /// Checks if a reviews-in-session count triggers a lootbox.
    /// A lootbox is earned every 25 reviews within a single session.
    /// - Parameter reviewsInSession: Reviews completed in the current session.
    /// - Returns: True if this review count triggers a lootbox.
    public static func shouldAwardLootBox(reviewsInSession: Int) -> Bool {
        reviewsInSession > 0 && reviewsInSession % 25 == 0
    }

    // MARK: - Lootbox Generation

    /// Generates a lootbox with a random challenge and rewards.
    /// Reward rarity scales with player level.
    /// - Parameter level: The player's current RPG level.
    /// - Returns: A new unopened lootbox.
    public static func generateLootBox(level: Int) -> LootBox {
        guard let challengeType = LootBox.ChallengeType.allCases.randomElement() else {
            // ChallengeType.allCases is never empty, but guard against the impossible
            let fallback = LootBox.ChallengeType.kanjiSpeed
            let requiredScore = challengeRequiredScore(for: fallback, level: level)
            let rewards = generateRewards(level: level)
            return LootBox(challengeType: fallback, requiredScore: requiredScore, rewards: rewards)
        }
        let requiredScore = challengeRequiredScore(for: challengeType, level: level)
        let rewards = generateRewards(level: level)

        Logger.rpg.info(
            "Lootbox generated: \(challengeType.displayName), req=\(requiredScore), rewards=\(rewards.count)"
        )

        return LootBox(
            challengeType: challengeType,
            requiredScore: requiredScore,
            rewards: rewards
        )
    }

    // MARK: - Challenge Configuration

    /// Determines the required score for a challenge.
    /// Scales mildly with level to maintain engagement.
    /// - Parameters:
    ///   - type: The challenge type.
    ///   - level: The player's level.
    /// - Returns: Required score to complete the challenge.
    static func challengeRequiredScore(for type: LootBox.ChallengeType, level: Int) -> Int {
        let base: Int
        switch type {
        case .kanjiSpeed: base = 8
        case .vocabMatch: base = 6
        case .kanaBlitz: base = 10
        case .grammarRush: base = 5
        }
        // Scale gently: +1 per 5 levels, capped at base * 2
        let levelBonus = min(base, level / 5)
        return base + levelBonus
    }

    // MARK: - Reward Generation

    /// Generates 1-3 reward items for a lootbox.
    /// Higher-level players get more items and better rarity.
    private static func generateRewards(level: Int) -> [LootItem] {
        let rewardCount = min(3, 1 + (level / 10))
        return (0..<rewardCount).map { _ in
            LootDropService.generateDrop(level: level)
        }
    }
}
