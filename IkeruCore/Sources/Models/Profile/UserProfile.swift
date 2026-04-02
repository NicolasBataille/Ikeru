import Foundation
import SwiftData

/// A user profile that owns all learning data.
/// Each profile maintains its own set of cards and associated review history.
@Model
public final class UserProfile {

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

    public init(
        displayName: String,
        settings: ProfileSettings = ProfileSettings()
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.createdAt = Date()
        self.settings = settings
        self.cards = []
    }
}
