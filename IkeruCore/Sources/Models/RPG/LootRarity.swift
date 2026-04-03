import Foundation

/// Rarity tier for loot items and lootbox rewards.
/// Determines visual color, glow intensity, and drop probability.
public enum LootRarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common
    case rare
    case epic
    case legendary

    /// Display name for the rarity tier.
    public var displayName: String {
        rawValue.capitalized
    }

    /// Sort order for rarity comparison.
    private var sortOrder: Int {
        switch self {
        case .common: 0
        case .rare: 1
        case .epic: 2
        case .legendary: 3
        }
    }

    public static func < (lhs: LootRarity, rhs: LootRarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
