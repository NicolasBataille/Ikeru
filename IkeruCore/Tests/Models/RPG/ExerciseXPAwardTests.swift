import Testing
@testable import IkeruCore

@Suite("ExerciseXP.award")
struct ExerciseXPAwardTests {

    @Test("Kana .good at N5 = 6 (matches RPGConstants.xpForGrade)")
    func kanaN5Good() {
        #expect(ExerciseXP.award(type: .kanaStudy, level: .n5, grade: .good) == 6)
    }

    @Test("Kana .again at N5 = 3")
    func kanaN5Again() {
        #expect(ExerciseXP.award(type: .kanaStudy, level: .n5, grade: .again) == 3)
    }

    @Test("Kanji .good at N5 = 8 (6 base + 2 bonus)")
    func kanjiN5Good() {
        #expect(ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .good) == 8)
    }

    @Test("Reading passage at N5 = 25")
    func readingN5() {
        #expect(ExerciseXP.award(type: .readingPassage, level: .n5, grade: nil) == 25)
    }

    @Test("Reading passage at N3 = 33 (round(25 × 1.30))")
    func readingN3() {
        #expect(ExerciseXP.award(type: .readingPassage, level: .n3, grade: nil) == 33)
    }

    @Test("Sentence construction at N3 = 16 (round(12 × 1.30))")
    func sentenceN3() {
        #expect(ExerciseXP.award(type: .sentenceConstruction, level: .n3, grade: nil) == 16)
    }

    @Test("Sakura at N1 = 35 (round(20 × 1.75))")
    func sakuraN1() {
        #expect(ExerciseXP.award(type: .sakuraConversation, level: .n1, grade: nil) == 35)
    }
}
