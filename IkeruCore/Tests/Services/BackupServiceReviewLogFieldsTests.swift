import Testing
import Foundation
@testable import IkeruCore

/// Verifies that `ReviewSnapshot` round-trips the three learner-telemetry
/// fields added to `ReviewLog` in `IkeruSchemaV3` (`answeredValue`,
/// `exerciseType`, `surface`) through `Codable`, and stays backward-compatible
/// with backup payloads written before those fields existed.
///
/// This closes the gap where `CloudBackupManager` restored a `ReviewLog`
/// without these fields: latent while `iCloudEnabled == false`, but a silent
/// data loss the day iCloud backup/restore is turned on — a restored user
/// would lose all confusion-pair data with no error surfaced.
@Suite("BackupService.reviewLogFields")
struct BackupServiceReviewLogFieldsTests {

    @Test("ReviewSnapshot round-trips all three fields through JSON")
    func taggedRoundTrip() throws {
        let original = ReviewSnapshot(
            id: UUID(),
            cardId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_799_000_000),
            grade: "3",
            responseTimeMs: 1200,
            answeredValue: "ツ",
            exerciseType: "kana.quiz",
            surface: "iphone.drill"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewSnapshot.self, from: encoded)

        #expect(decoded.answeredValue == "ツ")
        #expect(decoded.exerciseType == "kana.quiz")
        #expect(decoded.surface == "iphone.drill")
    }

    @Test("ReviewSnapshot round-trips nil fields through JSON (self-graded flashcard)")
    func nilRoundTrip() throws {
        let original = ReviewSnapshot(
            id: UUID(),
            cardId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_799_000_000),
            grade: "3",
            responseTimeMs: 1200,
            answeredValue: nil,
            exerciseType: nil,
            surface: nil
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewSnapshot.self, from: encoded)

        #expect(decoded.answeredValue == nil)
        #expect(decoded.exerciseType == nil)
        #expect(decoded.surface == nil)
    }

    @Test("Legacy payload without the three keys decodes with nil (back-compat)")
    func legacyBackCompat() throws {
        // Hand-crafted JSON missing `answeredValue` / `exerciseType` /
        // `surface` — represents a backup file written before IkeruSchemaV3
        // added these fields to ReviewLog. Decoder MUST accept it: a
        // strict decode here would break every backup already in the wild.
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "cardId": "33333333-3333-3333-3333-333333333333",
          "timestamp": 1799000000,
          "grade": "3",
          "responseTimeMs": 1200
        }
        """
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(ReviewSnapshot.self, from: data)

        #expect(decoded.answeredValue == nil)
        #expect(decoded.exerciseType == nil)
        #expect(decoded.surface == nil)
        #expect(decoded.responseTimeMs == 1200)
    }
}
