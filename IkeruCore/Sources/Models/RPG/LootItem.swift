import Foundation

/// A collectible item earned through learning sessions or lootbox rewards.
/// Stored as part of RPGState's inventory.
public struct LootItem: Codable, Sendable, Equatable, Identifiable {

    /// Unique identifier for this item instance.
    public let id: UUID

    /// The category of this item.
    public let category: Category

    /// Rarity tier determining visual treatment and drop probability.
    public let rarity: LootRarity

    /// Display name shown in inventory.
    public let name: String

    /// SF Symbol name for the item icon.
    public let iconName: String

    /// When this item was earned.
    public let earnedAt: Date

    public init(
        id: UUID = UUID(),
        category: Category,
        rarity: LootRarity,
        name: String,
        iconName: String,
        earnedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.rarity = rarity
        self.name = name
        self.iconName = iconName
        self.earnedAt = earnedAt
    }
}

// MARK: - Category

extension LootItem {

    /// Categories of collectible items.
    public enum Category: String, Codable, Sendable, CaseIterable {
        /// Cosmetic theme or background.
        case theme
        /// Title displayed on profile.
        case title
        /// Badge earned for achievements.
        case badge
        /// Scroll containing Japanese proverbs or cultural notes.
        case scroll

        public var displayName: String {
            rawValue.capitalized
        }

        public var iconName: String {
            switch self {
            case .theme: "paintpalette.fill"
            case .title: "textformat"
            case .badge: "medal.fill"
            case .scroll: "scroll.fill"
            }
        }
    }
}
