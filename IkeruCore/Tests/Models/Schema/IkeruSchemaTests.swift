import Testing
import SwiftData
@testable import IkeruCore

@Suite("Schema versioning & migration plan")
struct IkeruSchemaTests {

    @Test("V1 enumerates exactly the 10 persisted models")
    func v1ModelCount() {
        // Bump this and add an IkeruSchemaV2 + stage when the schema changes —
        // never silently grow V1. See IkeruSchema.swift.
        #expect(IkeruSchemaV1.models.count == 10)
    }

    @Test("V1 version identifier is 1.0.0")
    func v1Version() {
        #expect(IkeruSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("Migration plan is well-formed: stages == schemas - 1")
    func planWellFormed() {
        #expect(IkeruMigrationPlan.schemas.count == 1)
        #expect(IkeruMigrationPlan.stages.count == IkeruMigrationPlan.schemas.count - 1)
    }

    @Test("A container opens with the versioned schema + migration plan")
    func containerOpensWithPlan() throws {
        let schema = Schema(versionedSchema: IkeruSchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: IkeruMigrationPlan.self,
            configurations: [config]
        )
        // Every declared model resolves to exactly one schema entity — a guard
        // against a model being dropped from (or duplicated in) V1.
        #expect(container.schema.entities.count == IkeruSchemaV1.models.count)
    }
}
