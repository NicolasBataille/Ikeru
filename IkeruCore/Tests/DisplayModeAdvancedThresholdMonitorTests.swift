import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayModeAdvancedThresholdMonitor")
struct DisplayModeAdvancedThresholdMonitorTests {

    @Test("All three signals true → eligible")
    func allTrue() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 21,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .eligible)
    }

    @Test("Streak below threshold → not eligible")
    func streakLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 20,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .notEligible)
    }

    @Test("Reviews below threshold → not eligible")
    func reviewsLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 30,
            totalReviewsCompleted: 499,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .notEligible)
    }

    @Test("Mastery below threshold → not eligible")
    func masteryLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 30,
            totalReviewsCompleted: 600,
            cardsAtFamiliarOrAbove: 49
        )
        #expect(result == .notEligible)
    }

    @Test("Boundary values: 21 / 500 / 50 are inclusive")
    func boundary() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: 21,
            totalReviewsCompleted: 500,
            cardsAtFamiliarOrAbove: 50
        )
        #expect(result == .eligible)
    }
}
