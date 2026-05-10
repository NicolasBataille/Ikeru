import Testing
@testable import IkeruCore

@Suite("SkillSplit")
struct SkillSplitTests {

    @Test("Stores all four weights")
    func fields() {
        let split = SkillSplit(reading: 0.3, writing: 0.0, listening: 0.7, speaking: 0.0)
        #expect(split.reading == 0.3)
        #expect(split.writing == 0.0)
        #expect(split.listening == 0.7)
        #expect(split.speaking == 0.0)
    }

    @Test("sum() reports total")
    func sum() {
        let split = SkillSplit(reading: 0.3, writing: 0.4, listening: 0.2, speaking: 0.1)
        #expect(abs(split.sum() - 1.0) < 1e-9)
    }
}
