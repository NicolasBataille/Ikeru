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
    }
}
