import Testing
@testable import IkeruCore

@Suite("JLPTReadinessReport")
struct JLPTReadinessReportTests {

    @Test("Stores per-level + bestFit + confidence")
    func fields() {
        let report = JLPTReadinessReport(
            perLevel: [.n5: 0.95, .n4: 0.4, .n3: 0.0, .n2: 0.0, .n1: 0.0],
            bestFit: .n5,
            bestFitConfidence: 0.95
        )
        #expect(report.perLevel[.n5] == 0.95)
        #expect(report.bestFit == .n5)
        #expect(report.bestFitConfidence == 0.95)
    }

    @Test("bestFitThreshold is 0.85")
    func threshold() {
        #expect(JLPTReadinessReport.bestFitThreshold == 0.85)
    }
}
