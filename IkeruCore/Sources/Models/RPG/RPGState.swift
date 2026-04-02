import Foundation
import SwiftData

/// Persistent RPG progression state for a user profile.
/// Tracks experience points, level, and total reviews completed.
@Model
public final class RPGState {

    /// Unique identifier for the RPG state
    public var id: UUID

    /// Total experience points earned
    public var xp: Int

    /// Current level
    public var level: Int

    /// Total number of reviews completed across all sessions
    public var totalReviewsCompleted: Int

    /// The user profile that owns this RPG state
    public var profile: UserProfile?

    public init(
        xp: Int = 0,
        level: Int = 1,
        totalReviewsCompleted: Int = 0
    ) {
        self.id = UUID()
        self.xp = xp
        self.level = level
        self.totalReviewsCompleted = totalReviewsCompleted
    }
}
