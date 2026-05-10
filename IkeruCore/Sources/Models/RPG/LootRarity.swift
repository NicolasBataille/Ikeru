import Foundation

/// Rarity tier for loot items and lootbox rewards.
/// Determines visual color, glow intensity, and drop probability.
public enum LootRarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common
    case uncommon
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
        case .uncommon: 1
        case .rare: 2
        case .epic: 3
        case .legendary: 4
        }
    }

    public static func < (lhs: LootRarity, rhs: LootRarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
