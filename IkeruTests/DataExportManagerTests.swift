import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Coverage for remediation 7.7 — the data export must actually write
/// `reviews.json` (it previously only promised it in the bundle docs) and hand
/// the share sheet a single `.zip` archive rather than a bare directory.
@Suite("Data Export — reviews.json + zip")
@MainActor
struct DataExportManagerTests {

    // MARK: - Decode shape (matches DataExportManager.ReviewExportRow JSON keys)

    private struct DecodedReview: Codable {
        let id: UUID
        let cardId: UUID?
        let cardType: String?
        let timestamp: Date
        let grade: Int
        let gradeLabel: String
        let responseTimeMs: Int
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedProfile(_ container: ModelContainer) throws -> UserProfile {
        let context = container.mainContext
        let profile = UserProfile(displayName: "Export Test")
        context.insert(profile)
        try context.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return profile
    }

    // MARK: - reviews.json is written with the right contents

    @Test("reviews.json round-trips the recorded review logs")
    func reviewsJSONRoundTrip() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container)
        let context = container.mainContext

        let card = Card(front: "日", back: "sun", type: .kanji, dueDate: Date())
        card.profile = profile
        context.insert(card)

        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_600)
        context.insert(ReviewLog(card: card, grade: .good, responseTimeMs: 1234, timestamp: t1))
        context.insert(ReviewLog(card: card, grade: .again, responseTimeMs: 4321, timestamp: t2))
        try context.save()

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let reviewsURL = dir.appending(path: "reviews.json")
        #expect(FileManager.default.fileExists(atPath: reviewsURL.path))

        let data = try Data(contentsOf: reviewsURL)
        let rows = try decoder().decode([DecodedReview].self, from: data)

        #expect(rows.count == 2)

        let byGrade = Dictionary(grouping: rows, by: { $0.grade })
        let good = try #require(byGrade[Grade.good.rawValue]?.first)
        let again = try #require(byGrade[Grade.again.rawValue]?.first)

        #expect(good.gradeLabel == "good")
        #expect(good.responseTimeMs == 1234)
        #expect(good.cardId == card.id)
        #expect(good.cardType == CardType.kanji.rawValue)
        #expect(good.timestamp == t1)

        #expect(again.gradeLabel == "again")
        #expect(again.responseTimeMs == 4321)
        #expect(again.timestamp == t2)
    }

    @Test("reviews.json is a valid empty array when there is no history")
    func reviewsJSONEmpty() async throws {
        let container = try makeContainer()
        _ = try seedProfile(container)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let reviewsURL = dir.appending(path: "reviews.json")
        #expect(FileManager.default.fileExists(atPath: reviewsURL.path))

        let rows = try decoder().decode([DecodedReview].self, from: Data(contentsOf: reviewsURL))
        #expect(rows.isEmpty)
    }

    // MARK: - The shared artifact is a single zip, not a directory

    @Test("exportData returns a single non-empty .zip file")
    func exportProducesSingleZip() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container)
        let context = container.mainContext

        let card = Card(front: "水", back: "water", type: .vocabulary, dueDate: Date())
        card.profile = profile
        context.insert(card)
        context.insert(ReviewLog(card: card, grade: .easy, responseTimeMs: 900, timestamp: Date()))
        try context.save()

        let manager = DataExportManager()
        let zipURL = try await manager.exportData(modelContainer: container)
        defer { manager.cleanup(url: zipURL) }

        #expect(zipURL.pathExtension == "zip")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: zipURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(!isDirectory.boolValue)

        let size = (try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int) ?? 0
        #expect(size > 0)

        // The intermediate export directory must not leak alongside the zip.
        let dirURL = zipURL.deletingPathExtension()
        #expect(!FileManager.default.fileExists(atPath: dirURL.path))
    }
}
