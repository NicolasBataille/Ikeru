#if os(iOS)
import Foundation
import ActivityKit

/// ActivityKit attributes for the study session Live Activity.
/// Displayed on Dynamic Island and Lock Screen during active sessions.
public struct SessionActivityAttributes: ActivityAttributes {

    /// Static context that doesn't change during the activity.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Elapsed time in seconds.
        public let elapsedSeconds: Int

        /// Current exercise type description.
        public let exerciseType: String

        /// Number of exercises completed.
        public let completedCount: Int

        /// Total exercises in the session.
        public let totalCount: Int

        /// Current XP earned this session.
        public let xpEarned: Int

        /// Current streak count (consecutive correct).
        public let streakCount: Int

        /// Progress fraction (0.0 to 1.0).
        public var progressFraction: Double {
            guard totalCount > 0 else { return 0 }
            return Double(completedCount) / Double(totalCount)
        }

        public init(
            elapsedSeconds: Int,
            exerciseType: String,
            completedCount: Int,
            totalCount: Int,
            xpEarned: Int,
            streakCount: Int
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.exerciseType = exerciseType
            self.completedCount = completedCount
            self.totalCount = totalCount
            self.xpEarned = xpEarned
            self.streakCount = streakCount
        }
    }

    /// Session display title (not dynamic).
    public let sessionTitle: String

    public init(sessionTitle: String = "Study Session") {
        self.sessionTitle = sessionTitle
    }
}
#endif
