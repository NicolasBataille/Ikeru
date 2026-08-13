import Foundation
import os
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
    /// Dormant since loot retirement 2026-07-15 — no new items are ever added
    /// (the drop/lootbox pipeline was removed); kept verbatim, along with
    /// `LootItem`'s exact stored shape, so existing profiles' inventories
    /// still decode without a SwiftData migration.
    public var lootInventoryData: Data?

    /// JSON-encoded LootBox array. Use `lootBoxes`/`setLootBoxes(_:)` accessors.
    /// Dormant since loot retirement 2026-07-15 — same rationale as
    /// `lootInventoryData` above.
    public var lootBoxesData: Data?

    /// Total sessions completed (used for lootbox milestone detection).
    /// The milestone detection itself was removed with the loot pipeline
    /// (2026-07-15); the counter is still written for streak/XP bookkeeping.
    public var totalSessionsCompleted: Int

    /// Currently equipped title item id (category == .title). Nil if none.
    public var equippedTitleID: UUID?

    /// Currently equipped theme item id (category == .theme). Nil if none.
    public var equippedThemeID: UUID?

    /// JSON-encoded [UUID] of equipped badge ids (max 3).
    public var equippedBadgeIDsData: Data?

    /// JSON-encoded `Set<ExerciseType>`. Tracks which types have already
    /// been awarded their one-time 「新しい稽古」 unlock badge so re-running
    /// the unlock service doesn't re-award them.
    public var acknowledgedUnlocksData: Data?

    /// Count of consecutive sessions that ended with zero drops. Dormant
    /// since loot retirement 2026-07-15 — the pity-timer behavior that used
    /// to read/increment this (`LootDropService`) was removed; the field is
    /// left frozen at its last value to avoid a schema migration.
    public var sessionsSinceLastDrop: Int = 0

    /// Date of the most recent completed session (day-resolution matters).
    /// Used by SessionBonusService to detect first-session-of-day / streak.
    public var lastSessionDate: Date?

    /// Current consecutive daily-session streak.
    public var currentDailyStreak: Int = 0

    /// Highest daily streak reached, for posterity.
    public var longestDailyStreak: Int = 0

    /// Lifetime count of distinct calendar days with at least one completed
    /// session (not a streak — a gap doesn't reset it). Feeds the
    /// `OR active days ≥ 30` path of `DisplayModeAdvancedThresholdMonitor`.
    /// Existing rows decode as `0` (conservative: pre-existing profiles start
    /// this count fresh rather than backfilling an approximation from
    /// `totalSessionsCompleted`, which would overcount multi-session days).
    public var activeDaysCount: Int = 0

    /// One-shot JLPT backfill schema version. `0` means the backfill has not
    /// run yet; `1` means it has completed. Existing rows decode as `0` so
    /// the boot-time backfill task fires once for migrating users. Mirrors
    /// the `acknowledgedUnlocks` precedent set by Spec A's UnlockBackfill.
    public var jlptBackfillVersion: Int = 0

    /// Last `JLPTReadinessReport.bestFit` raw value observed when the
    /// dashboard data was loaded. Used by the app layer to detect upward
    /// level crossings (Spec C `readiness.bestFit.changed` telemetry) —
    /// `nil` for fresh profiles; updated to the current best-fit on every
    /// dashboard load.
    public var lastReadinessBestFit: String?

    /// The user profile that owns this RPG state
    public var profile: UserProfile?

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). `RPGState`
    // holds monotone counters merged by `max()` per spec §5.3 rule 3, not
    // LWW — but it still needs `updatedAt`/`syncedAt` to drive the push
    // delta. Nothing reads or writes any of the three yet; that wiring is a
    // later lot.

    /// Local modification clock. Defaults to the Unix epoch at the property
    /// level so the `.lightweight` V3→V4 migration can backfill existing
    /// rows without a custom stage; the initializer below sets this to
    /// `Date()` explicitly for freshly created objects.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Tombstone. Non-nil means this row was locally deleted and awaits a
    /// sync push of the deletion.
    public var deletedAt: Date?

    /// Timestamp of the last confirmed push to the sync server. `nil` means
    /// never synced.
    public var syncedAt: Date?

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
        self.equippedTitleID = nil
        self.equippedThemeID = nil
        self.equippedBadgeIDsData = nil
        self.sessionsSinceLastDrop = 0
        self.lastSessionDate = nil
        self.currentDailyStreak = 0
        self.longestDailyStreak = 0
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }

    // MARK: - Attributes Accessors

    /// Decoded RPG attributes. Returns empty array if no data stored.
    public var attributes: [RPGAttribute] {
        guard let data = attributesData else { return [] }
        do {
            return try JSONDecoder().decode([RPGAttribute].self, from: data)
        } catch {
            Logger.rpg.error("Failed to decode RPG attributes: \(error.localizedDescription)")
            return []
        }
    }

    /// Encodes and stores the given attributes.
    public func setAttributes(_ attributes: [RPGAttribute]) {
        do {
            self.attributesData = try JSONEncoder().encode(attributes)
        } catch {
            Logger.rpg.error("Failed to encode RPG attributes: \(error.localizedDescription)")
        }
    }

    // MARK: - Loot Inventory Accessors

    /// Decoded loot inventory. Returns empty array if no data stored.
    public var lootInventory: [LootItem] {
        guard let data = lootInventoryData else { return [] }
        do {
            return try JSONDecoder().decode([LootItem].self, from: data)
        } catch {
            Logger.rpg.error("Failed to decode loot inventory: \(error.localizedDescription)")
            return []
        }
    }

    /// Encodes and stores the given inventory.
    public func setLootInventory(_ inventory: [LootItem]) {
        do {
            self.lootInventoryData = try JSONEncoder().encode(inventory)
        } catch {
            Logger.rpg.error("Failed to encode loot inventory: \(error.localizedDescription)")
        }
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
        do {
            return try JSONDecoder().decode([LootBox].self, from: data)
        } catch {
            Logger.rpg.error("Failed to decode loot boxes: \(error.localizedDescription)")
            return []
        }
    }

    /// Encodes and stores the given lootboxes.
    public func setLootBoxes(_ boxes: [LootBox]) {
        do {
            self.lootBoxesData = try JSONEncoder().encode(boxes)
        } catch {
            Logger.rpg.error("Failed to encode loot boxes: \(error.localizedDescription)")
        }
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

    // MARK: - Acknowledged Unlocks Accessors

    /// Decoded set of `ExerciseType` already acknowledged. Returns empty
    /// when no data stored. Used by `ExerciseUnlockService.newlyUnlocked`
    /// to dedup the one-time 「新しい稽古」 unlock badge.
    public var acknowledgedUnlocks: Set<ExerciseType> {
        get {
            guard let data = acknowledgedUnlocksData else { return [] }
            do {
                return try JSONDecoder().decode(Set<ExerciseType>.self, from: data)
            } catch {
                Logger.rpg.error("Failed to decode acknowledged unlocks: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                acknowledgedUnlocksData = try JSONEncoder().encode(newValue)
            } catch {
                Logger.rpg.error("Failed to encode acknowledged unlocks: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Equipped Badges Accessors

    /// Decoded equipped badge ids. Returns empty array if no data stored.
    public var equippedBadgeIDs: [UUID] {
        guard let data = equippedBadgeIDsData else { return [] }
        do {
            return try JSONDecoder().decode([UUID].self, from: data)
        } catch {
            Logger.rpg.error("Failed to decode equipped badges: \(error.localizedDescription)")
            return []
        }
    }

    /// Encodes and stores equipped badge ids (caller should enforce cap).
    public func setEquippedBadgeIDs(_ ids: [UUID]) {
        do {
            self.equippedBadgeIDsData = try JSONEncoder().encode(ids)
        } catch {
            Logger.rpg.error("Failed to encode equipped badges: \(error.localizedDescription)")
        }
    }

    // MARK: - Equipped Item Resolvers

    /// Resolved equipped title item, if any and still present in inventory.
    public var equippedTitle: LootItem? {
        guard let id = equippedTitleID else { return nil }
        return lootInventory.first { $0.id == id }
    }

    /// Resolved equipped theme item, if any and still present in inventory.
    public var equippedTheme: LootItem? {
        guard let id = equippedThemeID else { return nil }
        return lootInventory.first { $0.id == id }
    }

    /// Resolved equipped badge items (up to 3), in the order they were equipped.
    public var equippedBadges: [LootItem] {
        let ids = equippedBadgeIDs
        let inv = lootInventory
        return ids.compactMap { id in inv.first { $0.id == id } }
    }
}
