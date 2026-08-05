import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayModeAdvancedThresholdMonitor")
struct DisplayModeAdvancedThresholdMonitorTests {

    @Test("Reviews and mastery above thresholds → eligible")
    func allTrue() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 750,
            cardsAtFamiliarOrAbove: 75,
            activeDaysCount: 0
        )
        #expect(result == .eligible)
    }

    @Test("Zero streak with enough reviews and mastery → eligible (streak no longer gated)")
    func zeroStreakDoesNotBlock() {
        // Streak is ignored. A user who never logged in two days in a row
        // but completed enough reviews and mastered enough cards should be eligible.
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 1000,
            cardsAtFamiliarOrAbove: 100,
            activeDaysCount: 0
        )
        #expect(result == .eligible)
    }

    @Test("Reviews below threshold, active days below threshold → not eligible")
    func reviewsLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 749,
            cardsAtFamiliarOrAbove: 75,
            activeDaysCount: 0
        )
        #expect(result == .notEligible)
    }

    @Test("Mastery below threshold, active days below threshold → not eligible")
    func masteryLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 800,
            cardsAtFamiliarOrAbove: 74,
            activeDaysCount: 0
        )
        #expect(result == .notEligible)
    }

    @Test("Boundary values: 750 reviews / 75 mastery are inclusive")
    func boundary() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 750,
            cardsAtFamiliarOrAbove: 75,
            activeDaysCount: 0
        )
        #expect(result == .eligible)
    }

    @Test("All signals below threshold → not eligible")
    func bothLow() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 100,
            cardsAtFamiliarOrAbove: 10,
            activeDaysCount: 5
        )
        #expect(result == .notEligible)
    }

    // MARK: - Active-days OR path

    @Test("Active days at threshold, competence below threshold → eligible via OR path")
    func activeDaysAloneMeetsThreshold() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 0,
            cardsAtFamiliarOrAbove: 0,
            activeDaysCount: 30
        )
        #expect(result == .eligible)
    }

    @Test("Active days one below threshold, competence below threshold → not eligible")
    func activeDaysJustBelowThreshold() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 0,
            cardsAtFamiliarOrAbove: 0,
            activeDaysCount: 29
        )
        #expect(result == .notEligible)
    }

    @Test("Active days above threshold and competence also met → eligible (no double gating)")
    func bothPathsSatisfied() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 800,
            cardsAtFamiliarOrAbove: 80,
            activeDaysCount: 45
        )
        #expect(result == .eligible)
    }

    @Test("Only reviews met, mastery and active days both short → not eligible (competence path is AND, not OR, between reviews/mastery)")
    func reviewsMetButMasteryAndActiveDaysShort() {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: 900,
            cardsAtFamiliarOrAbove: 10,
            activeDaysCount: 10
        )
        #expect(result == .notEligible)
    }
}
