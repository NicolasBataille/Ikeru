import Testing
@testable import IkeruCore

@Suite("KanaData")
struct KanaDataTests {

    @Test("Hiragana contains 46 entries")
    func hiraganaCount() {
        #expect(KanaData.hiragana.count == 46)
    }

    @Test("Katakana contains 46 entries")
    func katakanaCount() {
        #expect(KanaData.katakana.count == 46)
    }

    @Test("All kana have unique IDs")
    func uniqueIDs() {
        let allIDs = KanaData.all.map(\.id)
        let uniqueIDs = Set(allIDs)
        #expect(allIDs.count == uniqueIDs.count)
    }

    @Test("Quiz question generates 4 choices including target")
    func quizQuestion() {
        let question = KanaData.generateQuizQuestion(from: KanaData.hiragana)
        #expect(question != nil)
        #expect(question!.choices.count == 4)
        #expect(question!.choices.contains(where: { $0.id == question!.target.id }))
    }

    @Test("Quiz question distractors are different from target")
    func quizDistractors() {
        let question = KanaData.generateQuizQuestion(from: KanaData.hiragana)!
        let distractors = question.choices.filter { $0.id != question.target.id }
        #expect(distractors.count == 3)
    }

    @Test("Quiz returns nil with insufficient pool")
    func quizInsufficientPool() {
        let smallPool = Array(KanaData.hiragana.prefix(3))
        let question = KanaData.generateQuizQuestion(from: smallPool)
        #expect(question == nil)
    }
}
