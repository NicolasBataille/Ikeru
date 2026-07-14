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

    // MARK: - Content-Aware Distractors (4.6)

    @Test("Kanji distractors are drawn from the same-JLPT-level content bundle")
    func kanjiDistractorsUseSameLevelBundle() {
        let card = makeCard(front: "水", back: "water", type: .kanji, jlptLevel: .n5)
        let confusion = ConfusionPattern(target: "水", description: "Test", type: .generalDifficulty)
        let context = LeechContentContext(
            sameLevelKanji: [
                makeKanji(character: "水", meaning: "water", level: .n5),
                makeKanji(character: "火", meaning: "fire", level: .n5),
                makeKanji(character: "木", meaning: "tree", level: .n5),
                makeKanji(character: "金", meaning: "gold", level: .n5),
            ]
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion,
            contentContext: context
        )

        let distractors = parseDistractors(from: intervention.quizTag)
        #expect(distractors.count == 2)
        // Never repeats the correct answer.
        #expect(!distractors.contains { $0.lowercased() == "water" })
        // Both distractors come from the same-level bundle, not the legacy filler.
        let bundleMeanings: Set<String> = ["fire", "tree", "gold"]
        for distractor in distractors {
            #expect(bundleMeanings.contains(distractor.lowercased()))
        }
    }

    @Test("Kanji distractors pad from the adjacent level when same level is too small")
    func kanjiDistractorsPadFromAdjacentLevel() {
        let card = makeCard(front: "水", back: "water", type: .kanji, jlptLevel: .n4)
        let confusion = ConfusionPattern(target: "水", description: "Test", type: .generalDifficulty)
        let context = LeechContentContext(
            sameLevelKanji: [makeKanji(character: "水", meaning: "water", level: .n4)],
            adjacentLevelKanji: [
                makeKanji(character: "火", meaning: "fire", level: .n5),
                makeKanji(character: "木", meaning: "tree", level: .n5),
            ]
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion,
            contentContext: context
        )

        let distractors = parseDistractors(from: intervention.quizTag)
        #expect(distractors.count == 2)
        #expect(!distractors.contains { $0.lowercased() == "water" })
        let paddedMeanings: Set<String> = ["fire", "tree"]
        for distractor in distractors {
            #expect(paddedMeanings.contains(distractor.lowercased()))
        }
    }

    @Test("Kanji distractors never crash and never repeat the correct answer with an empty bundle")
    func kanjiDistractorsFallBackGracefullyWhenBundleEmpty() {
        let card = makeCard(front: "日", back: "day/sun", type: .kanji, jlptLevel: .n5)
        let confusion = ConfusionPattern(target: "日", description: "Test", type: .generalDifficulty)

        // No contentContext passed — defaults to `.empty`.
        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        let distractors = parseDistractors(from: intervention.quizTag)
        #expect(distractors.count == 2)
        #expect(distractors[0] != distractors[1])
        #expect(!distractors.contains { $0.lowercased() == "day/sun" })
    }

    @Test("Vocabulary distractors are drawn from the same-JLPT-level bundle")
    func vocabularyDistractorsUseSameLevelBundle() {
        let card = makeCard(front: "食べる", back: "to eat", type: .vocabulary, jlptLevel: .n5)
        let confusion = ConfusionPattern(target: "食べる", description: "Test", type: .generalDifficulty)
        let context = LeechContentContext(
            sameLevelVocabulary: [
                makeVocabulary(word: "食べる", meaning: "to eat", level: .n5),
                makeVocabulary(word: "飲む", meaning: "to drink", level: .n5),
                makeVocabulary(word: "見る", meaning: "to see", level: .n5),
            ]
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion,
            contentContext: context
        )

        let distractors = parseDistractors(from: intervention.quizTag)
        #expect(distractors.count == 2)
        #expect(!distractors.contains { $0.lowercased() == "to eat" })
        let bundleMeanings: Set<String> = ["to drink", "to see"]
        for distractor in distractors {
            #expect(bundleMeanings.contains(distractor.lowercased()))
        }
    }

    @Test("Grammar distractors are drawn from the same-JLPT-level bundle")
    func grammarDistractorsUseSameLevelBundle() {
        let card = makeCard(front: "〜ている", back: "progressive", type: .grammar, jlptLevel: .n4)
        let confusion = ConfusionPattern(target: "〜ている", description: "Test", type: .generalDifficulty)
        let context = LeechContentContext(
            sameLevelGrammar: [
                makeGrammarPoint(id: 1, title: "progressive", level: .n4),
                makeGrammarPoint(id: 2, title: "conditional", level: .n4),
                makeGrammarPoint(id: 3, title: "causative", level: .n4),
            ]
        )

        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion,
            contentContext: context
        )

        let distractors = parseDistractors(from: intervention.quizTag)
        #expect(distractors.count == 2)
        #expect(!distractors.contains { $0.lowercased() == "progressive" })
        let bundleTitles: Set<String> = ["conditional", "causative"]
        for distractor in distractors {
            #expect(bundleTitles.contains(distractor.lowercased()))
        }
    }

    @Test("Distractor sampling is deterministic for the same inputs")
    func sampleDistractorsIsDeterministic() {
        let pool = ["fire", "tree", "gold", "earth", "warrior"]
        let first = LeechInterventionService.sampleDistractors(
            correctAnswer: "water",
            sameLevel: pool,
            adjacentLevel: [],
            fallback: ["not this meaning", "something else"],
            seedKey: "水|water"
        )
        let second = LeechInterventionService.sampleDistractors(
            correctAnswer: "water",
            sameLevel: pool,
            adjacentLevel: [],
            fallback: ["not this meaning", "something else"],
            seedKey: "水|water"
        )

        #expect(first.0 == second.0)
        #expect(first.1 == second.1)
        #expect(first.0 != first.1)
    }

    @Test("Distractor sampling never selects the correct answer even with a tiny pool")
    func sampleDistractorsNeverRepeatsCorrectAnswer() {
        let result = LeechInterventionService.sampleDistractors(
            correctAnswer: "water",
            sameLevel: ["water"],
            adjacentLevel: ["Water", " water "],
            fallback: ["not this meaning", "something else"],
            seedKey: "seed"
        )

        #expect(result.0.lowercased() != "water")
        #expect(result.1.lowercased() != "water")
        #expect(result.0 != result.1)
    }

    @Test("Distractor sampling falls back to generic pools when bundle pools are empty")
    func sampleDistractorsFallsBackWhenBundleEmpty() {
        let result = LeechInterventionService.sampleDistractors(
            correctAnswer: "water",
            sameLevel: [],
            adjacentLevel: [],
            fallback: ["not this meaning", "something else"],
            seedKey: "seed"
        )

        #expect(result.0 != result.1)
        #expect(Set(["not this meaning", "something else"]).contains(result.0))
        #expect(Set(["not this meaning", "something else"]).contains(result.1))
    }

    @Test("adjacentLevel(to:) maps every level to a valid neighbor without crashing")
    func adjacentLevelCoversAllCases() {
        for level in JLPTLevel.allCases {
            let adjacent = LeechInterventionService.adjacentLevel(to: level)
            #expect(adjacent != level)
        }
    }

    // MARK: - Helpers

    private func makeCard(
        front: String = "日",
        back: String = "day/sun",
        type: CardType = .kanji,
        lapseCount: Int = 3,
        jlptLevel: JLPTLevel? = nil
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
            leechFlag: false,
            jlptLevel: jlptLevel
        )
    }

    private func makeKanji(character: String, meaning: String, level: JLPTLevel) -> Kanji {
        Kanji(
            character: character,
            radicals: [],
            onReadings: [],
            kunReadings: [],
            meanings: [meaning],
            jlptLevel: level,
            strokeCount: 1,
            strokeOrderSVGRef: nil
        )
    }

    private func makeVocabulary(word: String, meaning: String, level: JLPTLevel) -> Vocabulary {
        Vocabulary(
            id: word.hashValue,
            word: word,
            reading: word,
            meaning: meaning,
            kanjiCharacter: nil,
            jlptLevel: level,
            exampleSentences: []
        )
    }

    private func makeGrammarPoint(id: Int, title: String, level: JLPTLevel) -> GrammarPoint {
        GrammarPoint(
            id: id,
            jlptLevel: level,
            title: title,
            explanation: "",
            examples: []
        )
    }

    /// Parses the two distractors out of a `[QUIZ:question|correct|wrong1|wrong2]` tag.
    private func parseDistractors(from quizTag: String) -> [String] {
        let stripped = quizTag
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .replacingOccurrences(of: "QUIZ:", with: "")
        let parts = stripped.components(separatedBy: "|")
        guard parts.count == 4 else { return [] }
        return [parts[2], parts[3]]
    }
}
