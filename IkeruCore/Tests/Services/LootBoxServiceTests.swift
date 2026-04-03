import Testing
import Foundation
@testable import IkeruCore

@Suite("LootBoxService")
struct LootBoxServiceTests {

    @Test("Every 25 reviews awards a lootbox")
    func shouldAwardAtMilestones() {
        #expect(LootBoxService.shouldAwardLootBox(reviewsInSession: 25))
        #expect(LootBoxService.shouldAwardLootBox(reviewsInSession: 50))
        #expect(LootBoxService.shouldAwardLootBox(reviewsInSession: 75))
    }

    @Test("Non-milestone reviews do not award lootbox")
    func shouldNotAwardAtNonMilestones() {
        #expect(!LootBoxService.shouldAwardLootBox(reviewsInSession: 0))
        #expect(!LootBoxService.shouldAwardLootBox(reviewsInSession: 10))
        #expect(!LootBoxService.shouldAwardLootBox(reviewsInSession: 24))
        #expect(!LootBoxService.shouldAwardLootBox(reviewsInSession: 26))
    }

    @Test("Session milestones are recognized")
    func sessionMilestones() {
        #expect(LootBoxService.isLootBoxMilestone(totalSessions: 5))
        #expect(LootBoxService.isLootBoxMilestone(totalSessions: 10))
        #expect(LootBoxService.isLootBoxMilestone(totalSessions: 100))
        #expect(!LootBoxService.isLootBoxMilestone(totalSessions: 3))
        #expect(!LootBoxService.isLootBoxMilestone(totalSessions: 7))
    }

    @Test("Generated lootbox has valid challenge and rewards")
    func generateLootBox() {
        let box = LootBoxService.generateLootBox(level: 5)
        #expect(!box.opened)
        #expect(box.requiredScore > 0)
        #expect(!box.rewards.isEmpty)
        #expect(LootBox.ChallengeType.allCases.contains(box.challengeType))
    }

    @Test("Challenge required score scales with level")
    func challengeScoreScaling() {
        let lowLevel = LootBoxService.challengeRequiredScore(for: .kanjiSpeed, level: 1)
        let highLevel = LootBoxService.challengeRequiredScore(for: .kanjiSpeed, level: 20)
        #expect(highLevel > lowLevel)
    }

    @Test("Higher level lootbox has more rewards")
    func higherLevelMoreRewards() {
        let lowBox = LootBoxService.generateLootBox(level: 1)
        let highBox = LootBoxService.generateLootBox(level: 25)
        #expect(highBox.rewards.count >= lowBox.rewards.count)
    }

    @Test("LootBox asOpened preserves all fields except opened")
    func asOpened() {
        let box = LootBoxService.generateLootBox(level: 5)
        let opened = box.asOpened()
        #expect(opened.id == box.id)
        #expect(opened.challengeType == box.challengeType)
        #expect(opened.requiredScore == box.requiredScore)
        #expect(opened.rewards == box.rewards)
        #expect(opened.opened)
        #expect(!box.opened)
    }
}
