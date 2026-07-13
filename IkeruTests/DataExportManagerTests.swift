import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Coverage for remediation 7.7 — the data export must actually write
/// `reviews.json` (it previously only promised it in the bundle docs) and hand
/// the share sheet a single `.zip` archive rather than a bare directory.
// Serialized: every test mutates the process-global active-profile id
// (ActiveProfileResolver, backed by shared UserDefaults). Running them in
// parallel lets one test clobber another's active id mid-export, which can
// send fetchActiveProfile to its oldest-profile fallback and surface the wrong
// profile's data — a test artifact, not a production condition (where the
// active id is stable and profiles have distinct timestamps).
@Suite("Data Export — reviews.json + zip", .serialized)
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

    @Test("reviews.json is scoped to the active profile — no cross-profile leak")
    func reviewsJSONScopedToActiveProfile() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Two profiles, each with one card and one review log.
        let profileA = UserProfile(displayName: "A")
        let profileB = UserProfile(displayName: "B")
        context.insert(profileA)
        context.insert(profileB)

        let cardA = Card(front: "甲", back: "A", type: .kanji, dueDate: Date())
        cardA.profile = profileA
        context.insert(cardA)
        context.insert(ReviewLog(
            card: cardA, grade: .good, responseTimeMs: 100,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let cardB = Card(front: "乙", back: "B", type: .kanji, dueDate: Date())
        cardB.profile = profileB
        context.insert(cardB)
        context.insert(ReviewLog(
            card: cardB, grade: .again, responseTimeMs: 200,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500)
        ))
        try context.save()

        // Active profile = A. The export must contain ONLY A's review log —
        // profile B's history must never leak into a shared archive.
        ActiveProfileResolver.setActiveProfileID(profileA.id)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try decoder().decode(
            [DecodedReview].self,
            from: Data(contentsOf: dir.appending(path: "reviews.json"))
        )
        #expect(rows.count == 1)
        #expect(rows.first?.cardId == cardA.id)
        #expect(rows.allSatisfy { $0.cardId != cardB.id })
    }

    // MARK: - rpg.json is scoped to the active profile

    private struct DecodedRPG: Codable {
        let xp: Int
        let level: Int
        let totalReviewsCompleted: Int
    }

    @Test("rpg.json is scoped to the active profile — no cross-profile leak")
    func rpgJSONScopedToActiveProfile() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Two profiles, each with their own distinct RPG state.
        let profileA = UserProfile(displayName: "A")
        let profileB = UserProfile(displayName: "B")
        context.insert(profileA)
        context.insert(profileB)

        let rpgA = RPGState(xp: 500, level: 5, totalReviewsCompleted: 42)
        rpgA.profile = profileA
        profileA.rpgState = rpgA
        context.insert(rpgA)

        let rpgB = RPGState(xp: 9_000, level: 42, totalReviewsCompleted: 999)
        rpgB.profile = profileB
        profileB.rpgState = rpgB
        context.insert(rpgB)

        try context.save()

        // Active profile = B, the SECOND-inserted profile. This deliberately
        // differs from insertion order: the old unscoped code took
        // `fetch(FetchDescriptor<RPGState>()).first`, which returns rpgA
        // (insertion-first) — so this test FAILS against the old bug and only
        // passes when the export truly reads the ACTIVE profile's state.
        ActiveProfileResolver.setActiveProfileID(profileB.id)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rpgURL = dir.appending(path: "rpg.json")
        #expect(FileManager.default.fileExists(atPath: rpgURL.path))

        let decoded = try decoder().decode(DecodedRPG.self, from: Data(contentsOf: rpgURL))
        #expect(decoded.xp == 9_000)
        #expect(decoded.level == 42)
        #expect(decoded.totalReviewsCompleted == 999)
        #expect(decoded.xp != rpgA.xp)
        #expect(decoded.level != rpgA.level)
    }

    // NOTE: an "rpg.json omitted when the active profile has no RPGState" case
    // is intentionally NOT tested — `UserProfile.init` always creates a default
    // `RPGState` (UserProfile.swift:43), so a normally-created profile always
    // has one. The omit branch only covers legacy profiles that predate the
    // RPGState relationship, which cannot be constructed through the public API.

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
