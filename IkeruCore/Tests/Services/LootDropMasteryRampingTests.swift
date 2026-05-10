import Testing
@testable import IkeruCore

/// Verifies that mastery-event drops use `BadgeRamping` to scale rarity by
/// learner level. The legacy `generateMasteryDrop(for:)` used the static
/// `MasteryEvent.rarity` table, which fired the same Legendary celebration
/// for a new N5 player as for an N1 veteran. The new overload threads
/// `learnerLevel` through and lets `BadgeRamping` decide.
@Suite("LootDropService.generateMasteryDrop ramping")
struct LootDropMasteryRampingTests {

    @Test("Burned at N5 is rare; same event at N2 is legendary")
    func burnedRamping() {
        let n5Drop = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n5)
        let n2Drop = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n2)
        #expect(n5Drop.rarity == .rare)
        #expect(n2Drop.rarity == .legendary)
    }

    @Test("Iconography stays consistent across levels (only rarity changes)")
    func iconUnchanged() {
        let n5 = LootDropService.generateMasteryDrop(for: .graduation, learnerLevel: .n5)
        let n1 = LootDropService.generateMasteryDrop(for: .graduation, learnerLevel: .n1)
        #expect(n5.iconName == n1.iconName)
        #expect(n5.name == n1.name)
        #expect(n5.rarity == .common)
        #expect(n1.rarity == .uncommon)
    }

    @Test("Long-interval recall ramps N5 uncommon -> N3 rare -> N1 epic")
    func longIntervalRecallRamping() {
        let n5 = LootDropService.generateMasteryDrop(for: .longIntervalRecall, learnerLevel: .n5)
        let n3 = LootDropService.generateMasteryDrop(for: .longIntervalRecall, learnerLevel: .n3)
        let n1 = LootDropService.generateMasteryDrop(for: .longIntervalRecall, learnerLevel: .n1)
        #expect(n5.rarity == .uncommon)
        #expect(n3.rarity == .rare)
        #expect(n1.rarity == .epic)
    }

    @Test("Leech recovered ramps N5 rare -> N3 epic -> N1 legendary")
    func leechRecoveredRamping() {
        let n5 = LootDropService.generateMasteryDrop(for: .leechRecovered, learnerLevel: .n5)
        let n3 = LootDropService.generateMasteryDrop(for: .leechRecovered, learnerLevel: .n3)
        let n1 = LootDropService.generateMasteryDrop(for: .leechRecovered, learnerLevel: .n1)
        #expect(n5.rarity == .rare)
        #expect(n3.rarity == .epic)
        #expect(n1.rarity == .legendary)
    }

    @Test("Drop name and category come from the event's template, not from BadgeRamping")
    func templateOwnership() {
        // Burned → "Burned In" (.title) regardless of level.
        let n5 = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n5)
        let n1 = LootDropService.generateMasteryDrop(for: .burned, learnerLevel: .n1)
        #expect(n5.name == "Burned In")
        #expect(n1.name == "Burned In")
        #expect(n5.category == .title)
        #expect(n1.category == .title)
    }
}
