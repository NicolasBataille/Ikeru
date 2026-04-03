import Foundation
import SwiftData

/// Persistent RPG progression state for a user profile.
/// Tracks experience points, level, attributes, and loot inventory.
@Model
public final class RPGState {

    /// Unique identifier for the RPG state
    public var id: UUID

    /// Total experience points earned
    public var xp: Int

    /// Current level
    public var level: Int

    /// Total number of reviews completed across all sessions
    public var totalReviewsCompleted: Int

    /// JSON-encoded RPGAttribute array. Use `attributes`/`setAttributes(_:)` accessors.
    public var attributesData: Data?

    /// JSON-encoded LootItem array. Use `lootInventory`/`setLootInventory(_:)` accessors.
    public var lootInventoryData: Data?

    /// JSON-encoded LootBox array. Use `lootBoxes`/`setLootBoxes(_:)` accessors.
    public var lootBoxesData: Data?

    /// Total sessions completed (used for lootbox milestone detection).
    public var totalSessionsCompleted: Int

    /// The user profile that owns this RPG state
    public var profile: UserProfile?

    public init(
        xp: Int = 0,
        level: Int = 1,
        totalReviewsCompleted: Int = 0
    ) {
        self.id = UUID()
        self.xp = xp
        self.level = level
        self.totalReviewsCompleted = totalReviewsCompleted
        self.attributesData = nil
        self.lootInventoryData = nil
        self.lootBoxesData = nil
        self.totalSessionsCompleted = 0
    }

    // MARK: - Attributes Accessors

    /// Decoded RPG attributes. Returns empty array if no data stored.
    public var attributes: [RPGAttribute] {
        guard let data = attributesData else { return [] }
        return (try? JSONDecoder().decode([RPGAttribute].self, from: data)) ?? []
    }

    /// Encodes and stores the given attributes.
    public func setAttributes(_ attributes: [RPGAttribute]) {
        self.attributesData = try? JSONEncoder().encode(attributes)
    }

    // MARK: - Loot Inventory Accessors

    /// Decoded loot inventory. Returns empty array if no data stored.
    public var lootInventory: [LootItem] {
        guard let data = lootInventoryData else { return [] }
        return (try? JSONDecoder().decode([LootItem].self, from: data)) ?? []
    }

    /// Encodes and stores the given inventory.
    public func setLootInventory(_ inventory: [LootItem]) {
        self.lootInventoryData = try? JSONEncoder().encode(inventory)
    }

    /// Adds a single loot item to the inventory.
    public func addLootItem(_ item: LootItem) {
        var current = lootInventory
        current.append(item)
        setLootInventory(current)
    }

    // MARK: - LootBox Accessors

    /// Decoded lootboxes. Returns empty array if no data stored.
    public var lootBoxes: [LootBox] {
        guard let data = lootBoxesData else { return [] }
        return (try? JSONDecoder().decode([LootBox].self, from: data)) ?? []
    }

    /// Encodes and stores the given lootboxes.
    public func setLootBoxes(_ boxes: [LootBox]) {
        self.lootBoxesData = try? JSONEncoder().encode(boxes)
    }

    /// Adds a single lootbox.
    public func addLootBox(_ box: LootBox) {
        var current = lootBoxes
        current.append(box)
        setLootBoxes(current)
    }

    /// Marks a lootbox as opened and moves its rewards to inventory.
    public func openLootBox(id: UUID) {
        var boxes = lootBoxes
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        let box = boxes[index]
        boxes[index] = box.asOpened()
        setLootBoxes(boxes)

        // Add rewards to inventory
        for reward in box.rewards {
            addLootItem(reward)
        }
    }

    /// Returns unopened lootboxes.
    public var unopenedLootBoxes: [LootBox] {
        lootBoxes.filter { !$0.opened }
    }
}
