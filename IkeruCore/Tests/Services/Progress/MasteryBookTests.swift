import Testing
import Foundation
@testable import IkeruCore

@Suite("MasteryBookCounts — competency-booklet aggregation")
struct MasteryBookTests {

    @Test("Buckets cards by mastery level")
    func bucketsCards() {
        let cards = [
            fixtureCard(stability: 0, reps: 0),      // new
            fixtureCard(stability: 0.5, reps: 1),    // learning (stability < 1)
            fixtureCard(stability: 5, reps: 2),      // familiar
            fixtureCard(stability: 10, reps: 2),     // mastered
            fixtureCard(stability: 90, reps: 2),     // anchored
        ]
        let counts = MasteryBookCounts.from(cards: cards)

        #expect(counts.newCount == 1)
        #expect(counts.learningCount == 1)
        #expect(counts.familiarCount == 1)
        #expect(counts.masteredCount == 1)
        #expect(counts.anchoredCount == 1)
        #expect(counts.totalCount == 5)
        #expect(counts.knownCount == 3, "familiar + mastered + anchored")
    }

    @Test("Empty pool yields all-zero counts")
    func emptyPool() {
        let counts = MasteryBookCounts.from(cards: [])
        #expect(counts.totalCount == 0)
        #expect(counts.knownCount == 0)
    }

    @Test("Combining two snapshots sums level-by-level")
    func combinesWithPlus() {
        let first = MasteryBookCounts(newCount: 2, learningCount: 1, familiarCount: 0, masteredCount: 0, anchoredCount: 0)
        let second = MasteryBookCounts(newCount: 0, learningCount: 1, familiarCount: 3, masteredCount: 0, anchoredCount: 0)
        let sum = first + second
        #expect(sum.newCount == 2)
        #expect(sum.learningCount == 2)
        #expect(sum.familiarCount == 3)
        #expect(sum.totalCount == 7)
    }

    @Test("Delta reports the change in known (familiar+) count, including negative deltas")
    func deltaTracksKnownChange() {
        let before = MasteryBookCounts(newCount: 10, learningCount: 5, familiarCount: 2, masteredCount: 0, anchoredCount: 0)
        let after = MasteryBookCounts(newCount: 8, learningCount: 5, familiarCount: 4, masteredCount: 0, anchoredCount: 0)
        #expect(after.delta(from: before) == 2)
        #expect(before.delta(from: after) == -2, "a lapse-driven regression must be reported honestly, not clamped")
    }

    // MARK: - Fixtures

    private func fixtureCard(stability: Double, reps: Int) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: "\u{3042}",
            back: "x",
            type: .vocabulary,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: stability,
                reps: reps,
                lapses: 0,
                lastReview: nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
    }
}
