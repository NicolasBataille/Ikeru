import Testing
@testable import IkeruCore

@Suite("BadgeRamping.rarity")
struct BadgeRampingTests {

    @Test("Burned at N5 = rare; Burned at N2 = legendary")
    func burnedRamps() {
        #expect(BadgeRamping.rarity(for: .burned, learnerLevel: .n5) == .rare)
        #expect(BadgeRamping.rarity(for: .burned, learnerLevel: .n2) == .legendary)
    }

    @Test("Graduation N5..N3 = common, N2..N1 = uncommon")
    func graduationRamps() {
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n5) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n4) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n3) == .common)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n2) == .uncommon)
        #expect(BadgeRamping.rarity(for: .graduation, learnerLevel: .n1) == .uncommon)
    }

    @Test("LongIntervalRecall N5=uncommon, N3=rare, N1=epic")
    func longIntervalRamps() {
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n5) == .uncommon)
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n3) == .rare)
        #expect(BadgeRamping.rarity(for: .longIntervalRecall, learnerLevel: .n1) == .epic)
    }

    @Test("LeechRecovered N5..N4=rare, N3..N2=epic, N1=legendary")
    func leechRamps() {
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n5) == .rare)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n4) == .rare)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n3) == .epic)
        #expect(BadgeRamping.rarity(for: .leechRecovered, learnerLevel: .n1) == .legendary)
    }
}
