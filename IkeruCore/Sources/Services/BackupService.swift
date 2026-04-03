import Foundation
import os

// MARK: - Backup Snapshot

/// Complete snapshot of all learning data for backup/restore.
/// All-or-nothing: either the entire state is backed up or none of it.
public struct BackupSnapshot: Codable, Sendable {

    /// Schema version for forward compatibility.
    public let schemaVersion: Int

    /// When this backup was created.
    public let createdAt: Date

    /// Device name that created the backup.
    public let deviceName: String

    /// User profile data.
    public let profile: ProfileSnapshot

    /// SRS card data.
    public let cards: [CardSnapshot]

    /// Review history.
    public let reviews: [ReviewSnapshot]

    /// RPG progression state.
    public let rpgState: RPGSnapshot

    public init(
        profile: ProfileSnapshot,
        cards: [CardSnapshot],
        reviews: [ReviewSnapshot],
        rpgState: RPGSnapshot,
        deviceName: String = ""
    ) {
        self.schemaVersion = 1
        self.createdAt = Date()
        self.deviceName = deviceName
        self.profile = profile
        self.cards = cards
        self.reviews = reviews
        self.rpgState = rpgState
    }
}

// MARK: - Snapshot Types

public struct ProfileSnapshot: Codable, Sendable {
    public let displayName: String
    public let settings: ProfileSettingsSnapshot
    public let createdAt: Date

    public init(displayName: String, settings: ProfileSettingsSnapshot, createdAt: Date) {
        self.displayName = displayName
        self.settings = settings
        self.createdAt = createdAt
    }
}

public struct ProfileSettingsSnapshot: Codable, Sendable {
    public let desiredRetention: Double
    public let dailyNewCardLimit: Int
    public let dailyReviewLimit: Int
    public let reviewReminderEnabled: Bool
    public let reviewReminderHour: Int
    public let weeklyCheckInEnabled: Bool
    public let weeklyCheckInDay: Int
    public let weeklyCheckInHour: Int

    public init(
        desiredRetention: Double,
        dailyNewCardLimit: Int,
        dailyReviewLimit: Int,
        reviewReminderEnabled: Bool,
        reviewReminderHour: Int,
        weeklyCheckInEnabled: Bool,
        weeklyCheckInDay: Int,
        weeklyCheckInHour: Int
    ) {
        self.desiredRetention = desiredRetention
        self.dailyNewCardLimit = dailyNewCardLimit
        self.dailyReviewLimit = dailyReviewLimit
        self.reviewReminderEnabled = reviewReminderEnabled
        self.reviewReminderHour = reviewReminderHour
        self.weeklyCheckInEnabled = weeklyCheckInEnabled
        self.weeklyCheckInDay = weeklyCheckInDay
        self.weeklyCheckInHour = weeklyCheckInHour
    }
}

public struct CardSnapshot: Codable, Sendable {
    public let id: UUID
    public let front: String
    public let back: String
    public let type: String
    public let dueDate: Date
    public let easeFactor: Double
    public let interval: Int
    public let reps: Int
    public let lapseCount: Int
    public let leechFlag: Bool

    public init(
        id: UUID, front: String, back: String, type: String,
        dueDate: Date, easeFactor: Double, interval: Int,
        reps: Int, lapseCount: Int, leechFlag: Bool
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.type = type
        self.dueDate = dueDate
        self.easeFactor = easeFactor
        self.interval = interval
        self.reps = reps
        self.lapseCount = lapseCount
        self.leechFlag = leechFlag
    }
}

public struct ReviewSnapshot: Codable, Sendable {
    public let id: UUID
    public let cardId: UUID
    public let timestamp: Date
    public let grade: String
    public let responseTimeMs: Int

    public init(id: UUID, cardId: UUID, timestamp: Date, grade: String, responseTimeMs: Int) {
        self.id = id
        self.cardId = cardId
        self.timestamp = timestamp
        self.grade = grade
        self.responseTimeMs = responseTimeMs
    }
}

public struct RPGSnapshot: Codable, Sendable {
    public let xp: Int
    public let level: Int
    public let totalReviewsCompleted: Int
    public let totalSessionsCompleted: Int
    public let attributesData: Data?
    public let lootInventoryData: Data?
    public let lootBoxesData: Data?

    public init(
        xp: Int, level: Int, totalReviewsCompleted: Int, totalSessionsCompleted: Int,
        attributesData: Data?, lootInventoryData: Data?, lootBoxesData: Data?
    ) {
        self.xp = xp
        self.level = level
        self.totalReviewsCompleted = totalReviewsCompleted
        self.totalSessionsCompleted = totalSessionsCompleted
        self.attributesData = attributesData
        self.lootInventoryData = lootInventoryData
        self.lootBoxesData = lootBoxesData
    }
}

// MARK: - Backup Error

public enum BackupError: LocalizedError, Sendable {
    case iCloudUnavailable
    case quotaExceeded
    case serializationFailed(String)
    case restoreFailed(String)
    case noBackupFound

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            "iCloud is not available. Please sign in to iCloud in Settings."
        case .quotaExceeded:
            "iCloud storage is full. Please free up space."
        case .serializationFailed(let detail):
            "Failed to prepare backup data: \(detail)"
        case .restoreFailed(let detail):
            "Failed to restore backup: \(detail)"
        case .noBackupFound:
            "No backup found in iCloud."
        }
    }
}
