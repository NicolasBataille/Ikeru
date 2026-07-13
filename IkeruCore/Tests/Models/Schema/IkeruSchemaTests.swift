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
}
