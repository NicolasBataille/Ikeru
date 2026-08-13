import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - V3 → V4 migration (cloud-sync lot 0)
//
// Runs in its OWN CI step / own `swift test` process — same containment
// requirement as `StoreMigrationV2V3Tests` and `LegacyStoreMigrationTests`:
// opening a versioned-schema container with frozen nested types, then
// reopening the SAME on-disk store with the live top-level types, poisons
// SwiftData's process-global entity↔class cache. A later fetch of one of the
// affected types anywhere else in the same process can then materialize the
// wrong class ("Failed to cast model ... to X"). Process isolation — not
// `.serialized`, not `--no-parallel` alone — is the only reliable
// containment; see `StoreMigrationV2V3Tests`'s header for the same story.
//
// Suite name deliberately distinct from "StoreMigrationV2V3",
// "LegacyStoreMigration", "IkeruSchema", and "ExerciseOutcome" — those are
// existing CI `--filter` substrings; sharing one would run this suite in the
// wrong process and reintroduce the exact poisoning above. This suite needs
// its OWN new CI step (`swift test --no-parallel --filter
// "StoreMigrationV3V4"`) — adding it is out of this lot's file perimeter
// (ci.yml); flagged in the handoff notes.
@Suite("StoreMigrationV3V4", .serialized)
struct StoreMigrationV3V4Tests {

    // The body is one long arrange-migrate-assert sequence on purpose: it opens
    // a real store at V3, closes it, reopens it at V4, and checks every entity
    // that gained the sync columns. Splitting it into helpers would move the
    // store's lifetime out of the test and reintroduce exactly the cross-suite
    // container leakage this suite is isolated to avoid.
    @Test("Existing V3 rows survive the lightweight V3→V4 stage; the 3 sync columns backfill per their documented defaults")
    // swiftlint:disable:next function_body_length
    func v3ToV4AdditiveMigration() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-v3v4-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        // 1. Create a genuine V3-versioned store: a plain
        //    `Schema(versionedSchema: IkeruSchemaV3.self)` container with NO
        //    migration plan attached, mirroring how the app's real V3 stores
        //    were created before this change. Insert data using the FROZEN
        //    V3 model types (`IkeruSchemaV3.UserProfile`, `.Card`,
        //    `.RPGState`, `.ReviewLog`, `.VocabularyEntry`,
        //    `.VocabularyEncounter`) — not the live top-level types, which
        //    now describe V4's shape. See IkeruSchema.swift.
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV3.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            let profile = IkeruSchemaV3.UserProfile(displayName: "Migrator")
            let rpg = try #require(profile.rpgState)
            rpg.xp = 1_200
            rpg.activeDaysCount = 8
            ctx.insert(profile)

            let card = IkeruSchemaV3.Card(front: "六", back: "six", type: .kanji, dueDate: Date())
            card.profile = profile
            ctx.insert(card)

            let existingLog = IkeruSchemaV3.ReviewLog(
                card: card,
                grade: .hard,
                responseTimeMs: 3_100,
                timestamp: Date(timeIntervalSince1970: 1_850_000_000),
                answeredValue: "四",
                exerciseType: "kanjiStudy",
                surface: "iphone.session"
            )
            ctx.insert(existingLog)

            let vocab = IkeruSchemaV3.VocabularyEntry(word: "六つ", reading: "むっつ", meaning: "six (things)")
            ctx.insert(vocab)
            let encounter = IkeruSchemaV3.VocabularyEncounter(
                source: .sakuraChat,
                contextSnippet: "六つあります。",
                entry: vocab
            )
            ctx.insert(encounter)

            try ctx.save()
        }

        // 2. Reopen with the CURRENT (V4) schema + migration plan → the
        //    lightweight V3→V4 stage runs, adding the three cloud-sync
        //    columns to the 8 synchronized entities.
        let schemaV4 = Schema(versionedSchema: IkeruSchemaV4.self)
        let configV4 = ModelConfiguration(schema: schemaV4, url: url)
        let containerV4 = try ModelContainer(
            for: schemaV4,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV4]
        )
        let ctx = ModelContext(containerV4)

        // V3 data survived intact, now readable through the LIVE (V4) types.
        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.displayName == "Migrator")
        // Pre-existing rows backfill `updatedAt` to the documented epoch
        // sentinel (never a fabricated "now"), `deletedAt`/`syncedAt` to nil.
        #expect(profile.updatedAt == Date(timeIntervalSince1970: 0))
        #expect(profile.deletedAt == nil)
        #expect(profile.syncedAt == nil)

        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.updatedAt == Date(timeIntervalSince1970: 0))

        let logs = try ctx.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        let migratedLog = try #require(logs.first)
        // Pre-existing V3 values survived the migration untouched...
        #expect(migratedLog.grade == .hard)
        #expect(migratedLog.responseTimeMs == 3_100)
        #expect(migratedLog.answeredValue == "四")
        #expect(migratedLog.exerciseType == "kanjiStudy")
        #expect(migratedLog.surface == "iphone.session")
        // ...and the new V4-only (cloud-sync) columns backfill per their
        // documented defaults.
        #expect(migratedLog.updatedAt == Date(timeIntervalSince1970: 0))
        #expect(migratedLog.deletedAt == nil)
        #expect(migratedLog.syncedAt == nil)

        let rpgStates = try ctx.fetch(FetchDescriptor<RPGState>())
        #expect(rpgStates.first?.xp == 1_200)
        #expect(rpgStates.first?.activeDaysCount == 8)
        #expect(rpgStates.first?.updatedAt == Date(timeIntervalSince1970: 0))

        // The relationship-pair freeze (VocabularyEntry ↔ VocabularyEncounter)
        // survives too — this is the pair the 2026-08-13 freeze-set expansion
        // exists to protect.
        let vocabEntries = try ctx.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(vocabEntries.count == 1)
        #expect(vocabEntries.first?.word == "六つ")
        #expect(vocabEntries.first?.updatedAt == Date(timeIntervalSince1970: 0))

        let vocabEncounters = try ctx.fetch(FetchDescriptor<VocabularyEncounter>())
        #expect(vocabEncounters.count == 1)
        #expect(vocabEncounters.first?.contextSnippet == "六つあります。")
        #expect(vocabEncounters.first?.entry?.id == vocabEntries.first?.id)
        #expect(vocabEncounters.first?.updatedAt == Date(timeIntervalSince1970: 0))

        // The new columns are usable going forward in the migrated store —
        // a freshly-inserted row gets a real `updatedAt`, not the sentinel.
        let card = try #require(cards.first)
        let newLog = ReviewLog(
            card: card,
            grade: .good,
            responseTimeMs: 800
        )
        ctx.insert(newLog)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<ReviewLog>()).count == 2)
        #expect(newLog.updatedAt != Date(timeIntervalSince1970: 0))
    }
}
