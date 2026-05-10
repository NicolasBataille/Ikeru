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

    // MARK: - Backwards-compatibility regression
    //
    // Pre-Spec-B sessions awarded 6 XP for any non-.again flashcard grade
    // and 3 XP for .again. Flashcard exercise types (kanaStudy,
    // vocabularyStudy, fillInBlank) at N5 must continue to award the same
    // totals so the existing curve is not perturbed for early users.

    @Test("Vocabulary .good at N5 = 6 (no bonus, no scaling)")
    func vocabN5Good() {
        #expect(ExerciseXP.award(type: .vocabularyStudy, level: .n5, grade: .good) == 6)
    }

    @Test("Vocabulary .again at N5 = 3")
    func vocabN5Again() {
        #expect(ExerciseXP.award(type: .vocabularyStudy, level: .n5, grade: .again) == 3)
    }

    @Test("FillInBlank .good at N5 = 7 (6 + 1 bonus)")
    func fillInBlankN5Good() {
        #expect(ExerciseXP.award(type: .fillInBlank, level: .n5, grade: .good) == 7)
    }

    @Test("Vocabulary .good at N3 = 8 (round(6 × 1.30))")
    func vocabN3Good() {
        #expect(ExerciseXP.award(type: .vocabularyStudy, level: .n3, grade: .good) == 8)
    }

    @Test("Kanji .good at N3 = 10 (round(8 × 1.30))")
    func kanjiN3Good() {
        #expect(ExerciseXP.award(type: .kanjiStudy, level: .n3, grade: .good) == 10)
    }

    @Test("Listening unsubtitled at N4 = 16 (round(14 × 1.15))")
    func listeningUnsubtitledN4() {
        #expect(ExerciseXP.award(type: .listeningUnsubtitled, level: .n4, grade: nil) == 16)
    }

    @Test("Writing practice at N2 = 27 (round(18 × 1.50))")
    func writingPracticeN2() {
        #expect(ExerciseXP.award(type: .writingPractice, level: .n2, grade: nil) == 27)
    }
}
