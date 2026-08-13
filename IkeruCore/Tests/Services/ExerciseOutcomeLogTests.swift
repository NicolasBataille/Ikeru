import Testing
import SwiftData
import Foundation
@testable import IkeruCore

// MARK: - Accuracy mapping (pure)

@Suite("ExerciseOutcomeAccuracy mapping")
struct ExerciseOutcomeAccuracyTests {

    @Test("Listening is binary: correct → 1.0, incorrect → 0.0")
    func listeningBinary() {
        #expect(ExerciseOutcomeAccuracy.from(grade: .good, skill: .listening) == 1.0)
        #expect(ExerciseOutcomeAccuracy.from(grade: .easy, skill: .listening) == 1.0)
        #expect(ExerciseOutcomeAccuracy.from(grade: .again, skill: .listening) == 0.0)
    }

    @Test("Speaking maps the four shadowing bands to increasing representatives")
    func speakingBands() {
        let again = ExerciseOutcomeAccuracy.from(grade: .again, skill: .speaking)
        let hard = ExerciseOutcomeAccuracy.from(grade: .hard, skill: .speaking)
        let good = ExerciseOutcomeAccuracy.from(grade: .good, skill: .speaking)
        let easy = ExerciseOutcomeAccuracy.from(grade: .easy, skill: .speaking)
        #expect(again < hard)
        #expect(hard < good)
        #expect(good < easy)
        #expect(again >= 0 && easy <= 1)
        // A perfect shadow clears the 0.6 unlock threshold; a failed one doesn't.
        #expect(easy >= 0.6)
        #expect(again < 0.6)
    }
}

// MARK: - Aggregation (SwiftData)

@Suite("ExerciseOutcomeLog aggregation", .serialized)
@MainActor
struct ExerciseOutcomeLogAggregationTests {

    private func makeContainer() throws -> ModelContainer {
        // Full current (V4) schema so the ExerciseOutcomeLog entity is
        // present. Must be V4, not V3: `IkeruSchemaV3` is now frozen (nested
        // snapshot types, cloud-sync lot 0, 2026-08-13) — a container opened
        // with `versionedSchema: IkeruSchemaV3.self` would bind
        // `CardRepository`'s live-type fetches (UserProfile/Card/
        // ReviewLog/RPGState, used throughout this suite) to the WRONG
        // entity identity and crash with "Failed to cast model ... to X".
        // See IkeruSchema.swift's `IkeruSchemaV3` doc comment.
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Inserts a profile. When `active`, points the UserDefaults active-profile
    /// key at it (the actor's scoping reads that key). Returns the profile.
    @discardableResult
    private func seedProfile(_ container: ModelContainer, active: Bool) throws -> UserProfile {
        let profile = UserProfile(displayName: "P-\(UUID().uuidString.prefix(4))")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        if active {
            UserDefaults.standard.set(
                profile.id.uuidString,
                forKey: UserProfile.activeProfileIDDefaultsKey
            )
        }
        return profile
    }

    private func setActive(_ profile: UserProfile) {
        UserDefaults.standard.set(
            profile.id.uuidString,
            forKey: UserProfile.activeProfileIDDefaultsKey
        )
    }

    private func clearActiveKey() {
        UserDefaults.standard.removeObject(forKey: UserProfile.activeProfileIDDefaultsKey)
    }

    @Test("Empty store yields 0 for every aggregation")
    func emptyIsZero() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        #expect(await repo.listeningAccuracyLast30() == 0)
        #expect(await repo.listeningRecallLast30Days() == 0)
        #expect(await repo.speakingAccuracyLast30() == 0)
    }

    @Test("listeningAccuracyLast30 is the mean of recorded listening outcomes")
    func listeningMean() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        // 3 correct + 1 incorrect → mean 0.75.
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 0.0)
        #expect(await repo.listeningAccuracyLast30() == 0.75)
        // Speaking aggregation must not see listening outcomes.
        #expect(await repo.speakingAccuracyLast30() == 0)
    }

    @Test("listeningAccuracyLast30 averages only the most recent 30 attempts")
    func listeningWindowOfThirty() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        // 10 old failures (older timestamps), then 30 recent perfect passes.
        for i in 0..<10 {
            await repo.recordExerciseOutcome(
                skill: .listening, accuracy: 0.0,
                now: base.addingTimeInterval(Double(i))
            )
        }
        for i in 0..<30 {
            await repo.recordExerciseOutcome(
                skill: .listening, accuracy: 1.0,
                now: base.addingTimeInterval(1000 + Double(i))
            )
        }
        // Window = last 30 by timestamp → all the 1.0s, none of the old 0.0s.
        #expect(await repo.listeningAccuracyLast30() == 1.0)
    }

    @Test("listeningRecallLast30Days excludes outcomes older than 30 days")
    func recallDayWindow() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let within = now.addingTimeInterval(-5 * 86_400)   // 5 days ago
        let outside = now.addingTimeInterval(-40 * 86_400)  // 40 days ago
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0, now: within)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 0.0, now: outside)
        // Only the in-window 1.0 counts → mean 1.0.
        #expect(await repo.listeningRecallLast30Days(now: now) == 1.0)
    }

    @Test("Aggregation is scoped to the active profile")
    func profileIsolation() async throws {
        let container = try makeContainer()
        let profileA = try seedProfile(container, active: true)
        let profileB = try seedProfile(container, active: false)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)

        setActive(profileA)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0)
        setActive(profileB)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 0.0)

        // Active = A sees only A's perfect outcome.
        setActive(profileA)
        #expect(await repo.listeningAccuracyLast30() == 1.0)
        // Active = B sees only B's failing outcome.
        setActive(profileB)
        #expect(await repo.listeningAccuracyLast30() == 0.0)
    }

    @Test("Out-of-range accuracy is clamped to [0, 1] at the persistence boundary")
    func accuracyClamped() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        // 1.5 clamps to 1.0, -0.5 clamps to 0.0 → mean 0.5 (not (1.5-0.5)/2=0.5
        // by coincidence; use asymmetric values to prove clamping, not luck).
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.5)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.5)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: -0.5)
        // Clamped: (1.0 + 1.0 + 0.0) / 3 = 0.666…, not (1.5+1.5-0.5)/3 = 0.833…
        let mean = await repo.listeningAccuracyLast30()
        #expect(abs(mean - (2.0 / 3.0)) < 1e-9)
    }

    @Test("Recorded shadowing outcomes feed speakingAccuracyLast30")
    func speakingAggregation() async throws {
        let container = try makeContainer()
        try seedProfile(container, active: true)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)
        await repo.recordExerciseOutcome(skill: .speaking, accuracy: 0.8)
        await repo.recordExerciseOutcome(skill: .speaking, accuracy: 0.6)
        #expect(await repo.speakingAccuracyLast30() == 0.7)
        // Listening aggregation must not see speaking outcomes.
        #expect(await repo.listeningAccuracyLast30() == 0)
    }
}

// MARK: - V1 → V2 → V3 migration
//
// Migrates a genuine V1-shaped store through the FULL current chain
// (V1→V2→V3), matching what production actually does on a real user's
// device — not just the V1→V2 stage in isolation. Extended for
// learner-telemetry lot 1 / remediation #17 (which added V3): the store is
// still SEEDED as V1 (unchanged), only the reopen target moved from V2 to
// V3 so this keeps proving the WHOLE migration plan, not a stale prefix of
// it. `IkeruSchemaTests.swift`'s `StoreMigrationV2V3Tests` separately proves
// the V2→V3 stage in isolation, starting from a V2-shaped store.

// Runs in its OWN CI step / own `swift test` process: opening a V1-shaped
// container poisons CoreData's process-global entity↔class cache, so any
// later V2/V3 fetch of RPGState in the same process can materialize the
// wrong class ("Failed to cast model ... to RPGState"). Process isolation —
// not .serialized, not --no-parallel — is the only reliable containment.
// The suite name deliberately avoids the "IkeruSchema" substring the main
// CI filter matches.
@Suite("LegacyStoreMigration V1→V2→V3→V4", .serialized)
struct LegacyStoreMigrationTests {

    @Test("Existing V1 data survives the lightweight V1→V2→V3→V4 chain; ExerciseOutcomeLog becomes usable")
    func v1ToV2AdditiveMigration() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ikeru-mig-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        }

        // 1. Create a genuine V1-versioned store, mimicking the released app
        //    exactly: a plain `Schema(versionedSchema: IkeruSchemaV1.self)`
        //    container with NO migration plan attached. Insert data using the
        //    FROZEN V1 model types (`IkeruSchemaV1.UserProfile`, `.Card`,
        //    `.RPGState`, `.ReviewLog`) — not the live top-level types, which
        //    now describe V4's shape (learner-telemetry lot 1 / remediation
        //    #17 froze V2 and added V3; cloud-sync lot 0 froze V3 and added
        //    V4 — see IkeruSchema.swift).
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            let profile = IkeruSchemaV1.UserProfile(displayName: "Migrator")
            let rpg = try #require(profile.rpgState)
            rpg.xp = 4_200
            rpg.level = 7
            rpg.currentDailyStreak = 12
            rpg.longestDailyStreak = 30
            ctx.insert(profile)

            let card = IkeruSchemaV1.Card(front: "\u{4E00}", back: "one", type: .kanji, dueDate: Date())
            card.profile = profile
            ctx.insert(card)
            ctx.insert(IkeruSchemaV1.ReviewLog(card: card, grade: .good, responseTimeMs: 1_500))

            try ctx.save()
        }

        // 2. Reopen with the CURRENT (V4) schema + migration plan → ALL
        //    THREE lightweight stages run in sequence (V1→V2, V2→V3, then
        //    V3→V4) — exactly what production does. Must target V4, not V3:
        //    `IkeruSchemaV3` is now frozen (nested snapshot types,
        //    cloud-sync lot 0), so a container opened with `versionedSchema:
        //    IkeruSchemaV3.self` would bind the live-type fetches below to
        //    the WRONG entity identity and crash with "Failed to cast model
        //    ... to X" — the same failure class this test exists to catch,
        //    just one version later.
        let schemaV4 = Schema(versionedSchema: IkeruSchemaV4.self)
        let configV4 = ModelConfiguration(schema: schemaV4, url: url)
        let containerV4 = try ModelContainer(
            for: schemaV4,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV4]
        )
        let ctx = ModelContext(containerV4)

        // V1 data survived intact through ALL THREE stages — now readable
        // through the LIVE (V4) types.
        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Migrator")
        #expect(try ctx.fetch(FetchDescriptor<Card>()).count == 1)

        let reviewLogs = try ctx.fetch(FetchDescriptor<ReviewLog>())
        #expect(reviewLogs.count == 1)
        // The V3-only columns backfill to nil for a row that predates them
        // by two versions.
        #expect(reviewLogs.first?.answeredValue == nil)
        #expect(reviewLogs.first?.exerciseType == nil)
        #expect(reviewLogs.first?.surface == nil)
        // ...and the V4-only (cloud-sync) columns backfill per their
        // documented defaults for a row that predates them by three
        // versions.
        #expect(reviewLogs.first?.updatedAt == Date(timeIntervalSince1970: 0))
        #expect(reviewLogs.first?.deletedAt == nil)
        #expect(reviewLogs.first?.syncedAt == nil)

        // RPGState's pre-existing values survived the migration untouched...
        let rpgStates = try ctx.fetch(FetchDescriptor<RPGState>())
        #expect(rpgStates.count == 1)
        let rpg = try #require(rpgStates.first)
        #expect(rpg.xp == 4_200)
        #expect(rpg.level == 7)
        #expect(rpg.currentDailyStreak == 12)
        #expect(rpg.longestDailyStreak == 30)
        // ...and the new V2-only property backfills to its documented
        // default for rows that predate it.
        #expect(rpg.activeDaysCount == 0)
        // ...and the new V4-only (cloud-sync) columns backfill too.
        #expect(rpg.updatedAt == Date(timeIntervalSince1970: 0))

        // The V2-added entity is usable in the migrated store, and its
        // freshly-inserted row gets a real `updatedAt` (V4 column), not the
        // migration-backfill sentinel.
        let profileID = try #require(profiles.first?.id)
        let outcome = ExerciseOutcomeLog(skill: .listening, accuracy: 1.0, profileID: profileID)
        ctx.insert(outcome)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<ExerciseOutcomeLog>()).count == 1)
        #expect(outcome.updatedAt != Date(timeIntervalSince1970: 0))
    }
}
