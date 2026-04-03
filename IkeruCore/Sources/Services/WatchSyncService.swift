import Foundation
import os

// MARK: - Watch Sync Payload

/// Data payload for iPhone ↔ Watch synchronization.
/// Serializable to/from dictionary for WCSession transfer.
public struct WatchSyncPayload: Codable, Sendable {

    /// Total XP at time of sync.
    public let xp: Int

    /// Current level at time of sync.
    public let level: Int

    /// Total reviews completed.
    public let totalReviews: Int

    /// Number of cards due for review.
    public let dueCardCount: Int

    /// Timestamp of this payload (for conflict resolution).
    public let timestamp: Date

    /// Source device that generated this payload.
    public let source: SyncSource

    public init(
        xp: Int,
        level: Int,
        totalReviews: Int,
        dueCardCount: Int,
        timestamp: Date = Date(),
        source: SyncSource
    ) {
        self.xp = xp
        self.level = level
        self.totalReviews = totalReviews
        self.dueCardCount = dueCardCount
        self.timestamp = timestamp
        self.source = source
    }

    public enum SyncSource: String, Codable, Sendable {
        case iPhone
        case watch
    }

    // MARK: - Dictionary Conversion

    /// Converts to a dictionary suitable for WCSession applicationContext.
    public func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Parses from a WCSession dictionary.
    public static func fromDictionary(_ dict: [String: Any]) -> WatchSyncPayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSyncPayload.self, from: data)
    }
}

// MARK: - Watch Session Result

/// Result of a Watch nano-session to be synced back to iPhone.
public struct WatchSessionResult: Codable, Sendable {

    /// Number of questions answered correctly.
    public let correctCount: Int

    /// Total questions in the session.
    public let totalQuestions: Int

    /// Type of drill completed.
    public let drillType: DrillType

    /// When the session completed.
    public let completedAt: Date

    /// XP earned from this session.
    public let xpEarned: Int

    public init(
        correctCount: Int,
        totalQuestions: Int,
        drillType: DrillType,
        completedAt: Date = Date(),
        xpEarned: Int
    ) {
        self.correctCount = correctCount
        self.totalQuestions = totalQuestions
        self.drillType = drillType
        self.completedAt = completedAt
        self.xpEarned = xpEarned
    }

    public enum DrillType: String, Codable, Sendable {
        case kanaQuiz
        case pitchAccent
    }

    /// Converts to a dictionary suitable for WCSession transferUserInfo.
    public func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Parses from a WCSession dictionary.
    public static func fromDictionary(_ dict: [String: Any]) -> WatchSessionResult? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSessionResult.self, from: data)
    }
}

// MARK: - Sync Conflict Resolution

/// Pure-function conflict resolution for Watch ↔ iPhone sync.
/// Uses timestamp-based last-write-wins strategy.
public enum SyncConflictResolver {

    /// Resolves which payload should be used when both devices have state.
    /// - Parameters:
    ///   - local: The local device's payload.
    ///   - remote: The remote device's payload.
    /// - Returns: The winning payload (most recent timestamp wins).
    public static func resolve(
        local: WatchSyncPayload,
        remote: WatchSyncPayload
    ) -> WatchSyncPayload {
        if remote.timestamp > local.timestamp {
            Logger.sync.info("Sync conflict: remote wins (remote=\(remote.source.rawValue), \(remote.timestamp))")
            return remote
        } else {
            Logger.sync.info("Sync conflict: local wins (local=\(local.source.rawValue), \(local.timestamp))")
            return local
        }
    }
}
