import Testing
import Foundation
@testable import IkeruCore

@Suite("LeechInterventionService")
struct LeechInterventionServiceTests {

    // MARK: - Intervention Generation

    @Test("Generates intervention with all components for kanji card")
    func kanjiIntervention() {
        let card = makeCard(front: "日", back: "day/sun", type: .kanji)
        let confusion = ConfusionPattern(
            target: "日",
            description: "You may be confusing 日 with 目.",
            type: .visuallySimilar
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        #expect(!intervention.message.isEmpty)
        #expect(!intervention.mnemonic.isEmpty)
        #expect(intervention.quizTag.hasPrefix("[QUIZ:"))
        #expect(intervention.quizTag.hasSuffix("]"))
        #expect(intervention.message.contains("[KANJI:日]"))
        #expect(intervention.message.contains("[QUIZ:"))
    }

    @Test("Generates intervention for vocabulary card without KANJI tag")
    func vocabularyIntervention() {
        let card = makeCard(front: "食べる", back: "to eat", type: .vocabulary)
        let confusion = ConfusionPattern(
            target: "食べる",
            description: "This word keeps slipping.",
            type: .generalDifficulty
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        #expect(!intervention.message.contains("[KANJI:"))
        #expect(intervention.message.contains("[QUIZ:"))
        #expect(intervention.message.contains("食べる"))
    }

    @Test("Quiz tag contains correct answer")
    func quizTagContainsCorrectAnswer() {
        let card = makeCard(front: "日", back: "day/sun", type: .kanji)
        let confusion = ConfusionPattern(
            target: "日",
            description: "Test",
            type: .generalDifficulty
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        // Quiz format: [QUIZ:question|correct|wrong1|wrong2]
        #expect(intervention.quizTag.contains("day/sun"))
    }

    @Test("Mnemonic for visually similar kanji mentions uniqueness")
    func mnemonicForVisuallySimilar() {
        let card = makeCard(front: "日", back: "day/sun", type: .kanji)
        let confusion = ConfusionPattern(
            target: "日",
            description: "Visually similar",
            type: .visuallySimilar
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        #expect(intervention.mnemonic.contains("unique"))
    }

    @Test("Grammar card generates sentence-based mnemonic")
    func grammarMnemonic() {
        let card = makeCard(front: "〜ている", back: "progressive", type: .grammar)
        let confusion = ConfusionPattern(
            target: "〜ている",
            description: "Hard pattern",
            type: .generalDifficulty
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        #expect(intervention.mnemonic.contains("sentence"))
    }

    // MARK: - Helpers

    private func makeCard(
        front: String = "日",
        back: String = "day/sun",
        type: CardType = .kanji,
        lapseCount: Int = 3
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
            leechFlag: false
        )
    }
}
