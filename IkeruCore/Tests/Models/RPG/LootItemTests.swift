import Testing
import Foundation
@testable import IkeruCore

@Suite("LootItem")
struct LootItemTests {

    @Test("Creation assigns unique ID and stores properties")
    func creation() {
        let item = LootItem(
            category: .badge,
            rarity: .rare,
            name: "Test Badge",
            iconName: "star.fill"
        )

        #expect(item.category == .badge)
        #expect(item.rarity == .rare)
        #expect(item.name == "Test Badge")
        #expect(item.iconName == "star.fill")
    }

    @Test("Two items with different IDs are not equal")
    func uniqueIDs() {
        let item1 = LootItem(category: .badge, rarity: .common, name: "A", iconName: "a")
        let item2 = LootItem(category: .badge, rarity: .common, name: "A", iconName: "a")
        #expect(item1 != item2) // Different UUIDs
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let item = LootItem(
            category: .scroll,
            rarity: .legendary,
            name: "Ancient Scroll",
            iconName: "scroll.fill",
            earnedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(LootItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.category == .scroll)
        #expect(decoded.rarity == .legendary)
        #expect(decoded.name == "Ancient Scroll")
        #expect(decoded.earnedAt == item.earnedAt)
    }

    @Test("All categories have display names and icons")
    func categoryProperties() {
        for category in LootItem.Category.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.iconName.isEmpty)
        }
    }
}
