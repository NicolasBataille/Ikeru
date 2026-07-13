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
        // Full V2 schema so the ExerciseOutcomeLog entity is present.
        let schema = Schema(versionedSchema: IkeruSchemaV2.self)
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
        let a = try seedProfile(container, active: true)
        let b = try seedProfile(container, active: false)
        defer { clearActiveKey() }
        let repo = CardRepository(modelContainer: container)

        setActive(a)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 1.0)
        setActive(b)
        await repo.recordExerciseOutcome(skill: .listening, accuracy: 0.0)

        // Active = A sees only A's perfect outcome.
        setActive(a)
        #expect(await repo.listeningAccuracyLast30() == 1.0)
        // Active = B sees only B's failing outcome.
        setActive(b)
        #expect(await repo.listeningAccuracyLast30() == 0.0)
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

// MARK: - V1 → V2 migration

@Suite("IkeruSchema V1→V2 migration")
struct IkeruSchemaMigrationTests {

    @Test("Existing V1 data survives the lightweight V1→V2 stage; ExerciseOutcomeLog becomes usable")
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

        // 1. Create a genuine V1-versioned store and insert V1 data.
        do {
            let schema = Schema(versionedSchema: IkeruSchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            ctx.insert(UserProfile(displayName: "Migrator"))
            ctx.insert(Card(front: "\u{4E00}", back: "one", type: .kanji, dueDate: Date()))
            try ctx.save()
        }

        // 2. Reopen with the V2 schema + migration plan → the lightweight stage runs.
        let schemaV2 = Schema(versionedSchema: IkeruSchemaV2.self)
        let configV2 = ModelConfiguration(schema: schemaV2, url: url)
        let containerV2 = try ModelContainer(
            for: schemaV2,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [configV2]
        )
        let ctx = ModelContext(containerV2)

        // V1 data survived intact.
        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Migrator")
        #expect(try ctx.fetch(FetchDescriptor<Card>()).count == 1)

        // The newly-added entity is usable in the migrated store.
        let profileID = try #require(profiles.first?.id)
        ctx.insert(ExerciseOutcomeLog(skill: .listening, accuracy: 1.0, profileID: profileID))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<ExerciseOutcomeLog>()).count == 1)
    }
}
