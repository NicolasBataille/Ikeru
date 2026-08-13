import Foundation
import SwiftData

/// A user profile that owns all learning data.
/// Each profile maintains its own set of cards and associated review history.
@Model
public final class UserProfile: Identifiable {

    /// UserDefaults key holding the currently-active profile id (UUID string).
    /// Referenced by both the app layer's `ActiveProfileResolver` and the core
    /// layer's `CardModelActor` for per-profile scoping without plumbing.
    public static let activeProfileIDDefaultsKey = "ikeru.activeProfileID"

    /// Unique identifier for the profile
    public var id: UUID

    /// Display name for the user
    public var displayName: String

    /// When the profile was created
    public var createdAt: Date

    /// User-configurable learning settings
    public var settings: ProfileSettings

    /// All cards belonging to this profile
    @Relationship(deleteRule: .cascade, inverse: \Card.profile)
    public var cards: [Card]?

    /// RPG progression state for this profile
    @Relationship(deleteRule: .cascade, inverse: \RPGState.profile)
    public var rpgState: RPGState?

    // MARK: - Cloud sync (schema-only, lot 0)
    //
    // Added by `IkeruSchemaV4` (cloud-sync lot 0, see
    // `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). Nothing
    // reads or writes these yet — no repository bumps `updatedAt` on
    // mutation, nothing sets `deletedAt`, nothing sets `syncedAt`. That
    // wiring is a later lot; this lot only adds the columns.

    /// Local modification clock. Defaults to the Unix epoch at the property
    /// level so the `.lightweight` V3→V4 migration can backfill existing
    /// rows without a custom stage; every initializer below sets this to
    /// `Date()` explicitly for freshly created objects.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Tombstone. Non-nil means this row was locally deleted and awaits a
    /// sync push of the deletion.
    public var deletedAt: Date?

    /// Timestamp of the last confirmed push to the sync server. `nil` means
    /// never synced.
    public var syncedAt: Date?

    public init(
        displayName: String,
        settings: ProfileSettings = ProfileSettings()
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.createdAt = Date()
        self.settings = settings
        self.cards = []
        self.rpgState = RPGState()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}
