import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGService")
struct RPGServiceTests {

    // MARK: - XP Award

    @Test("awardXP gives 10 XP for Good grade")
    func awardXPGood() {
        let result = RPGService.awardXP(
            grade: .good,
            currentXP: 0,
            currentLevel: 1,
            totalReviews: 0
        )
        #expect(result.xpAwarded == 10)
        #expect(result.newXP == 10)
        #expect(result.newTotalReviews == 1)
    }

    @Test("awardXP gives 10 XP for Easy grade")
    func awardXPEasy() {
        let result = RPGService.awardXP(
            grade: .easy,
            currentXP: 0,
            currentLevel: 1,
            totalReviews: 0
        )
        #expect(result.xpAwarded == 10)
        #expect(result.newXP == 10)
    }

    @Test("awardXP gives 5 XP for Hard grade")
    func awardXPHard() {
        let result = RPGService.awardXP(
            grade: .hard,
            currentXP: 0,
            currentLevel: 1,
            totalReviews: 0
        )
        #expect(result.xpAwarded == 5)
        #expect(result.newXP == 5)
    }

    @Test("awardXP gives 2 XP for Again grade")
    func awardXPAgain() {
        let result = RPGService.awardXP(
            grade: .again,
            currentXP: 0,
            currentLevel: 1,
            totalReviews: 0
        )
        #expect(result.xpAwarded == 2)
        #expect(result.newXP == 2)
    }

    @Test("awardXP accumulates XP correctly")
    func awardXPAccumulates() {
        let result = RPGService.awardXP(
            grade: .good,
            currentXP: 50,
            currentLevel: 1,
            totalReviews: 5
        )
        #expect(result.newXP == 60)
        #expect(result.newTotalReviews == 6)
    }

    // MARK: - Level Up Detection

    @Test("awardXP detects level-up when XP crosses threshold")
    func awardXPDetectsLevelUp() {
        let xpNeeded = RPGConstants.xpForLevel(1)
        // Give enough XP to be just under the threshold, then award to cross it
        let result = RPGService.awardXP(
            grade: .good,
            currentXP: xpNeeded - 5,
            currentLevel: 1,
            totalReviews: 10
        )
        #expect(result.didLevelUp == true)
        #expect(result.newLevel == 2)
    }

    @Test("awardXP does not flag level-up when staying same level")
    func awardXPNoLevelUp() {
        let result = RPGService.awardXP(
            grade: .good,
            currentXP: 0,
            currentLevel: 1,
            totalReviews: 0
        )
        #expect(result.didLevelUp == false)
        #expect(result.newLevel == 1)
    }

    @Test("awardXP at exact threshold does not double-level")
    func awardXPAtExactThreshold() {
        let xpForLevel1 = RPGConstants.xpForLevel(1)
        let result = RPGService.awardXP(
            grade: .good,
            currentXP: xpForLevel1,
            currentLevel: 2,
            totalReviews: 20
        )
        #expect(result.didLevelUp == false)
        #expect(result.newLevel == 2)
    }

    // MARK: - Near Level Up

    @Test("isNearLevelUp returns true when within 10% of threshold")
    func nearLevelUpTrue() {
        let required = RPGConstants.xpForLevel(1)
        let nearXP = Int(Double(required) * 0.95)
        #expect(RPGService.isNearLevelUp(totalXP: nearXP) == true)
    }

    @Test("isNearLevelUp returns false when far from threshold")
    func nearLevelUpFalse() {
        let required = RPGConstants.xpForLevel(1)
        let farXP = Int(Double(required) * 0.5)
        #expect(RPGService.isNearLevelUp(totalXP: farXP) == false)
    }

    @Test("isNearLevelUp returns false for 0 XP")
    func nearLevelUpZero() {
        #expect(RPGService.isNearLevelUp(totalXP: 0) == false)
    }
}
