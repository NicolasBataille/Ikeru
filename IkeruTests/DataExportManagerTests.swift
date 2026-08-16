import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// Coverage for remediation 7.7 — the data export must actually write
// `reviews.json` (it previously only promised it in the bundle docs) and hand
// the share sheet a single `.zip` archive rather than a bare directory.
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
        let answeredValue: String?
        let exerciseType: String?
        let surface: String?
    }

    private struct DecodedConfusion: Codable {
        let expected: String
        let answered: String
        let count: Int
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, Card.self, ReviewLog.self, RPGState.self, ExerciseOutcomeLog.self,
        ])
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

        // Mutate the state each profile ALREADY owns (`UserProfile.init`
        // mints one) rather than attaching a rival. Attaching a rival via the
        // owning side (`rpgA.profile = profileA`) traps the whole test runner
        // once the profile has been saved — see the GAP-10 regression test in
        // `HomeViewModelTests` for the measurement. This suite only stayed
        // green because it never saved between the insert and the assignment;
        // that is ordering luck, not safety, and it also left an orphaned
        // RPGState per profile in the store the export then had to ignore.
        let rpgA = try #require(profileA.rpgState)
        rpgA.xp = 500
        rpgA.level = 5
        rpgA.totalReviewsCompleted = 42

        let rpgB = try #require(profileB.rpgState)
        rpgB.xp = 9_000
        rpgB.level = 42
        rpgB.totalReviewsCompleted = 999

        // `totalReviewsCompleted` in the export is GAP-13's ReviewLog-derived
        // count (`CardRepository.activeProfileReviewCount()`), not a mirror of
        // `RPGState.totalReviewsCompleted` — the two intentionally diverge (see
        // that field's doc comment). So the fixture needs real `ReviewLog` rows
        // per profile, distinct in count from each other AND from each
        // profile's `RPGState` counter (42 / 999), so this test still fails
        // against both the old cross-profile leak (would read A's 3 rows or
        // A's rpgA.totalReviewsCompleted) and a regression back to reading
        // `RPGState.totalReviewsCompleted` directly (would read 999, not 5).
        let cardA = Card(front: "甲", back: "A", type: .kanji, dueDate: Date())
        cardA.profile = profileA
        context.insert(cardA)
        for _ in 0..<3 {
            context.insert(ReviewLog(card: cardA, grade: .good, responseTimeMs: 100))
        }

        let cardB = Card(front: "乙", back: "B", type: .kanji, dueDate: Date())
        cardB.profile = profileB
        context.insert(cardB)
        for _ in 0..<5 {
            context.insert(ReviewLog(card: cardB, grade: .good, responseTimeMs: 100))
        }

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
        #expect(decoded.totalReviewsCompleted == 5)
        #expect(decoded.xp != rpgA.xp)
        #expect(decoded.level != rpgA.level)
    }

    // NOTE: an "rpg.json omitted when the active profile has no RPGState" case
    // is intentionally NOT tested — `UserProfile.init` always creates a default
    // `RPGState` (UserProfile.swift:43), so a normally-created profile always
    // has one. The omit branch only covers legacy profiles that predate the
    // RPGState relationship, which cannot be constructed through the public API.

    // MARK: - outcomes.json (ITEM A — ExerciseOutcomeLog export)

    private struct DecodedOutcome: Codable {
        let id: UUID
        let timestamp: Date
        let skill: String
        let accuracy: Double
    }

    @Test("outcomes.json round-trips the recorded exercise outcomes")
    func outcomesJSONRoundTrip() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container)
        let context = container.mainContext

        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_600)
        context.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 1.0, profileID: profile.id, timestamp: t1))
        context.insert(ExerciseOutcomeLog(skill: .speaking, accuracy: 0.8, profileID: profile.id, timestamp: t2))
        try context.save()

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcomesURL = dir.appending(path: "outcomes.json")
        #expect(FileManager.default.fileExists(atPath: outcomesURL.path))

        let data = try Data(contentsOf: outcomesURL)
        let rows = try decoder().decode([DecodedOutcome].self, from: data)
        #expect(rows.count == 2)

        let bySkill = Dictionary(grouping: rows, by: { $0.skill })
        let listening = try #require(bySkill["listening"]?.first)
        let speaking = try #require(bySkill["speaking"]?.first)

        #expect(listening.accuracy == 1.0)
        #expect(listening.timestamp == t1)
        #expect(speaking.accuracy == 0.8)
        #expect(speaking.timestamp == t2)
    }

    @Test("outcomes.json is a valid empty array when there is no outcome history")
    func outcomesJSONEmpty() async throws {
        let container = try makeContainer()
        _ = try seedProfile(container)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcomesURL = dir.appending(path: "outcomes.json")
        #expect(FileManager.default.fileExists(atPath: outcomesURL.path))

        let rows = try decoder().decode([DecodedOutcome].self, from: Data(contentsOf: outcomesURL))
        #expect(rows.isEmpty)
    }

    @Test("outcomes.json is scoped to the active profile — no cross-profile leak")
    func outcomesJSONScopedToActiveProfile() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let profileA = UserProfile(displayName: "A")
        let profileB = UserProfile(displayName: "B")
        context.insert(profileA)
        context.insert(profileB)

        context.insert(ExerciseOutcomeLog(
            skill: .listening, accuracy: 1.0, profileID: profileA.id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        context.insert(ExerciseOutcomeLog(
            skill: .listening, accuracy: 0.0, profileID: profileB.id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500)
        ))
        try context.save()

        // Active profile = A. The export must contain ONLY A's outcome —
        // profile B's history must never leak into a shared archive.
        ActiveProfileResolver.setActiveProfileID(profileA.id)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try decoder().decode(
            [DecodedOutcome].self,
            from: Data(contentsOf: dir.appending(path: "outcomes.json"))
        )
        #expect(rows.count == 1)
        #expect(rows.first?.accuracy == 1.0)
    }

    // MARK: - Telemetry fields (learner-telemetry lot 1 export — chantier #44)

    @Test("reviews.json carries answeredValue/exerciseType/surface for a quiz-style log, nil for a flashcard")
    func reviewsJSONCarriesTelemetryFields() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container)
        let context = container.mainContext

        let card = Card(front: "シ", back: "shi", type: .kanji, dueDate: Date())
        card.profile = profile
        context.insert(card)

        // Quiz-style log: the learner was shown シ and answered ツ.
        context.insert(ReviewLog(
            card: card, grade: .again, responseTimeMs: 800,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            answeredValue: "ツ", exerciseType: "kana.quiz", surface: "iphone.drill"
        ))
        // Self-graded flashcard log: nothing was chosen, so the 3 telemetry
        // fields stay at their `nil` default.
        context.insert(ReviewLog(
            card: card, grade: .good, responseTimeMs: 900,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100)
        ))
        try context.save()

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try decoder().decode(
            [DecodedReview].self,
            from: Data(contentsOf: dir.appending(path: "reviews.json"))
        )
        #expect(rows.count == 2)

        let quizRow = try #require(rows.first { $0.answeredValue != nil })
        #expect(quizRow.answeredValue == "ツ")
        #expect(quizRow.exerciseType == "kana.quiz")
        #expect(quizRow.surface == "iphone.drill")

        let flashcardRow = try #require(rows.first { $0.answeredValue == nil })
        #expect(flashcardRow.exerciseType == nil)
        #expect(flashcardRow.surface == nil)
    }

    // MARK: - confusions.json (derived aggregate)

    @Test("confusions.json aggregates repeated (expected, answered) pairs and excludes correct answers")
    func confusionsJSONAggregatesRepeatedPairs() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container)
        let context = container.mainContext

        let shi = Card(front: "シ", back: "shi", type: .kanji, dueDate: Date())
        shi.profile = profile
        context.insert(shi)

        let so = Card(front: "ソ", back: "so", type: .kanji, dueDate: Date())
        so.profile = profile
        context.insert(so)

        // シ confused with ツ, twice — the classic shi/tsu stroke-shape pair.
        context.insert(ReviewLog(
            card: shi, grade: .again, responseTimeMs: 700,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            answeredValue: "ツ", exerciseType: "kana.quiz", surface: "iphone.drill"
        ))
        context.insert(ReviewLog(
            card: shi, grade: .again, responseTimeMs: 750,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            answeredValue: "ツ", exerciseType: "kana.quiz", surface: "iphone.drill"
        ))
        // ソ confused with ン, once.
        context.insert(ReviewLog(
            card: so, grade: .again, responseTimeMs: 720,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200),
            answeredValue: "ン", exerciseType: "kana.quiz", surface: "iphone.drill"
        ))
        // A correct answer (expected == answered) — must NOT surface as a
        // confusion pair.
        context.insert(ReviewLog(
            card: shi, grade: .good, responseTimeMs: 500,
            timestamp: Date(timeIntervalSince1970: 1_700_000_300),
            answeredValue: "シ", exerciseType: "kana.quiz", surface: "iphone.drill"
        ))
        try context.save()

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let confusionsURL = dir.appending(path: "confusions.json")
        #expect(FileManager.default.fileExists(atPath: confusionsURL.path))

        let rows = try decoder().decode([DecodedConfusion].self, from: Data(contentsOf: confusionsURL))
        #expect(rows.count == 2)

        let shiTsu = try #require(rows.first { $0.expected == "シ" })
        #expect(shiTsu.answered == "ツ")
        #expect(shiTsu.count == 2)

        let soN = try #require(rows.first { $0.expected == "ソ" })
        #expect(soN.answered == "ン")
        #expect(soN.count == 1)

        // Sorted count-descending — the 2x pair must lead.
        #expect(rows.first?.expected == "シ")
    }

    @Test("confusions.json is a valid empty array when there is no confusable history")
    func confusionsJSONEmpty() async throws {
        let container = try makeContainer()
        _ = try seedProfile(container)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let confusionsURL = dir.appending(path: "confusions.json")
        #expect(FileManager.default.fileExists(atPath: confusionsURL.path))

        let rows = try decoder().decode([DecodedConfusion].self, from: Data(contentsOf: confusionsURL))
        #expect(rows.isEmpty)
    }

    // MARK: - context.json documents the new fields (self-describing package)

    @Test("context.json parses as valid JSON and documents grade_semantics + the new review/confusion fields")
    func contextJSONDocumentsTelemetryFields() async throws {
        let container = try makeContainer()
        _ = try seedProfile(container)

        let dir = try await DataExportManager().buildExportDirectory(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: dir) }

        let data = try Data(contentsOf: dir.appending(path: "context.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let gradeSemantics = try #require(json["grade_semantics"] as? [String: Any])
        let hard = try #require(gradeSemantics["2"] as? [String: Any])
        #expect((hard["label"] as? String) == "hard")

        let files = try #require(json["files"] as? [String: Any])
        let reviewsFields = try #require((files["reviews.json"] as? [String: Any])?["fields"] as? [String: Any])
        #expect(reviewsFields["answeredValue"] != nil)
        #expect(reviewsFields["exerciseType"] != nil)
        #expect(reviewsFields["surface"] != nil)

        let confusionsFields = try #require((files["confusions.json"] as? [String: Any])?["fields"] as? [String: Any])
        #expect(confusionsFields["expected"] != nil)
        #expect(confusionsFields["answered"] != nil)
        #expect(confusionsFields["count"] != nil)
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
