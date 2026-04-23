import Foundation

/// Learning-aligned events that represent genuine mastery progress.
/// These are the ONLY source of Epic and Legendary loot — RNG drops are
/// capped at Rare. Detected post-review, fire dedicated loot with semantic
/// names tied to what the learner actually achieved.
public enum MasteryEvent: String, Equatable, Sendable, CaseIterable {

    /// First correct review on a brand-new card (reps went from 0).
    case graduation

    /// A previously-flagged leech was just reviewed correctly.
    case leechRecovered

    /// Correct recall after a long interval (≥ 30 days).
    case longIntervalRecall

    /// Near-permanent retention milestone (interval ≥ 180 days + correct).
    case burned

    /// Rarity tier awarded for this event.
    public var rarity: LootRarity {
        switch self {
        case .graduation: .rare
        case .leechRecovered: .epic
        case .longIntervalRecall: .epic
        case .burned: .legendary
        }
    }

    /// Human-readable label for logging and UI.
    public var displayName: String {
        switch self {
        case .graduation: "Graduation"
        case .leechRecovered: "Leech Recovered"
        case .longIntervalRecall: "Lasting Recall"
        case .burned: "Burned In"
        }
    }
}
