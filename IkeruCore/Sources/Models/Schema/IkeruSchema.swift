import SwiftData

// MARK: - Versioned Schema

/// Versioned baseline of the app's persisted SwiftData schema.
///
/// This is **V1** — the schema exactly as it ships today (the 10 `@Model`
/// types below). Its only job right now is to establish the migration
/// infrastructure: once a `SchemaMigrationPlan` is attached to the
/// `ModelContainer`, any future model change can be expressed as an explicit
/// `IkeruSchemaV2` + a `MigrationStage`, instead of relying on SwiftData's
/// implicit lightweight migration — which silently succeeds for additive
/// changes but can drop data (or fail to open the store) on incompatible ones.
///
/// - Important: `IkeruSchemaV1.models` must stay byte-identical to the shape
///   already on TestFlight users' devices. **Never edit V1** to reflect a new
///   model change — add an `IkeruSchemaV2` and a stage between them instead.
public enum IkeruSchemaV1: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
        ]
    }
}

// MARK: - Versioned Schema V2

/// **V2** — adds the `ExerciseOutcomeLog` entity (remediation 4.4): persisted
/// outcomes of pool-based output drills (listening / shadowing) that have no
/// backing FSRS `Card`.
///
/// The change is purely additive: a brand-new entity whose only cross-entity
/// reference is a scalar `profileID: UUID` (not a SwiftData relationship), so no
/// existing V1 entity — `UserProfile` included — changes shape. That makes the
/// V1→V2 stage `.lightweight`-safe.
///
/// - Important: this copies V1's ten models verbatim and appends the new one.
///   V1 stays frozen; never edit it.
public enum IkeruSchemaV2: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
            ExerciseOutcomeLog.self,
        ]
    }
}

// MARK: - Migration Plan

/// The app's schema migration plan.
///
/// Currently a single baseline version (`IkeruSchemaV1`) with no stages, so it
/// is a no-op for existing stores — the on-disk schema already matches V1, so
/// attaching this plan changes nothing for current users while giving future
/// changes a migration path.
///
/// When a `@Model` changes shape, add an `IkeruSchemaV2` (copying V1's models
/// with the change applied) and append a `MigrationStage` here:
///
/// ```swift
/// public static var schemas: [any VersionedSchema.Type] {
///     [IkeruSchemaV1.self, IkeruSchemaV2.self]
/// }
/// public static var stages: [MigrationStage] {
///     [.lightweight(fromVersion: IkeruSchemaV1.self, toVersion: IkeruSchemaV2.self)]
/// }
/// ```
///
/// Use `.custom(...)` instead of `.lightweight(...)` when a change needs data
/// transformation (renames with data preservation, split/merge fields, etc.).
public enum IkeruMigrationPlan: SchemaMigrationPlan {

    public static var schemas: [any VersionedSchema.Type] {
        [IkeruSchemaV1.self, IkeruSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        // V1 → V2 adds only the `ExerciseOutcomeLog` entity (no changes to any
        // existing entity), so a lightweight stage is sufficient and safe: it
        // adds the new table and leaves all V1 data untouched.
        [.lightweight(fromVersion: IkeruSchemaV1.self, toVersion: IkeruSchemaV2.self)]
    }
}
