import Testing
import SwiftData
@testable import IkeruCore

@Suite("Schema versioning & migration plan")
struct IkeruSchemaTests {

    @Test("V1 enumerates exactly the 10 persisted models (frozen — never grow)")
    func v1ModelCount() {
        // V1 is frozen: it must stay byte-identical to TestFlight users' on-disk
        // shape. New models go in a new version. See IkeruSchema.swift.
        #expect(IkeruSchemaV1.models.count == 10)
    }

    @Test("V1 version identifier is 1.0.0")
    func v1Version() {
        #expect(IkeruSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("V2 adds exactly one model (ExerciseOutcomeLog) on top of V1")
    func v2ModelCount() {
        #expect(IkeruSchemaV2.models.count == IkeruSchemaV1.models.count + 1)
        #expect(IkeruSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }

    @Test("Migration plan is well-formed: stages == schemas - 1")
    func planWellFormed() {
        #expect(IkeruMigrationPlan.schemas.count == 2)
        #expect(IkeruMigrationPlan.stages.count == IkeruMigrationPlan.schemas.count - 1)
    }

    @Test("A container opens with the current (V2) versioned schema + migration plan")
    func containerOpensWithPlan() throws {
        let schema = Schema(versionedSchema: IkeruSchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [config]
        )
        // Every declared model resolves to exactly one schema entity — a guard
        // against a model being dropped from (or duplicated in) V2.
        #expect(container.schema.entities.count == IkeruSchemaV2.models.count)
    }

    // MARK: - Golden fingerprints (mechanical guard against silent drift)

    /// Builds the complete, sorted `entityName.propertyName` fingerprint of a
    /// versioned schema — every persisted attribute AND relationship, across
    /// every entity. This is the load-bearing check that makes it impossible
    /// to repeat the `aa03566` bug: that commit added a stored property to
    /// the *live* `RPGState` class, which — because `IkeruSchemaV1.models`
    /// held a live reference to that same class — silently changed what
    /// "V1" meant with no compiler error and no failing test.
    ///
    /// `IkeruSchemaV1` is now built from nested, frozen snapshot types (see
    /// `IkeruSchema.swift`), so it can no longer drift this way. This test
    /// exists as the mechanical guard for the *next* time someone is tempted
    /// to "just add a property" to a model referenced by a frozen versioned
    /// schema, or to edit a frozen nested snapshot directly instead of
    /// cutting a new version.
    private static func fingerprint(of schema: Schema) -> [String] {
        schema.entities
            .flatMap { entity in entity.properties.map { "\(entity.name).\($0.name)" } }
            .sorted()
    }

    /// Deeper drift guard than the name list: a stable digest of SwiftData's
    /// OWN description of every property (which includes value type,
    /// optionality, and annotations) — so retyping or re-optionalizing an
    /// EXISTING property, which leaves the name fingerprint unchanged, still
    /// fails loudly. On failure: if the change was intentional, cut a new
    /// VersionedSchema + migration stage and update the golden hash here;
    /// never edit a frozen schema in place.
    private static func typedFingerprint(of schema: Schema) -> String {
        let lines = schema.entities
            .flatMap { entity in entity.properties.map { "\(entity.name)|\(String(describing: $0))" } }
            .sorted()
            .joined(separator: "\n")
        // Deterministic FNV-1a (Swift's Hasher is seeded per-process).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in lines.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    /// The exact `entityName.propertyName` set of `IkeruSchemaV1`, frozen at
    /// `a7371a3`. In particular: no `RPGState.activeDaysCount` — that
    /// property must not exist until V2.
    private static let v1GoldenFingerprintList = [
        "AssetManifest.generatedAt",
        "AssetManifest.hash",
        "AssetManifest.id",
        "AssetManifest.lastAccessedAt",
        "AssetManifest.sizeBytes",
        "AssetManifest.sourceText",
        "AssetManifest.typeRawValue",
        "Card.back",
        "Card.dueDate",
        "Card.easeFactor",
        "Card.front",
        "Card.fsrsState",
        "Card.id",
        "Card.interval",
        "Card.jlptLevelRawValue",
        "Card.lapseCount",
        "Card.leechFlag",
        "Card.profile",
        "Card.reviewLogs",
        "Card.typeRawValue",
        "CompanionChatMessage.content",
        "CompanionChatMessage.createdAt",
        "CompanionChatMessage.id",
        "CompanionChatMessage.profileId",
        "CompanionChatMessage.roleRawValue",
        "DailyTerm.addedToDictionary",
        "DailyTerm.caption",
        "DailyTerm.createdAt",
        "DailyTerm.date",
        "DailyTerm.id",
        "DailyTerm.jlptLevelRawValue",
        "DailyTerm.meaning",
        "DailyTerm.pronunciation",
        "DailyTerm.reading",
        "DailyTerm.revealedAt",
        "DailyTerm.word",
        "MnemonicCache.character",
        "MnemonicCache.generatedAt",
        "MnemonicCache.id",
        "MnemonicCache.mnemonic",
        "MnemonicCache.tierUsed",
        "RPGState.acknowledgedUnlocksData",
        "RPGState.attributesData",
        "RPGState.currentDailyStreak",
        "RPGState.equippedBadgeIDsData",
        "RPGState.equippedThemeID",
        "RPGState.equippedTitleID",
        "RPGState.id",
        "RPGState.jlptBackfillVersion",
        "RPGState.lastReadinessBestFit",
        "RPGState.lastSessionDate",
        "RPGState.level",
        "RPGState.longestDailyStreak",
        "RPGState.lootBoxesData",
        "RPGState.lootInventoryData",
        "RPGState.profile",
        "RPGState.sessionsSinceLastDrop",
        "RPGState.totalReviewsCompleted",
        "RPGState.totalSessionsCompleted",
        "RPGState.xp",
        "ReviewLog.card",
        "ReviewLog.gradeRawValue",
        "ReviewLog.id",
        "ReviewLog.responseTimeMs",
        "ReviewLog.timestamp",
        "UserProfile.cards",
        "UserProfile.createdAt",
        "UserProfile.displayName",
        "UserProfile.id",
        "UserProfile.rpgState",
        "UserProfile.settings",
        "VocabularyEncounter.contextSnippet",
        "VocabularyEncounter.entry",
        "VocabularyEncounter.id",
        "VocabularyEncounter.sourceRawValue",
        "VocabularyEncounter.timestamp",
        "VocabularyEntry.createdAt",
        "VocabularyEntry.dueDate",
        "VocabularyEntry.easeFactor",
        "VocabularyEntry.encounters",
        "VocabularyEntry.fsrsState",
        "VocabularyEntry.id",
        "VocabularyEntry.interval",
        "VocabularyEntry.isInDictionary",
        "VocabularyEntry.jlptLevelRawValue",
        "VocabularyEntry.lapseCount",
        "VocabularyEntry.meaning",
        "VocabularyEntry.reading",
        "VocabularyEntry.word",
    ]

    /// If this test fails, one of two things happened:
    /// 1. A referenced `@Model` gained/lost/renamed a stored property, and
    ///    that model is reachable from `IkeruSchemaV1.models` — **do not**
    ///    "fix" this by editing `IkeruSchemaV1`'s nested frozen types or by
    ///    updating this golden list. Instead: add a new `IkeruSchemaVn`
    ///    with the change, and a `MigrationStage` from V1 (or the prior
    ///    frozen version) to it.
    /// 2. You intentionally changed a *frozen* nested snapshot inside
    ///    `IkeruSchemaV1` — don't; frozen snapshots must stay byte-identical
    ///    to what shipped in `a7371a3` forever.
    @Test("V1 golden fingerprint — 10 entities, exact property set frozen at a7371a3")
    func v1GoldenFingerprint() {
        let schema = Schema(versionedSchema: IkeruSchemaV1.self)
        #expect(!Self.v1GoldenFingerprintList.contains("RPGState.activeDaysCount"))
        #expect(Self.fingerprint(of: schema) == Self.v1GoldenFingerprintList)
        // Typed digest: also catches retyping/re-optionalizing an EXISTING
        // property, which the name list above cannot see.
        #expect(Self.typedFingerprint(of: schema) == "3d20f3ad6b03e99b")
    }

    @Test("V2 golden fingerprint — V1 plus RPGState.activeDaysCount plus ExerciseOutcomeLog")
    func v2GoldenFingerprint() {
        let schema = Schema(versionedSchema: IkeruSchemaV2.self)
        var golden = Self.v1GoldenFingerprintList
        golden.append("RPGState.activeDaysCount")
        golden.append(contentsOf: [
            "ExerciseOutcomeLog.accuracy",
            "ExerciseOutcomeLog.id",
            "ExerciseOutcomeLog.profileID",
            "ExerciseOutcomeLog.skillRawValue",
            "ExerciseOutcomeLog.timestamp",
        ])
        golden.sort()
        #expect(Self.fingerprint(of: schema) == golden)
        // Typed digest — see v1GoldenFingerprint for what this adds.
        #expect(Self.typedFingerprint(of: schema) == "eb462d92926249b7")
    }
}
