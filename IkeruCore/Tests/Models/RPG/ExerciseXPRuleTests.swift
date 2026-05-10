import Testing
@testable import IkeruCore

@Suite("ExerciseXPRule")
struct ExerciseXPRuleTests {

    @Test("perGrade carries grade + bonus")
    func perGradeShape() {
        let rule = ExerciseXPRule.perGrade(grade: .good, bonus: 2)
        guard case .perGrade(let g, let bonus) = rule else { Issue.record("not perGrade"); return }
        #expect(g == .good)
        #expect(bonus == 2)
    }

    @Test("perCompletion carries base")
    func perCompletionShape() {
        let rule = ExerciseXPRule.perCompletion(base: 25)
        guard case .perCompletion(let base) = rule else { Issue.record("not perCompletion"); return }
        #expect(base == 25)
    }
}
