import Testing
import Foundation
@testable import IkeruCore

@Suite("LeechDetectionService")
struct LeechDetectionServiceTests {

    // MARK: - Detection

    @Test("No leech event when grade is not Again")
    func noLeechOnGoodGrade() {
        let card = makeCard(lapseCount: 5, leechFlag: false)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .good)
        #expect(result == nil)
    }

    @Test("No leech event when lapse count is below threshold")
    func noLeechBelowThreshold() {
        let card = makeCard(lapseCount: 1, leechFlag: false)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .again)
        #expect(result == nil)
    }

    @Test("Leech detected when lapse count reaches threshold")
    func leechDetectedAtThreshold() {
        // Card has 2 lapses, grading Again will make it 3 (the threshold)
        let card = makeCard(lapseCount: 2, leechFlag: false)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .again, threshold: 3)
        #expect(result != nil)
        #expect(result?.lapseCount == 3)
        #expect(result?.isNewLeech == true)
    }

    @Test("Leech detected for recurring leech (already flagged)")
    func recurringLeechDetected() {
        let card = makeCard(lapseCount: 5, leechFlag: true)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .again, threshold: 3)
        #expect(result != nil)
        #expect(result?.isNewLeech == false)
    }

    @Test("Custom threshold is respected")
    func customThreshold() {
        let card = makeCard(lapseCount: 4, leechFlag: false)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .again, threshold: 5)
        #expect(result != nil)
        #expect(result?.lapseCount == 5)
    }

    @Test("No leech when Hard grade even with high lapses")
    func noLeechOnHardGrade() {
        let card = makeCard(lapseCount: 10, leechFlag: false)
        let result = LeechDetectionService.checkForLeech(card: card, grade: .hard)
        #expect(result == nil)
    }

    // MARK: - Confusion Analysis

    @Test("Kanji confusion detects visually similar pair")
    func kanjiVisuallySimilar() {
        let card = makeCard(front: "日", back: "day/sun", type: .kanji)
        let pattern = LeechDetectionService.analyzeConfusion(card: card)
        #expect(pattern.type == .visuallySimilar)
        #expect(pattern.description.contains("目"))
    }

    @Test("Kanji confusion falls back to general difficulty for unknown kanji")
    func kanjiGeneralDifficulty() {
        let card = makeCard(front: "龍", back: "dragon", type: .kanji)
        let pattern = LeechDetectionService.analyzeConfusion(card: card)
        #expect(pattern.type == .generalDifficulty)
    }

    @Test("Vocabulary confusion returns general difficulty")
    func vocabularyConfusion() {
        let card = makeCard(front: "食べる", back: "to eat", type: .vocabulary)
        let pattern = LeechDetectionService.analyzeConfusion(card: card)
        #expect(pattern.type == .generalDifficulty)
        #expect(pattern.target == "食べる")
    }

    @Test("Grammar confusion returns general difficulty")
    func grammarConfusion() {
        let card = makeCard(front: "〜ている", back: "progressive", type: .grammar)
        let pattern = LeechDetectionService.analyzeConfusion(card: card)
        #expect(pattern.type == .generalDifficulty)
    }

    // MARK: - Helpers

    private func makeCard(
        front: String = "日",
        back: String = "day/sun",
        type: CardType = .kanji,
        lapseCount: Int = 0,
        leechFlag: Bool = false
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: back,
            type: type,
            fsrsState: FSRSState(lapses: lapseCount),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(),
            lapseCount: lapseCount,
            leechFlag: leechFlag
        )
    }
}
