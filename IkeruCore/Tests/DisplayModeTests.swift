import Testing
import Foundation
@testable import IkeruCore

@Suite("DisplayMode")
struct DisplayModeTests {

    @Test("Has exactly two cases, beginner is the default for fresh state")
    func twoCases() {
        let all = DisplayMode.allCases
        #expect(all.count == 2)
        #expect(all.contains(.beginner))
        #expect(all.contains(.tatami))
    }

    @Test("Codable round-trips both cases")
    func codableRoundTrip() throws {
        for mode in DisplayMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("Raw values match storage contract")
    func rawValues() {
        #expect(DisplayMode.beginner.rawValue == "beginner")
        #expect(DisplayMode.tatami.rawValue == "tatami")
    }
}
