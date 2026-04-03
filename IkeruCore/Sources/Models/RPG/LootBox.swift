import Foundation

/// A lootbox earned through session milestones.
/// Contains a challenge that must be completed to reveal rewards.
/// Failure never punishes — only delays. Infinite retries.
public struct LootBox: Codable, Sendable, Equatable, Identifiable {

    /// Unique identifier for this lootbox.
    public let id: UUID

    /// The type of challenge required to open this lootbox.
    public let challengeType: ChallengeType

    /// The score required to complete the challenge.
    public let requiredScore: Int

    /// The rewards inside (revealed after challenge completion).
    public let rewards: [LootItem]

    /// Whether this lootbox has been opened.
    public let opened: Bool

    /// When this lootbox was earned.
    public let earnedAt: Date

    public init(
        id: UUID = UUID(),
        challengeType: ChallengeType,
        requiredScore: Int,
        rewards: [LootItem],
        opened: Bool = false,
        earnedAt: Date = Date()
    ) {
        self.id = id
        self.challengeType = challengeType
        self.requiredScore = requiredScore
        self.rewards = rewards
        self.opened = opened
        self.earnedAt = earnedAt
    }

    /// Returns a new lootbox marked as opened.
    public func asOpened() -> LootBox {
        LootBox(
            id: id,
            challengeType: challengeType,
            requiredScore: requiredScore,
            rewards: rewards,
            opened: true,
            earnedAt: earnedAt
        )
    }
}

// MARK: - Challenge Types

extension LootBox {

    /// Types of challenges that can be presented to open a lootbox.
    public enum ChallengeType: String, Codable, Sendable, CaseIterable {
        /// Read N kanji correctly within a time limit.
        case kanjiSpeed
        /// Match N vocabulary items to their meanings.
        case vocabMatch
        /// Identify N kana in rapid succession.
        case kanaBlitz
        /// Answer N grammar questions correctly.
        case grammarRush

        public var displayName: String {
            switch self {
            case .kanjiSpeed: "Kanji Speed"
            case .vocabMatch: "Vocab Match"
            case .kanaBlitz: "Kana Blitz"
            case .grammarRush: "Grammar Rush"
            }
        }

        public var description: String {
            switch self {
            case .kanjiSpeed: "Read kanji correctly as fast as you can!"
            case .vocabMatch: "Match vocabulary to their meanings!"
            case .kanaBlitz: "Identify kana in rapid succession!"
            case .grammarRush: "Answer grammar questions correctly!"
            }
        }

        public var iconName: String {
            switch self {
            case .kanjiSpeed: "character.ja"
            case .vocabMatch: "list.bullet.rectangle.fill"
            case .kanaBlitz: "bolt.fill"
            case .grammarRush: "text.book.closed.fill"
            }
        }

        /// Time limit in seconds for this challenge type.
        public var timeLimitSeconds: Int {
            switch self {
            case .kanjiSpeed: 60
            case .vocabMatch: 45
            case .kanaBlitz: 30
            case .grammarRush: 60
            }
        }
    }
}
