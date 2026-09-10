import Foundation
import SwiftData
import os

/// Attributes the dictionary entries and imported texts that have no owner yet
/// to a profile (IkeruSchemaV6, P1-1 / OBS2-022).
///
/// ## Where unowned rows come from
///
/// Two places, and both are expected rather than exceptional:
///
/// 1. **The V5→V6 migration.** It is `.lightweight`, so every existing row
///    arrives with `profileID == nil`. Nico's ruling (2026-09-09): those rows
///    go to the profile that is active when the updated app first launches —
///    the only defensible choice without an ownership history, and the right
///    one for the single-profile learner the app has almost exclusively had.
/// 2. **A pull from a device that still runs V5.** Its push sends
///    `profile_id = null`, and `SyncPullActor` inserts what it receives. Those
///    rows are adopted at the end of the same pull.
///
/// ## Why `updatedAt` is bumped
///
/// `SyncModelActor.isDirty` compares `updatedAt` to `syncedAt`. An adoption
/// that only wrote `profileID` would never reach the server, and a reinstall
/// would restore the rows with the null `profile_id` the server still holds —
/// and adopt them again into whatever profile happened to be active then.
///
/// ## What it does not do
///
/// It never re-attributes a row that already has an owner, and it leaves
/// tombstoned rows alone: a deleted row is pushed as a deletion whatever its
/// `profile_id`, and reading it back is the one thing nobody does.
///
/// Does **not** save — the caller owns the transaction, exactly like
/// `ProfileDeletion.tombstoneGraph`.
public enum OwnershipAdoption {

    public struct Result: Equatable, Sendable {
        public let entries: Int
        public let imports: Int

        public var isEmpty: Bool { entries == 0 && imports == 0 }
    }

    /// Assigns every live, unowned `VocabularyEntry` and `TextImport` to
    /// `profileID` and marks them dirty for the next push.
    @discardableResult
    public static func adoptUnownedRows(
        into profileID: UUID,
        in context: ModelContext,
        at now: Date = Date()
    ) throws -> Result {
        let entries = try context.fetch(FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.profileID == nil && $0.deletedAt == nil }
        ))
        for entry in entries {
            entry.profileID = profileID
            entry.updatedAt = now
        }

        let imports = try context.fetch(FetchDescriptor<TextImport>(
            predicate: #Predicate { $0.profileID == nil && $0.deletedAt == nil }
        ))
        for record in imports {
            record.profileID = profileID
            record.updatedAt = now
        }

        let result = Result(entries: entries.count, imports: imports.count)
        if !result.isEmpty {
            Logger.vocabulary.info(
                "Ownership adoption: \(result.entries) entries and \(result.imports) imports attributed to the active profile"
            )
        }
        return result
    }
}
