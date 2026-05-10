import Foundation

/// Pure-function service for equipping / unequipping cosmetic loot items.
/// Does not persist — mutates the passed RPGState directly. Callers save via SwiftData.
public enum EquipmentService {

    /// Maximum number of badges that can be equipped simultaneously.
    public static let maxEquippedBadges: Int = 3

    /// Toggles the equipped state of an item in the given RPGState.
    /// Rules:
    /// - Title and theme are single-slot — equipping replaces the previous one.
    /// - Badges allow up to `maxEquippedBadges` equipped at once (FIFO eviction).
    /// - Scrolls are not equippable (they're readable notes).
    public static func toggleEquip(_ item: LootItem, in state: RPGState) {
        if isEquipped(item, in: state) {
            unequip(item, in: state)
        } else {
            equip(item, in: state)
        }
    }

    /// Equips the given item, respecting category-specific rules.
    public static func equip(_ item: LootItem, in state: RPGState) {
        switch item.category {
        case .title:
            state.equippedTitleID = item.id
        case .theme:
            state.equippedThemeID = item.id
        case .badge:
            var ids = state.equippedBadgeIDs.filter { $0 != item.id }
            ids.append(item.id)
            if ids.count > maxEquippedBadges {
                ids.removeFirst(ids.count - maxEquippedBadges)
            }
            state.setEquippedBadgeIDs(ids)
        case .scroll:
            break
        }
    }

    /// Unequips the given item if it is currently equipped.
    public static func unequip(_ item: LootItem, in state: RPGState) {
        switch item.category {
        case .title:
            if state.equippedTitleID == item.id { state.equippedTitleID = nil }
        case .theme:
            if state.equippedThemeID == item.id { state.equippedThemeID = nil }
        case .badge:
            let remaining = state.equippedBadgeIDs.filter { $0 != item.id }
            state.setEquippedBadgeIDs(remaining)
        case .scroll:
            break
        }
    }

    /// True if the given item is currently equipped in its category.
    public static func isEquipped(_ item: LootItem, in state: RPGState) -> Bool {
        switch item.category {
        case .title: return state.equippedTitleID == item.id
        case .theme: return state.equippedThemeID == item.id
        case .badge: return state.equippedBadgeIDs.contains(item.id)
        case .scroll: return false
        }
    }

    /// True if the category supports equipping (titles, themes, badges).
    public static func isEquippable(_ item: LootItem) -> Bool {
        switch item.category {
        case .title, .theme, .badge: return true
        case .scroll: return false
        }
    }
}
