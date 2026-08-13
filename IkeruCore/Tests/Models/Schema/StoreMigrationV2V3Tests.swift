import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - V2 → V3 migration
//
// Runs in its OWN CI step / own `swift test` process — same containment
// requirement as `LegacyStoreMigrationTests` (V1→V2) in
// `ExerciseOutcomeLogTests.swift`: opening a versioned-schema container with
// frozen nested types, then reopening the SAME on-disk store with the live
// top-level types, poisons SwiftData's process-global entity↔class cache. A
// later fetch of one of the affected types (`UserProfile`, `Card`,
// `ReviewLog`, `RPGState`) anywhere else in the same process can then
// materialize the wrong class ("Failed to cast model ... to X"). Process
// isolation — not `.serialized`, not `--no-parallel` alone — is the only
// reliable containment; see the V1→V2 suite's own note for the same story.
//
// The suite name deliberately avoids the "LegacyStoreMigration" substring:
// that name is a separate CI filter step (`--filter "LegacyStoreMigration"`)
// that already runs the V1→V2 suite in its own process. Sharing that process
// with THIS suite would reintroduce the exact poisoning both suites exist to
// avoid — each store-opening migration suite needs its own process. See the
// handoff notes for the new CI step this requires (ci.yml is out of this
// change's file perimeter).
@Suite("StoreMigrationV2V3", .serialized)
struct StoreMigrationV2V3Tests {

    @Test("Existing V2 ReviewLog rows survive the lightweight V2→V3 stage; new fields backfill to nil")
    func v2ToV3AdditiveMigration() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-v2v3-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        // 1. Create a genuine V2-versioned store: a plain
        //    `Schema(versionedSchema: IkeruSchemaV2.self)` container with NO
        //    migration plan attached, mirroring how the app's real V2 stores
        //    were created before this change. Insert data using the FROZEN
        //    V2 model types (`IkeruSchemaV2.UserProfile`, `.Card`, `.RPGState`,
        //    `.ReviewLog`) — not the live top-level types, which now describe
        //    V3's shape. See IkeruSchema.swift.
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV2.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            let profile = IkeruSchemaV2.UserProfile(displayName: "Migrator")
            let rpg = try #require(profile.rpgState)
            rpg.xp = 900
            rpg.activeDaysCount = 5
            ctx.insert(profile)

            let card = IkeruSchemaV2.Card(front: "シ", back: "shi", type: .vocabulary, dueDate: Date())
            card.profile = profile
            ctx.insert(card)

            let existingLog = IkeruSchemaV2.ReviewLog(
                card: card,
                grade: .again,
                responseTimeMs: 2_500,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000)
            )
            ctx.insert(existingLog)

            try ctx.save()
        }

        // 2. Reopen with the V3 schema + migration plan → both lightweight
        //    stages run (V1→V2 is a no-op here since the store is already
        //    V2-shaped; V2→V3 adds the three new nullable columns).
        let schemaV3 = Schema(versionedSchema: IkeruSchemaV3.self)
        let configV3 = ModelConfiguration(schema: schemaV3, url: url)
        let containerV3 = try ModelContainer(
            for: schemaV3,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV3]
        )
        let ctx = ModelContext(containerV3)

        // V2 data survived intact, now readable through the LIVE (V3) types.
        #expect(try ctx.fetch(FetchDescriptor<UserProfile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<Card>()).count == 1)

        let logs = try ctx.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        let migratedLog = try #require(logs.first)
        // Pre-existing values survived the migration untouched...
        #expect(migratedLog.grade == .again)
        #expect(migratedLog.responseTimeMs == 2_500)
        // ...and the new V3-only columns backfill to nil for rows that
        // predate them — never a fabricated default.
        #expect(migratedLog.answeredValue == nil)
        #expect(migratedLog.exerciseType == nil)
        #expect(migratedLog.surface == nil)

        let rpgStates = try ctx.fetch(FetchDescriptor<RPGState>())
        #expect(rpgStates.first?.xp == 900)
        #expect(rpgStates.first?.activeDaysCount == 5)

        // The new columns are usable going forward in the migrated store.
        let card = try #require(try ctx.fetch(FetchDescriptor<Card>()).first)
        let newLog = ReviewLog(
            card: card,
            grade: .good,
            responseTimeMs: 900,
            answeredValue: "ツ",
            exerciseType: "kana.quiz",
            surface: "iphone.drill"
        )
        ctx.insert(newLog)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<ReviewLog>()).count == 2)
    }
}
