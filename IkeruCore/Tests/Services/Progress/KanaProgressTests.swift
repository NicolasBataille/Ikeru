import Testing
import Foundation
@testable import IkeruCore

@Suite("KanaProgress — familiar+ kana counting")
struct KanaProgressTests {

    @Test("Counts familiar-or-better kana, bucketed by script")
    func bucketsByScript() {
        let cards = [
            fixtureCard(front: "\u{3042}", stability: 5, reps: 2),    // あ hiragana → familiar ✓
            fixtureCard(front: "\u{30A2}", stability: 10, reps: 2),   // ア katakana → mastered ✓
            fixtureCard(front: "\u{3044}", stability: 5, reps: 0), // い → new ✗
            fixtureCard(front: "\u{3046}", stability: 0.5),  // う → learning ✗ (stability < 1)
            fixtureCard(front: "\u{706B}", stability: 100),  // 火 kanji → not in base sets ✗
        ]
        let progress = KanaProgress.from(cards: cards)

        #expect(progress.hiraganaMastered == 1, "only あ is familiar+ hiragana")
        #expect(progress.katakanaMastered == 1, "only ア is familiar+ katakana")
        #expect(progress.total == 2)
    }

    @Test("Empty pool yields zero, denominator is a fixed 92")
    func emptyAndDenominator() {
        let progress = KanaProgress.from(cards: [])
        #expect(progress.total == 0)
        #expect(KanaProgress.grandTotal == 92)
        #expect(KanaProgress.hiraganaTotal == 46)
        #expect(KanaProgress.katakanaTotal == 46)
    }

    @Test("A first session (reps < 2) counts as learning, not silence")
    func firstSessionLeavesALearningTrace() {
        // One "Good" tap each: reps == 1, stability well below the familiar
        // gate — MasteryLevel.from correctly refuses .familiar (reps >= 2
        // gate), but the learner should still see SOMETHING move.
        let cards = [
            fixtureCard(front: "\u{3042}", stability: 3.13, reps: 1),  // あ hiragana
            fixtureCard(front: "\u{30A2}", stability: 3.13, reps: 1),  // ア katakana
        ]
        let progress = KanaProgress.from(cards: cards)

        #expect(progress.total == 0, "reps < 2 must never count as mastered")
        #expect(progress.hiraganaLearning == 1)
        #expect(progress.katakanaLearning == 1)
        #expect(progress.learningTotal == 2)
    }

    private func fixtureCard(
        front: String,
        stability: Double,
        reps: Int = 1
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
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
