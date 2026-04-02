import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGConstants")
struct RPGConstantsTests {

    // MARK: - XP For Level

    @Test("xpForLevel returns positive value for level 1")
    func xpForLevel1() {
        let xp = RPGConstants.xpForLevel(1)
        #expect(xp > 0)
        // Level 1: 100 * 1 * 1.2^(0.1) ~= 102
        #expect(xp >= 100)
    }

    @Test("xpForLevel increases with higher levels")
    func xpIncreases() {
        let xp1 = RPGConstants.xpForLevel(1)
        let xp5 = RPGConstants.xpForLevel(5)
        let xp10 = RPGConstants.xpForLevel(10)

        #expect(xp5 > xp1)
        #expect(xp10 > xp5)
    }

    @Test("xpForLevel handles edge case level 0")
    func xpForLevel0() {
        let xp = RPGConstants.xpForLevel(0)
        #expect(xp == RPGConstants.xpPerLevelBase)
    }

    // MARK: - Total XP For Level

    @Test("totalXPForLevel returns 0 for level 1")
    func totalXPForLevel1() {
        let total = RPGConstants.totalXPForLevel(1)
        #expect(total == 0)
    }

    @Test("totalXPForLevel accumulates correctly for level 2")
    func totalXPForLevel2() {
        let total = RPGConstants.totalXPForLevel(2)
        let level1XP = RPGConstants.xpForLevel(1)
        #expect(total == level1XP)
    }

    @Test("totalXPForLevel accumulates correctly for level 3")
    func totalXPForLevel3() {
        let total = RPGConstants.totalXPForLevel(3)
        let expected = RPGConstants.xpForLevel(1) + RPGConstants.xpForLevel(2)
        #expect(total == expected)
    }

    // MARK: - Level For XP

    @Test("levelForXP returns 1 for 0 XP")
    func levelForZeroXP() {
        let level = RPGConstants.levelForXP(0)
        #expect(level == 1)
    }

    @Test("levelForXP returns correct level just before threshold")
    func levelForXPBelowThreshold() {
        let xpNeeded = RPGConstants.xpForLevel(1)
        let level = RPGConstants.levelForXP(xpNeeded - 1)
        #expect(level == 1)
    }

    @Test("levelForXP returns next level at exact threshold")
    func levelForXPAtThreshold() {
        let xpNeeded = RPGConstants.xpForLevel(1)
        let level = RPGConstants.levelForXP(xpNeeded)
        #expect(level == 2)
    }

    @Test("levelForXP roundtrips with totalXPForLevel")
    func levelXPRoundtrip() {
        for targetLevel in 1...10 {
            let totalXP = RPGConstants.totalXPForLevel(targetLevel)
            let computedLevel = RPGConstants.levelForXP(totalXP)
            #expect(computedLevel == targetLevel, "Level \(targetLevel): totalXP=\(totalXP), computed=\(computedLevel)")
        }
    }

    // MARK: - Progress In Level

    @Test("progressInLevel returns 0 current for new player")
    func progressInLevelZeroXP() {
        let progress = RPGConstants.progressInLevel(totalXP: 0)
        #expect(progress.current == 0)
        #expect(progress.required == RPGConstants.xpForLevel(1))
    }

    @Test("progressInLevel tracks partial progress")
    func progressInLevelPartial() {
        let progress = RPGConstants.progressInLevel(totalXP: 50)
        #expect(progress.current == 50)
        #expect(progress.required == RPGConstants.xpForLevel(1))
    }

    @Test("progressInLevel resets at level boundary")
    func progressInLevelAtBoundary() {
        let xpForLevel1 = RPGConstants.xpForLevel(1)
        let progress = RPGConstants.progressInLevel(totalXP: xpForLevel1)
        #expect(progress.current == 0)
        #expect(progress.required == RPGConstants.xpForLevel(2))
    }

    // MARK: - Progress Fraction

    @Test("progressFraction returns 0 for 0 XP")
    func progressFractionZero() {
        let fraction = RPGConstants.progressFraction(totalXP: 0)
        #expect(fraction == 0.0)
    }

    @Test("progressFraction returns ~0.5 at halfway")
    func progressFractionHalfway() {
        let required = RPGConstants.xpForLevel(1)
        let halfXP = required / 2
        let fraction = RPGConstants.progressFraction(totalXP: halfXP)
        #expect(fraction > 0.4)
        #expect(fraction < 0.6)
    }

    @Test("progressFraction is clamped to 1.0 max")
    func progressFractionMax() {
        let fraction = RPGConstants.progressFraction(totalXP: 0)
        #expect(fraction <= 1.0)
    }

    // MARK: - XP For Grade

    @Test("xpForGrade returns correct values")
    func xpForGradeValues() {
        #expect(RPGConstants.xpForGrade(.easy) == 10)
        #expect(RPGConstants.xpForGrade(.good) == 10)
        #expect(RPGConstants.xpForGrade(.hard) == 5)
        #expect(RPGConstants.xpForGrade(.again) == 2)
    }
}
