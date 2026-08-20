import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - V4 → V5 migration (« apporte ton propre texte »)
//
// Runs in its OWN CI step / own `swift test` process — same containment
// requirement as `StoreMigrationV2V3Tests`, `StoreMigrationV3V4Tests` and
// `LegacyStoreMigrationTests`: opening a versioned-schema container against an
// on-disk store and then reopening that SAME store under another version can
// poison SwiftData's process-global entity↔class cache, after which a fetch of
// an affected type anywhere else in the process materializes the wrong class
// ("Failed to cast model … to X"). Process isolation — not `.serialized`, not
// `--no-parallel` alone — is the only reliable containment.
//
// V4 and V5 both name LIVE top-level types (V4 has no frozen nested snapshots),
// so the poisoning mechanism is less likely to fire here than in the V1/V2/V3
// suites. "Less likely" is not "cannot", and a green full run proves nothing
// about that — see CLAUDE.md. The suite stays isolated.
//
// Suite name deliberately distinct from "StoreMigrationV2V3",
// "StoreMigrationV3V4", "LegacyStoreMigration" and "IkeruSchema": those are the
// existing CI `--filter` / `--skip` substrings, and sharing one would drag this
// suite into the wrong process. Wired in `.github/workflows/ci.yml` as its own
// `swift test --no-parallel --filter "StoreMigrationV4V5"` step, plus a
// `--skip "StoreMigrationV4V5"` on the main run.
@Suite("StoreMigrationV4V5", .serialized)
struct StoreMigrationV4V5Tests {

    /// One long arrange-migrate-assert sequence on purpose: the store's
    /// lifetime is the subject of the test, so splitting it into helpers would
    /// move that lifetime out of the test body.
    @Test("Existing V4 rows survive the lightweight V4→V5 stage, and TextImport's table materializes")
    // swiftlint:disable:next function_body_length
    func v4ToV5AdditiveMigration() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-v4v5-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        let profileID = UUID()
        let entryID = UUID()

        // 1. A genuine V4 store: `Schema(versionedSchema: IkeruSchemaV4.self)`
        //    with NO migration plan, exactly how the shipped app created its
        //    store before V5 existed. V4 names the LIVE types, and at this
        //    commit the live types are still V4-shaped (nothing outside
        //    `TextImport` changed) — so seeding with the top-level types is
        //    seeding V4, not a later shape. `IkeruSchemaTests.v4GoldenFingerprint`
        //    is what keeps that sentence true.
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV4.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            let profile = UserProfile(displayName: "Lecteur")
            let rpg = try #require(profile.rpgState)
            rpg.xp = 4_200
            rpg.activeDaysCount = 31
            ctx.insert(profile)

            let card = Card(front: "傘", back: "parapluie", type: .kanji, dueDate: Date())
            card.profile = profile
            ctx.insert(card)

            let log = ReviewLog(card: card, grade: .good, responseTimeMs: 1_400,
                                timestamp: Date(timeIntervalSince1970: 1_860_000_000),
                                answeredValue: "かさ", exerciseType: "kanjiStudy",
                                surface: "iphone.session")
            ctx.insert(log)

            let entry = VocabularyEntry(word: "傘", reading: "かさ", meaning: "parapluie",
                                        isInDictionary: true)
            entry.id = entryID
            ctx.insert(entry)
            let encounter = VocabularyEncounter(source: .sakuraChat,
                                                contextSnippet: "傘を持っていこう。",
                                                entry: entry)
            ctx.insert(encounter)

            let outcome = ExerciseOutcomeLog(skill: .reading, accuracy: 0.82, profileID: profileID)
            ctx.insert(outcome)

            let message = CompanionChatMessage(role: .companion, content: "いい天気ですね",
                                               profileId: profileID)
            ctx.insert(message)

            try ctx.save()
        }

        // 2. Reopen with the CURRENT (V5) schema + the migration plan. The
        //    `.lightweight` V4→V5 stage runs: one new entity, nothing else
        //    touched. If V5 had silently modified an existing entity, THIS is
        //    where a real store stops hash-matching and the container throws —
        //    which is the whole point of running it against a file on disk
        //    rather than an in-memory store.
        let schemaV5 = Schema(versionedSchema: IkeruSchemaV5.self)
        let configV5 = ModelConfiguration(schema: schemaV5, url: url)
        let containerV5 = try ModelContainer(
            for: schemaV5,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV5]
        )
        let ctx = ModelContext(containerV5)

        // Nothing was lost, and nothing was rewritten — including the V4 sync
        // columns, which must NOT be bumped by a migration (a migration is not
        // a user edit; bumping `updatedAt` would push every row back up).
        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.displayName == "Lecteur")
        #expect(profile.deletedAt == nil)

        let rpg = try #require(try ctx.fetch(FetchDescriptor<RPGState>()).first)
        #expect(rpg.xp == 4_200)
        #expect(rpg.activeDaysCount == 31)

        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.front == "傘")
        #expect(cards.first?.profile?.id == profile.id)

        let logs = try ctx.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.answeredValue == "かさ")
        #expect(logs.first?.surface == "iphone.session")
        #expect(logs.first?.card?.id == cards.first?.id)

        let entries = try ctx.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.id == entryID)
        #expect(entries.first?.meaning == "parapluie")

        let encounters = try ctx.fetch(FetchDescriptor<VocabularyEncounter>())
        #expect(encounters.count == 1)
        #expect(encounters.first?.contextSnippet == "傘を持っていこう。")
        #expect(encounters.first?.entry?.id == entryID)

        #expect(try ctx.fetch(FetchDescriptor<ExerciseOutcomeLog>()).first?.accuracy == 0.82)
        #expect(try ctx.fetch(FetchDescriptor<CompanionChatMessage>()).first?.content == "いい天気ですね")

        // The new entity's table exists and is empty — an upgrading learner has
        // no imports yet, and asking for them must return nothing, not throw.
        #expect(try ctx.fetch(FetchDescriptor<TextImport>()).isEmpty)

        // 3. The new entity is usable in the migrated store, `[UUID]` column
        //    included. Written here, read back in step 4 from a store that was
        //    closed in between — an array property that only works while the
        //    container is warm would pass an in-memory test and lose the
        //    learner's words on the next launch.
        let record = TextImport(content: "今日は雨が降っている。\n傘を持っていこう。",
                                source: .photo, coverage: 0.78, entryIDs: [entryID])
        let recordID = record.id
        ctx.insert(record)
        try ctx.save()
        #expect(record.updatedAt != Date(timeIntervalSince1970: 0))

        // 4. Close and reopen at V5 (now an already-V5 store: the plan must be
        //    a no-op, not a second migration) and read the import back.
        let containerAgain = try ModelContainer(
            for: schemaV5,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schemaV5, url: url)]
        )
        let ctxAgain = ModelContext(containerAgain)
        let reread = try #require(try ctxAgain.fetch(
            FetchDescriptor<TextImport>(predicate: #Predicate { $0.id == recordID })
        ).first)
        // The learner's text, byte for byte — never re-derived, never trimmed.
        #expect(reread.content == "今日は雨が降っている。\n傘を持っていこう。")
        #expect(reread.title == "今日は雨が降っている。")
        #expect(reread.source == .photo)
        #expect(reread.coverage == 0.78)
        #expect(reread.entryIDs == [entryID])
        // And the V4 rows are still there after the second open.
        #expect(try ctxAgain.fetch(FetchDescriptor<VocabularyEntry>()).count == 1)
        #expect(try ctxAgain.fetch(FetchDescriptor<UserProfile>()).count == 1)
    }
}
