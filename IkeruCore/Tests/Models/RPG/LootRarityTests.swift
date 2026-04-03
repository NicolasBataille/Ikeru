import Testing
@testable import IkeruCore

@Suite("LootRarity")
struct LootRarityTests {

    @Test("Rarity ordering follows tier progression")
    func rarityOrdering() {
        #expect(LootRarity.common < .rare)
        #expect(LootRarity.rare < .epic)
        #expect(LootRarity.epic < .legendary)
        #expect(!(LootRarity.legendary < .common))
    }

    @Test("All cases have display names")
    func displayNames() {
        for rarity in LootRarity.allCases {
            #expect(!rarity.displayName.isEmpty)
        }
    }

    @Test("Codable round-trip preserves value", arguments: LootRarity.allCases)
    func codableRoundTrip(rarity: LootRarity) throws {
        let data = try JSONEncoder().encode(rarity)
        let decoded = try JSONDecoder().decode(LootRarity.self, from: data)
        #expect(decoded == rarity)
    }
}
