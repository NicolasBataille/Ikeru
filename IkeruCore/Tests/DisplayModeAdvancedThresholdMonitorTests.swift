import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayModeAdvancedThresholdMonitor")
struct DisplayModeAdvancedThresholdMonitorTests {

    @Test("Reviews and mastery above thresholds → eligible")
    func allTrue() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 750,
            cardsAtFamiliarOrAbove: 75
        )
        #expect(result == .eligible)
    }

    @Test("Zero streak with enough reviews and mastery → eligible (streak no longer gated)")
    func zeroStreakDoesNotBlock() {
        // Streak is ignored. A user who never logged in two days in a row
        // but completed enough reviews and mastered enough cards should be eligible.
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 1000,
            cardsAtFamiliarOrAbove: 100
        )
        #expect(result == .eligible)
    }

    @Test("Reviews below threshold → not eligible")
    func reviewsLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 749,
            cardsAtFamiliarOrAbove: 75
        )
        #expect(result == .notEligible)
    }

    @Test("Mastery below threshold → not eligible")
    func masteryLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 800,
            cardsAtFamiliarOrAbove: 74
        )
        #expect(result == .notEligible)
    }

    @Test("Boundary values: 750 reviews / 75 mastery are inclusive")
    func boundary() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 750,
            cardsAtFamiliarOrAbove: 75
        )
        #expect(result == .eligible)
    }

    @Test("Both signals below threshold → not eligible")
    func bothLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 100,
            cardsAtFamiliarOrAbove: 10
        )
        #expect(result == .notEligible)
    }
}
