import Testing
@testable import IkeruCore

@Suite("ExerciseXP.rule per-type table")
struct ExerciseXPTableTests {

    @Test("kanaStudy is perGrade with no bonus")
    func kanaIsFlat() {
        #expect(ExerciseXP.rule(for: .kanaStudy, grade: .good) == .perGrade(grade: .good, bonus: 0))
    }

    @Test("kanjiStudy is perGrade with +2 bonus")
    func kanjiBonus() {
        #expect(ExerciseXP.rule(for: .kanjiStudy, grade: .good) == .perGrade(grade: .good, bonus: 2))
    }

    @Test("readingPassage is perCompletion 25")
    func readingPassage() {
        #expect(ExerciseXP.rule(for: .readingPassage, grade: nil) == .perCompletion(base: 25))
    }

    @Test("sakuraConversation is perCompletion 20")
    func sakura() {
        #expect(ExerciseXP.rule(for: .sakuraConversation, grade: nil) == .perCompletion(base: 20))
    }

    @Test("All 12 ExerciseType cases have a rule")
    func everyTypeCovered() {
        for type in ExerciseType.allCases {
            _ = ExerciseXP.rule(for: type, grade: .good)
        }
    }
}
