import Testing
@testable import IkeruCore

@Suite("ExerciseXP.multiplier")
struct ExerciseXPMultiplierTests {
    @Test("N5 = 1.0")  func n5() { #expect(ExerciseXP.multiplier(for: .n5) == 1.0) }
    @Test("N4 = 1.15") func n4() { #expect(ExerciseXP.multiplier(for: .n4) == 1.15) }
    @Test("N3 = 1.30") func n3() { #expect(ExerciseXP.multiplier(for: .n3) == 1.30) }
    @Test("N2 = 1.50") func n2() { #expect(ExerciseXP.multiplier(for: .n2) == 1.50) }
    @Test("N1 = 1.75") func n1() { #expect(ExerciseXP.multiplier(for: .n1) == 1.75) }

    @Test("Multipliers strictly increase with level")
    func monotonic() {
        let levels: [JLPTLevel] = [.n5, .n4, .n3, .n2, .n1]
        let mults = levels.map(ExerciseXP.multiplier(for:))
        for i in 1..<mults.count { #expect(mults[i] > mults[i - 1]) }
    }
}
