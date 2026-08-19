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

    @Test("V3 has the same model COUNT as V2 (ReviewLog gains columns, not a new entity)")
    func v3ModelCount() {
        #expect(IkeruSchemaV3.models.count == IkeruSchemaV2.models.count)
        #expect(IkeruSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    }

    @Test("V4 has the same model COUNT as V3 (8 entities gain sync columns, not new entities)")
    func v4ModelCount() {
        #expect(IkeruSchemaV4.models.count == IkeruSchemaV3.models.count)
        #expect(IkeruSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    }

    @Test("V5 adds exactly one entity to V4 (TextImport), and touches nothing else")
    func v5ModelCount() {
        #expect(IkeruSchemaV5.models.count == IkeruSchemaV4.models.count + 1)
        #expect(IkeruSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        // Le point qui compte : V5 est purement ADDITIVE. Toute entité de V4
        // doit se retrouver telle quelle dans V5 — c'est ce qui autorise une
        // étape `.lightweight` et ce qui garde intact le sens de V4.
        let v4Names = Set(IkeruSchemaV4.models.map { String(describing: $0) })
        let v5Names = Set(IkeruSchemaV5.models.map { String(describing: $0) })
        #expect(v4Names.isSubset(of: v5Names))
        #expect(v5Names.subtracting(v4Names) == ["TextImport"])
    }

    @Test("Migration plan is well-formed: stages == schemas - 1")
    func planWellFormed() {
        #expect(IkeruMigrationPlan.schemas.count == 5)
        #expect(IkeruMigrationPlan.stages.count == IkeruMigrationPlan.schemas.count - 1)
    }

    @Test("A container opens with the current (V5) versioned schema + migration plan")
    func containerOpensWithPlan() throws {
        let schema = Schema(versionedSchema: IkeruSchemaV5.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [config]
        )
        // Every declared model resolves to exactly one schema entity — a guard
        // against a model being dropped from (or duplicated in) V5.
        #expect(container.schema.entities.count == IkeruSchemaV5.models.count)
    }

    // Deliberately NOT adding a "container opens with frozen V2 (or V3)
    // alone" test here: unlike `Schema(versionedSchema:)` construction (safe
    // — the golden fingerprint tests below already do this for V2/V3),
    // actually *opening a ModelContainer* against a frozen version's nested
    // types poisons SwiftData's process-global entity↔class cache for the
    // rest of THIS suite's process (same containment rule as
    // `StoreMigrationV2V3Tests` / `StoreMigrationV3V4Tests` — see their
    // header comments). This file runs `--no-parallel` alongside
    // CardRepositoryTests, KanaCardRepositoryTests, ProgressServiceTests,
    // etc., all of which fetch live types — planting that container-open
    // here would make their green status order-dependent. `v2GoldenFingerprint`
    // / `v3GoldenFingerprint` below and the isolated-process migration
    // suites already cover what this would have proven.

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
    /// One property, rendered from its **documented** API surface.
    ///
    /// ⚠️ Never `String(describing:)` a `Schema.Property`. That was the first
    /// version, and it made the digest **machine-dependent**: SwiftData's own
    /// description format is an implementation detail that differs between OS
    /// versions, so the same code produced `93c7f1726ba34d2a` on macOS 26 and
    /// `16a69598f17ed293` on the CI's macOS 15. A golden digest that fails
    /// depending on where it runs is worse than no digest at all — it teaches
    /// people to update the constant until the light goes green, which is
    /// exactly the reflex that lets a real schema drift through.
    ///
    /// Everything named here is public, stable API, and covers what the digest
    /// exists to catch: a property retyped, made optional, made unique, made
    /// transient, or given a default it did not have.
    private static func canonical(_ property: any SchemaProperty) -> String {
        if let attribute = property as? Schema.Attribute {
            return [
                "attr", attribute.name,
                "type=\(attribute.valueType)",
                "optional=\(attribute.isOptional)",
                "unique=\(attribute.isUnique)",
                "transformable=\(attribute.isTransformable)",
                "transient=\(attribute.isTransient)",
                "hasDefault=\(attribute.defaultValue != nil)",
            ].joined(separator: "|")
        }
        if let relationship = property as? Schema.Relationship {
            return [
                "rel", relationship.name,
                "optional=\(relationship.isOptional)",
                "toMany=\(relationship.isToOneRelationship == false)",
                "delete=\(relationship.deleteRule)",
            ].joined(separator: "|")
        }
        return "other|\(property.name)"
    }

    private static func typedFingerprint(of schema: Schema) -> String {
        let lines = schema.entities
            .flatMap { entity in entity.properties.map { "\(entity.name)|\(Self.canonical($0))" } }
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
        #expect(Self.typedFingerprint(of: schema) == "6b4dbca1984d31df")
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
        #expect(Self.typedFingerprint(of: schema) == "72c5a1eaf04ca95f")
    }

    @Test("V3 golden fingerprint — V2 plus ReviewLog.answeredValue/exerciseType/surface")
    func v3GoldenFingerprint() {
        let schema = Schema(versionedSchema: IkeruSchemaV3.self)
        var golden = Self.v1GoldenFingerprintList
        golden.append("RPGState.activeDaysCount")
        golden.append(contentsOf: [
            "ExerciseOutcomeLog.accuracy",
            "ExerciseOutcomeLog.id",
            "ExerciseOutcomeLog.profileID",
            "ExerciseOutcomeLog.skillRawValue",
            "ExerciseOutcomeLog.timestamp",
        ])
        golden.append(contentsOf: [
            "ReviewLog.answeredValue",
            "ReviewLog.exerciseType",
            "ReviewLog.surface",
        ])
        golden.sort()
        #expect(Self.fingerprint(of: schema) == golden)
        // Typed digest — see v1GoldenFingerprint for what this adds. Produced
        // by running this suite (`swift test --no-parallel --filter
        // "IkeruSchema"`) and reading the printed value; not hand-computed.
        #expect(Self.typedFingerprint(of: schema) == "38a4f9aceb34b52c")
    }

    /// The 24 `updatedAt`/`deletedAt`/`syncedAt` columns cloud-sync lot 0
    /// (`docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1) adds — one
    /// triple per synchronized entity (spec §3): `UserProfile`, `Card`,
    /// `ReviewLog`, `RPGState`, `VocabularyEntry`, `VocabularyEncounter`,
    /// `ExerciseOutcomeLog`, `CompanionChatMessage`. `MnemonicCache`,
    /// `AssetManifest`, `DailyTerm` are explicitly not synchronized and gain
    /// nothing.
    private static let v4SyncColumns = [
        "UserProfile.updatedAt", "UserProfile.deletedAt", "UserProfile.syncedAt",
        "Card.updatedAt", "Card.deletedAt", "Card.syncedAt",
        "ReviewLog.updatedAt", "ReviewLog.deletedAt", "ReviewLog.syncedAt",
        "RPGState.updatedAt", "RPGState.deletedAt", "RPGState.syncedAt",
        "VocabularyEntry.updatedAt", "VocabularyEntry.deletedAt", "VocabularyEntry.syncedAt",
        "VocabularyEncounter.updatedAt", "VocabularyEncounter.deletedAt", "VocabularyEncounter.syncedAt",
        "ExerciseOutcomeLog.updatedAt", "ExerciseOutcomeLog.deletedAt", "ExerciseOutcomeLog.syncedAt",
        "CompanionChatMessage.updatedAt", "CompanionChatMessage.deletedAt", "CompanionChatMessage.syncedAt",
    ]

    @Test("V4 golden fingerprint — V3 plus updatedAt/deletedAt/syncedAt on the 8 synchronized entities")
    func v4GoldenFingerprint() {
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
        var golden = Self.v1GoldenFingerprintList
        golden.append("RPGState.activeDaysCount")
        golden.append(contentsOf: [
            "ExerciseOutcomeLog.accuracy",
            "ExerciseOutcomeLog.id",
            "ExerciseOutcomeLog.profileID",
            "ExerciseOutcomeLog.skillRawValue",
            "ExerciseOutcomeLog.timestamp",
        ])
        golden.append(contentsOf: [
            "ReviewLog.answeredValue",
            "ReviewLog.exerciseType",
            "ReviewLog.surface",
        ])
        golden.append(contentsOf: Self.v4SyncColumns)
        golden.sort()
        #expect(Self.fingerprint(of: schema) == golden)
        // Typed digest — minted 2026-08-19 by running this suite, as the note
        // that stood here asked. It was missing until V5 shipped, which meant
        // V4 (whose `models` are LIVE types) had NO guard against a property
        // being *retyped* or *re-optionalized*: the name list above cannot see
        // that, and V4 is the version every store on a real device is coming
        // from. See v1GoldenFingerprint for the failure mode.
        #expect(Self.typedFingerprint(of: schema) == "e0f4cd9747ec06b4")
    }

    /// The 10 columns `TextImport` brings — and nothing else. V5 is purely
    /// additive by construction (see `IkeruSchemaV5`'s doc comment); this list
    /// is what makes "by construction" mechanically checkable.
    private static let v5TextImportColumns = [
        "TextImport.content",
        "TextImport.coverage",
        "TextImport.createdAt",
        "TextImport.deletedAt",
        "TextImport.entryIDs",
        "TextImport.id",
        "TextImport.sourceRawValue",
        "TextImport.syncedAt",
        "TextImport.title",
        "TextImport.updatedAt",
    ]

    /// The gap this closes: `v5ModelCount` only compares *entity name sets*, so
    /// it would stay green if a V4 entity silently gained, lost or retyped a
    /// property — which is exactly the `aa03566` failure, since V4 and V5 both
    /// name LIVE types. Both fingerprints below are needed: the name list
    /// catches added/removed/renamed properties, the typed digest catches
    /// retyping and re-optionalizing.
    @Test("V5 golden fingerprint — V4 untouched, plus exactly TextImport's 10 columns")
    func v5GoldenFingerprint() {
        let v4 = Self.fingerprint(of: Schema(versionedSchema: IkeruSchemaV4.self))
        let v5 = Self.fingerprint(of: Schema(versionedSchema: IkeruSchemaV5.self))
        // Not one property of V4 moved: additive means additive.
        #expect(v5.filter { !$0.hasPrefix("TextImport.") } == v4)
        #expect(v5.filter { $0.hasPrefix("TextImport.") } == Self.v5TextImportColumns)
        #expect((v4 + Self.v5TextImportColumns).sorted() == v5)
        // Typed digest — minted 2026-08-19 by running this suite.
        #expect(Self.typedFingerprint(of: Schema(versionedSchema: IkeruSchemaV5.self))
                == "93c7f1726ba34d2a")
    }
}
