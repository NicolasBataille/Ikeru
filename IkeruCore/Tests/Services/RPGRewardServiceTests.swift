import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGRewardService")
struct RPGRewardServiceTests {

    // MARK: - Attribute Unlocks

    @Test("Level 1 unlocks reading and writing attributes")
    func level1Unlocks() {
        let unlocked = RPGRewardService.unlockedAttributes(atLevel: 1)
        let ids = Set(unlocked.map(\.id))
        #expect(ids.contains("reading"))
        #expect(ids.contains("writing"))
        #expect(!ids.contains("listening"))
    }

    @Test("Level 3 unlocks listening and speaking")
    func level3Unlocks() {
        let unlocked = RPGRewardService.unlockedAttributes(atLevel: 3)
        let ids = Set(unlocked.map(\.id))
        #expect(ids.contains("listening"))
        #expect(ids.contains("speaking"))
    }

    @Test("Level 5 unlocks grammar and vocabulary")
    func level5Unlocks() {
        let unlocked = RPGRewardService.unlockedAttributes(atLevel: 5)
        let ids = Set(unlocked.map(\.id))
        #expect(ids.contains("grammar"))
        #expect(ids.contains("vocabulary"))
    }

    @Test("Level 15 unlocks all 8 attributes")
    func level15UnlocksAll() {
        let unlocked = RPGRewardService.unlockedAttributes(atLevel: 15)
        #expect(unlocked.count == 8)
    }

    @Test("Newly unlocked excludes already owned attributes")
    func newlyUnlockedExcludesOwned() {
        let existing = [
            RPGAttribute(id: "reading", name: "Reading", iconName: "book.fill",
                        value: 10, unlockLevel: 1, description: "test"),
            RPGAttribute(id: "writing", name: "Writing", iconName: "pencil.line",
                        value: 5, unlockLevel: 1, description: "test"),
        ]

        let newly = RPGRewardService.newlyUnlockedAttributes(
            atLevel: 3,
            currentAttributes: existing
        )

        let ids = Set(newly.map(\.id))
        #expect(!ids.contains("reading"))
        #expect(!ids.contains("writing"))
        #expect(ids.contains("listening"))
        #expect(ids.contains("speaking"))
    }

    // MARK: - Level Rewards

    @Test("Level 2 gives a common badge reward")
    func level2Reward() {
        let reward = RPGRewardService.levelReward(forLevel: 2)
        #expect(reward != nil)
        #expect(reward?.rarity == .common)
        #expect(reward?.category == .badge)
        #expect(reward?.name == "First Steps")
    }

    @Test("Level 10 gives a rare badge")
    func level10Reward() {
        let reward = RPGRewardService.levelReward(forLevel: 10)
        #expect(reward != nil)
        #expect(reward?.rarity == .rare)
    }

    @Test("Level 50 gives a legendary badge")
    func level50Reward() {
        let reward = RPGRewardService.levelReward(forLevel: 50)
        #expect(reward != nil)
        #expect(reward?.rarity == .legendary)
    }

    @Test("Non-milestone levels give no reward")
    func nonMilestoneNoReward() {
        #expect(RPGRewardService.levelReward(forLevel: 3) == nil)
        #expect(RPGRewardService.levelReward(forLevel: 7) == nil)
        #expect(RPGRewardService.levelReward(forLevel: 42) == nil)
    }

    // MARK: - Attribute Value Updates

    @Test("High success rate increases matching attribute value")
    func highSuccessIncreasesValue() {
        let attrs = [
            RPGAttribute(id: "reading", name: "Reading", iconName: "book.fill",
                        value: 10, unlockLevel: 1, description: "test"),
            RPGAttribute(id: "writing", name: "Writing", iconName: "pencil.line",
                        value: 5, unlockLevel: 1, description: "test"),
        ]

        let updated = RPGRewardService.updateAttributeValues(
            attributes: attrs,
            skillID: "reading",
            successRate: 0.9
        )

        #expect(updated[0].value > 10) // reading increased
        #expect(updated[1].value == 5) // writing unchanged
    }

    @Test("Low success rate does not increase attribute")
    func lowSuccessNoIncrease() {
        let attrs = [
            RPGAttribute(id: "reading", name: "Reading", iconName: "book.fill",
                        value: 10, unlockLevel: 1, description: "test"),
        ]

        let updated = RPGRewardService.updateAttributeValues(
            attributes: attrs,
            skillID: "reading",
            successRate: 0.3
        )

        #expect(updated[0].value == 10)
    }

    @Test("Attribute value never exceeds 100")
    func attributeValueCapsAt100() {
        let attrs = [
            RPGAttribute(id: "reading", name: "Reading", iconName: "book.fill",
                        value: 99, unlockLevel: 1, description: "test"),
        ]

        let updated = RPGRewardService.updateAttributeValues(
            attributes: attrs,
            skillID: "reading",
            successRate: 1.0
        )

        #expect(updated[0].value == 100)
    }
}
