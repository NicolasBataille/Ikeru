import Testing
import Foundation
@testable import IkeruCore

/// Verifies that `CardSnapshot` round-trips the optional `jlptLevel` field
/// through `Codable` and stays backward-compatible with payloads written
/// before the column existed.
@Suite("BackupService.jlptLevel")
struct BackupServiceJLPTLevelTests {

    @Test("CardSnapshot round-trips a tagged level through JSON")
    func taggedRoundTrip() throws {
        let original = CardSnapshot(
            id: UUID(),
            front: "本",
            back: "book",
            type: "vocabulary",
            dueDate: Date(timeIntervalSince1970: 1_799_000_000),
            easeFactor: 2.5,
            interval: 1,
            reps: 0,
            lapseCount: 0,
            leechFlag: false,
            jlptLevel: .n5
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CardSnapshot.self, from: encoded)

        #expect(decoded.jlptLevel == .n5)
        #expect(decoded.front == "本")
    }

    @Test("CardSnapshot round-trips nil jlptLevel through JSON")
    func nilRoundTrip() throws {
        let original = CardSnapshot(
            id: UUID(),
            front: "あ",
            back: "a",
            type: "vocabulary",
            dueDate: Date(timeIntervalSince1970: 1_799_000_000),
            easeFactor: 2.5,
            interval: 1,
            reps: 0,
            lapseCount: 0,
            leechFlag: false,
            jlptLevel: nil
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CardSnapshot.self, from: encoded)

        #expect(decoded.jlptLevel == nil)
    }

    @Test("Legacy payload without jlptLevel key decodes with nil (back-compat)")
    func legacyBackCompat() throws {
        // Hand-crafted JSON missing the `jlptLevel` key — represents a backup
        // file written before this column existed. Decoder MUST accept it.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "front": "古",
          "back": "old",
          "type": "kanji",
          "dueDate": 1799000000,
          "easeFactor": 2.5,
          "interval": 1,
          "reps": 0,
          "lapseCount": 0,
          "leechFlag": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CardSnapshot.self, from: json)

        #expect(decoded.jlptLevel == nil)
        #expect(decoded.front == "古")
        #expect(decoded.type == "kanji")
    }

    @Test("Each JLPT level survives round-trip", arguments: [
        JLPTLevel.n5, .n4, .n3, .n2, .n1
    ])
    func eachLevelRoundTrips(level: JLPTLevel) throws {
        let original = CardSnapshot(
            id: UUID(),
            front: "X",
            back: "y",
            type: "vocabulary",
            dueDate: Date(timeIntervalSince1970: 1_799_000_000),
            easeFactor: 2.5,
            interval: 1,
            reps: 0,
            lapseCount: 0,
            leechFlag: false,
            jlptLevel: level
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CardSnapshot.self, from: encoded)

        #expect(decoded.jlptLevel == level)
    }
}
