import Foundation
import SwiftData

/// A log entry recording where and when a vocabulary word was encountered.
@Model
public final class VocabularyEncounter {

    /// Unique identifier for this encounter.
    public var id: UUID

    /// Timestamp of the encounter.
    public var timestamp: Date

    /// Raw value storage for EncounterSource (used in SwiftData predicates).
    public var sourceRawValue: String

    /// Where in the app the word was encountered.
    public var source: EncounterSource {
        get { EncounterSource(rawValue: sourceRawValue) ?? .sakuraChat }
        set { sourceRawValue = newValue.rawValue }
    }

    /// The sentence or context where the word appeared.
    public var contextSnippet: String

    /// The vocabulary entry this encounter belongs to.
    public var entry: VocabularyEntry?

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1).
    // `VocabularyEncounter` is append-only per spec §3 (conflict-free by
    // construction), but it still needs `updatedAt`/`syncedAt` to drive the
    // push delta — `deletedAt` is carried for schema symmetry even though an
    // encounter log is never expected to be soft-deleted in practice.
    // Nothing reads or writes any of the three yet; that wiring is a later
    // lot.

    /// Local modification clock. Defaults to the Unix epoch at the property
    /// level so the `.lightweight` V3→V4 migration can backfill existing
    /// rows without a custom stage; the initializer below sets this to
    /// `Date()` explicitly for freshly created objects.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Tombstone. Non-nil means this row was locally deleted and awaits a
    /// sync push of the deletion.
    public var deletedAt: Date?

    /// Timestamp of the last confirmed push to the sync server. `nil` means
    /// never synced.
    public var syncedAt: Date?

    public init(
        source: EncounterSource,
        contextSnippet: String,
        entry: VocabularyEntry,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sourceRawValue = source.rawValue
        self.contextSnippet = contextSnippet
        self.entry = entry
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
