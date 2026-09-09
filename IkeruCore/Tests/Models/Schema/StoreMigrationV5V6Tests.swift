import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - V5 → V6 migration (un propriétaire pour le dictionnaire et les imports)
//
// Runs in its OWN CI step / own `swift test` process — the same containment
// requirement as every other `StoreMigration*` suite, and MORE pressing here:
// V5 nests frozen `VocabularyEntry` / `VocabularyEncounter` / `TextImport`
// snapshots, so this suite opens a container bound to those classes and then
// reopens the SAME store under the live ones. That is the exact poisoning
// mechanism CLAUDE.md quarantines these suites for. Seeding uses
// `IkeruSchemaV5.*`; everything after the migration uses the live types.
//
// Suite name deliberately distinct from every other CI `--filter` / `--skip`
// substring. Wired in `.github/workflows/ci.yml` as its own
// `swift test --no-parallel --filter "StoreMigrationV5V6"` step, plus a
// `--skip "StoreMigrationV5V6"` on the main run.
@Suite("StoreMigrationV5V6", .serialized)
struct StoreMigrationV5V6Tests {

    /// One long arrange-migrate-assert sequence on purpose: the store's
    /// lifetime is the subject of the test.
    @Test("Existing V5 rows survive the lightweight V5→V6 stage with profileID nil, and adoption attributes them")
    // swiftlint:disable:next function_body_length
    func v5ToV6AdditiveMigrationThenAdoption() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-v5v6-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        let entryID = UUID()
        let deletedEntryID = UUID()
        let importID = UUID()
        var profileID = UUID()

        // 1. A genuine V5 store, NO migration plan — how the shipped app
        //    created its store before V6 existed. The dictionary and the
        //    import are seeded through V5's frozen snapshots; the profile
        //    through the live `UserProfile`, which V5 still names live.
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV5.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            let profile = UserProfile(displayName: "Lecteur")
            profileID = profile.id
            ctx.insert(profile)

            let entry = IkeruSchemaV5.VocabularyEntry(word: "傘", reading: "かさ", meaning: "parapluie",
                                                      isInDictionary: true)
            entry.id = entryID
            entry.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
            entry.syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
            ctx.insert(entry)
            ctx.insert(IkeruSchemaV5.VocabularyEncounter(source: .sakuraChat,
                                                         contextSnippet: "傘を持っていこう。",
                                                         entry: entry))

            // A word the learner deleted before the update: it must stay a
            // tombstone, and adoption must leave it alone.
            let deleted = IkeruSchemaV5.VocabularyEntry(word: "犬", reading: "いぬ", meaning: "chien")
            deleted.id = deletedEntryID
            deleted.deletedAt = Date(timeIntervalSince1970: 1_800_000_500)
            ctx.insert(deleted)

            let record = IkeruSchemaV5.TextImport(id: importID, title: "今日は雨",
                                                  content: "今日は雨が降っている。\n傘を持っていこう。",
                                                  source: .photo, coverage: 0.78, entryIDs: [entryID])
            record.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
            record.syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
            ctx.insert(record)

            try ctx.save()
        }

        // 2. Reopen with the CURRENT (V6) schema + the migration plan. The
        //    `.lightweight` V5→V6 stage runs against a file on disk — where
        //    a real store would stop hash-matching if V6 had touched an
        //    existing entity's shape instead of adding two nullable columns.
        let schemaV6 = Schema(versionedSchema: IkeruSchemaV6.self)
        let configV6 = ModelConfiguration(schema: schemaV6, url: url)
        let containerV6 = try ModelContainer(
            for: schemaV6,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV6]
        )
        let ctx = ModelContext(containerV6)

        // Nothing lost, nothing rewritten — and the new column is `nil`, not
        // a fabricated owner: a migration is not an attribution.
        let entries = try ctx.fetch(FetchDescriptor<VocabularyEntry>(sortBy: [SortDescriptor(\.word)]))
        #expect(entries.count == 2)
        let live = try #require(entries.first { $0.id == entryID })
        #expect(live.meaning == "parapluie")
        #expect(live.profileID == nil)
        #expect(live.updatedAt == Date(timeIntervalSince1970: 1_800_000_000),
                "a migration must not bump updatedAt — that would re-push every row")
        #expect(live.encounters?.count == 1)
        let tombstoned = try #require(entries.first { $0.id == deletedEntryID })
        #expect(tombstoned.deletedAt != nil)
        #expect(tombstoned.profileID == nil)

        let imports = try ctx.fetch(FetchDescriptor<TextImport>())
        #expect(imports.count == 1)
        #expect(imports.first?.content == "今日は雨が降っている。\n傘を持っていこう。")
        #expect(imports.first?.entryIDs == [entryID])
        #expect(imports.first?.profileID == nil)

        #expect(try ctx.fetch(FetchDescriptor<UserProfile>()).first?.id == profileID)

        // 3. Adoption — what the app does on its first launch after the
        //    update: the unowned live rows go to the active profile and are
        //    marked dirty so the owner reaches the server; the tombstone is
        //    left exactly as it was.
        let adoptionInstant = Date(timeIntervalSince1970: 1_800_001_000)
        let adopted = try OwnershipAdoption.adoptUnownedRows(into: profileID, in: ctx, at: adoptionInstant)
        try ctx.save()
        #expect(adopted == OwnershipAdoption.Result(entries: 1, imports: 1))
        #expect(live.profileID == profileID)
        #expect(live.updatedAt == adoptionInstant)
        #expect(imports.first?.profileID == profileID)
        #expect(imports.first?.updatedAt == adoptionInstant)
        #expect(tombstoned.profileID == nil)

        // Idempotent: a second pass finds nothing.
        #expect(try OwnershipAdoption.adoptUnownedRows(into: profileID, in: ctx).isEmpty)

        // 4. Close and reopen at V6 (an already-V6 store: the plan must be a
        //    no-op) — the attribution survived the store's lifetime, and the
        //    scoped repository now serves the words to that profile.
        let containerAgain = try ModelContainer(
            for: schemaV6,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schemaV6, url: url)]
        )
        let ctxAgain = ModelContext(containerAgain)
        let reread = try #require(try ctxAgain.fetch(
            FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.id == entryID })
        ).first)
        #expect(reread.profileID == profileID)
        let rereadImport = try #require(try ctxAgain.fetch(
            FetchDescriptor<TextImport>(predicate: #Predicate { $0.id == importID })
        ).first)
        #expect(rereadImport.profileID == profileID)
    }
}
