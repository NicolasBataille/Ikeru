import Foundation
import SwiftData

// MARK: - Message Role

/// Role of a companion chat message.
public enum CompanionMessageRole: String, Codable, Sendable {
    case user
    case companion
    case system
}

// MARK: - CompanionChatMessage

/// A single message in the companion chat, persisted via SwiftData.
@Model
public final class CompanionChatMessage {

    /// Unique identifier for the message.
    public var id: UUID

    /// Who sent the message.
    public var roleRawValue: String

    /// The raw content of the message (may contain inline tags).
    public var content: String

    /// When the message was created.
    public var createdAt: Date

    /// The profile this message belongs to.
    public var profileId: UUID

    // MARK: - Computed

    /// Typed role accessor.
    @Transient
    public var role: CompanionMessageRole {
        CompanionMessageRole(rawValue: roleRawValue) ?? .system
    }

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). Per spec
    // §7, chat history syncs only on a **separate opt-in** — not implemented
    // here, this lot only adds the columns everyone else gets. Nothing
    // reads or writes these yet; that wiring is a later lot.

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

    // MARK: - Init

    public init(
        role: CompanionMessageRole,
        content: String,
        profileId: UUID
    ) {
        self.id = UUID()
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = Date()
        self.profileId = profileId
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
