import Testing
import Foundation
@testable import IkeruCore

@Suite("LootBoxQuizService")
struct LootBoxQuizServiceTests {

    @Test("Builds a question from real cards with the target's front as prompt")
    func buildsQuestionFromCards() {
        let cards = [
            makeCard(front: "水", back: "water"),
            makeCard(front: "火", back: "fire"),
            makeCard(front: "木", back: "tree"),
            makeCard(front: "金", back: "gold"),
        ]
        var rng = SeededGenerator(seed: 1)

        let question = LootBoxQuizService.makeQuestion(from: cards, rng: &rng)

        #expect(question != nil)
        guard let question else { return }
        let fronts = Set(cards.map(\.front))
        #expect(fronts.contains(question.prompt))
        #expect(question.choices.contains(question.correctAnswer))
        // The correct answer must match whichever card's front was chosen as prompt.
        let matchingCard = cards.first { $0.front == question.prompt }
        #expect(matchingCard?.back == question.correctAnswer)
    }

    @Test("Choices never repeat the correct answer twice")
    func choicesHaveNoDuplicateAnswers() {
        let cards = [
            makeCard(front: "水", back: "water"),
            makeCard(front: "火", back: "fire"),
            makeCard(front: "木", back: "tree"),
        ]
        var rng = SeededGenerator(seed: 42)

        let question = LootBoxQuizService.makeQuestion(from: cards, rng: &rng)

        #expect(question != nil)
        guard let question else { return }
        let lowered = question.choices.map { $0.lowercased() }
        #expect(Set(lowered).count == lowered.count)
    }

    @Test("Skips cards with empty front or back")
    func skipsBlankCards() {
        let cards = [
            makeCard(front: "", back: "water"),
            makeCard(front: "火", back: ""),
            makeCard(front: "木", back: "tree"),
            makeCard(front: "金", back: "gold"),
        ]
        var rng = SeededGenerator(seed: 7)

        let question = LootBoxQuizService.makeQuestion(from: cards, rng: &rng)

        #expect(question != nil)
        guard let question else { return }
        #expect(question.prompt != "" && question.prompt != "火")
        for choice in question.choices {
            #expect(!choice.isEmpty)
        }
    }

    @Test("Returns nil for an empty card pool (caller falls back to generic question)")
    func returnsNilForEmptyPool() {
        var rng = SeededGenerator(seed: 3)
        #expect(LootBoxQuizService.makeQuestion(from: [], rng: &rng) == nil)
    }

    @Test("Returns nil for a single-card pool (no distinct distractor possible)")
    func returnsNilForSingleCard() {
        var rng = SeededGenerator(seed: 3)
        let cards = [makeCard(front: "水", back: "water")]
        #expect(LootBoxQuizService.makeQuestion(from: cards, rng: &rng) == nil)
    }

    @Test("Returns nil when every card shares the same answer")
    func returnsNilWhenNoDistinctAnswerExists() {
        var rng = SeededGenerator(seed: 3)
        let cards = [
            makeCard(front: "水", back: "water"),
            makeCard(front: "みず", back: "water"),
        ]
        #expect(LootBoxQuizService.makeQuestion(from: cards, rng: &rng) == nil)
    }

    @Test("Deterministic given the same seeded RNG")
    func deterministicGivenSameSeed() {
        let cards = [
            makeCard(front: "水", back: "water"),
            makeCard(front: "火", back: "fire"),
            makeCard(front: "木", back: "tree"),
            makeCard(front: "金", back: "gold"),
        ]
        var rngA = SeededGenerator(seed: 99)
        var rngB = SeededGenerator(seed: 99)

        let questionA = LootBoxQuizService.makeQuestion(from: cards, rng: &rngA)
        let questionB = LootBoxQuizService.makeQuestion(from: cards, rng: &rngB)

        #expect(questionA == questionB)
    }

    // MARK: - Helpers

    private func makeCard(front: String, back: String) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: back,
            type: .vocabulary,
            fsrsState: FSRSState(),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false
        )
    }
}

/// Simple seeded RNG for deterministic test runs (xorshift64*).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
