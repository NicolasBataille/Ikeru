import Testing
@testable import IkeruCore
import Foundation

@Suite("SessionSkillContribution")
struct SessionSkillContributionTests {

    @Test("zero starts at all-zero")
    func zero() {
        let z = SessionSkillContribution.zero
        #expect(z.reading == 0)
        #expect(z.writing == 0)
        #expect(z.listening == 0)
        #expect(z.speaking == 0)
    }

    @Test("total returns sum across four winds")
    func total() {
        let c = SessionSkillContribution(reading: 10, writing: 5, listening: 3, speaking: 2)
        #expect(c.total == 20)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = SessionSkillContribution(reading: 1, writing: 2, listening: 3, speaking: 4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSkillContribution.self, from: data)
        #expect(decoded == original)
    }
}
