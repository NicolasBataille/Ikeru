import Foundation
import CloudKit
import SwiftData
import UIKit
import IkeruCore
import os

// MARK: - CloudBackupManager

/// Manages iCloud backup and restore of the full learning state.
/// Uses CloudKit for all-or-nothing backup/restore operations.
@MainActor
final class CloudBackupManager: ObservableObject {

    @Published private(set) var isBackingUp = false
    @Published private(set) var isRestoring = false
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var lastError: BackupError?

    /// Lazily resolved CKContainer — using a stored property crashes at init
    /// when the app has no iCloud entitlements. Lazy + try lets the manager
    /// degrade gracefully to "unavailable" when CloudKit isn't configured.
    private var _container: CKContainer?
    private var container: CKContainer? {
        if _container == nil {
            // CKContainer.default() throws if no container identifier is set in entitlements.
            // Wrap in a defensive check by first looking for the entitlement.
            if Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.icloud-container-identifiers") != nil {
                _container = CKContainer.default()
            }
        }
        return _container
    }
    private let recordType = "BackupSnapshot"
    private let recordID = CKRecord.ID(recordName: "ikeru-backup-latest")

    // MARK: - Backup

    /// Creates a full backup of all learning data to iCloud.
    func backup(modelContainer: ModelContainer) async {
        isBackingUp = true
        lastError = nil

        defer { isBackingUp = false }

        guard let ckContainer = container else {
            lastError = .iCloudUnavailable
            Logger.sync.warning("Backup skipped — CloudKit not configured")
            return
        }

        do {
            // Check iCloud availability
            let status = try await ckContainer.accountStatus()
            guard status == .available else {
                throw BackupError.iCloudUnavailable
            }

            // Create snapshot from SwiftData
            let snapshot = try createSnapshot(from: modelContainer)

            // Serialize to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)

            // Upload to CloudKit
            let record = CKRecord(recordType: recordType, recordID: recordID)
            record["snapshotData"] = data as NSData
            record["createdAt"] = snapshot.createdAt as NSDate
            record["schemaVersion"] = snapshot.schemaVersion as NSNumber

            let database = ckContainer.privateCloudDatabase
            do {
                try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                let existing = try await database.record(for: recordID)
                existing["snapshotData"] = data as NSData
                existing["createdAt"] = snapshot.createdAt as NSDate
                existing["schemaVersion"] = snapshot.schemaVersion as NSNumber
                try await database.save(existing)
            }

            lastBackupDate = snapshot.createdAt
            Logger.sync.info("Backup completed: \(data.count) bytes")
        } catch let error as BackupError {
            lastError = error
            Logger.sync.error("Backup failed: \(error.localizedDescription)")
        } catch {
            lastError = .serializationFailed(error.localizedDescription)
            Logger.sync.error("Backup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// Restores learning data from the most recent iCloud backup.
    /// This is destructive — replaces all local data.
    func restore(modelContainer: ModelContainer) async {
        isRestoring = true
        lastError = nil

        defer { isRestoring = false }

        guard let ckContainer = container else {
            lastError = .iCloudUnavailable
            Logger.sync.warning("Restore skipped — CloudKit not configured")
            return
        }

        do {
            let status = try await ckContainer.accountStatus()
            guard status == .available else {
                throw BackupError.iCloudUnavailable
            }

            let database = ckContainer.privateCloudDatabase
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch {
                throw BackupError.noBackupFound
            }

            guard let data = record["snapshotData"] as? Data else {
                throw BackupError.noBackupFound
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(BackupSnapshot.self, from: data)

            try applySnapshot(snapshot, to: modelContainer)

            lastBackupDate = snapshot.createdAt
            Logger.sync.info("Restore completed from backup dated \(snapshot.createdAt)")
        } catch let error as BackupError {
            lastError = error
            Logger.sync.error("Restore failed: \(error.localizedDescription)")
        } catch {
            lastError = .restoreFailed(error.localizedDescription)
            Logger.sync.error("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Last Backup

    /// Checks the date of the most recent backup.
    func checkLastBackup() async {
        guard let ckContainer = container else {
            lastBackupDate = nil
            return
        }
        do {
            let database = ckContainer.privateCloudDatabase
            let record = try await database.record(for: recordID)
            if let date = record["createdAt"] as? Date {
                lastBackupDate = date
            }
        } catch {
            lastBackupDate = nil
        }
    }

    // MARK: - Snapshot Creation

    private func createSnapshot(from container: ModelContainer) throws -> BackupSnapshot {
        let context = container.mainContext

        // Fetch profile
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let profile = profiles.first else {
            throw BackupError.serializationFailed("No profile found")
        }

        let profileSnapshot = ProfileSnapshot(
            displayName: profile.displayName,
            settings: ProfileSettingsSnapshot(
                desiredRetention: profile.settings.desiredRetention,
                dailyNewCardLimit: profile.settings.dailyNewCardLimit,
                dailyReviewLimit: profile.settings.dailyReviewLimit,
                reviewReminderEnabled: profile.settings.reviewReminderEnabled,
                reviewReminderHour: profile.settings.reviewReminderHour,
                weeklyCheckInEnabled: profile.settings.weeklyCheckInEnabled,
                weeklyCheckInDay: profile.settings.weeklyCheckInDay,
                weeklyCheckInHour: profile.settings.weeklyCheckInHour
            ),
            createdAt: profile.createdAt
        )

        // Fetch RPG state
        let rpgStates = (try? context.fetch(FetchDescriptor<RPGState>())) ?? []
        let rpg = rpgStates.first
        let rpgSnapshot = RPGSnapshot(
            xp: rpg?.xp ?? 0,
            level: rpg?.level ?? 1,
            totalReviewsCompleted: rpg?.totalReviewsCompleted ?? 0,
            totalSessionsCompleted: rpg?.totalSessionsCompleted ?? 0,
            attributesData: rpg?.attributesData,
            lootInventoryData: rpg?.lootInventoryData,
            lootBoxesData: rpg?.lootBoxesData
        )

        // Fetch all cards and their review logs
        let allCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let cardSnapshots = allCards.map { card in
            CardSnapshot(
                id: card.id,
                front: card.front,
                back: card.back,
                type: card.type.rawValue,
                dueDate: card.dueDate,
                easeFactor: card.easeFactor,
                interval: card.interval,
                reps: card.fsrsState.reps,
                lapseCount: card.lapseCount,
                leechFlag: card.leechFlag
            )
        }

        let reviewSnapshots = allCards.flatMap { card in
            (card.reviewLogs ?? []).map { log in
                ReviewSnapshot(
                    id: log.id,
                    cardId: card.id,
                    timestamp: log.timestamp,
                    grade: "\(log.gradeRawValue)",
                    responseTimeMs: log.responseTimeMs
                )
            }
        }

        return BackupSnapshot(
            profile: profileSnapshot,
            cards: cardSnapshots,
            reviews: reviewSnapshots,
            rpgState: rpgSnapshot,
            deviceName: UIDevice.current.model
        )
    }

    // MARK: - Snapshot Restore

    private func applySnapshot(_ snapshot: BackupSnapshot, to container: ModelContainer) throws {
        let context = container.mainContext

        // Update profile
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let profile = profiles.first {
            profile.displayName = snapshot.profile.displayName
            profile.settings = ProfileSettings(
                desiredRetention: snapshot.profile.settings.desiredRetention,
                dailyNewCardLimit: snapshot.profile.settings.dailyNewCardLimit,
                dailyReviewLimit: snapshot.profile.settings.dailyReviewLimit,
                reviewReminderEnabled: snapshot.profile.settings.reviewReminderEnabled,
                reviewReminderHour: snapshot.profile.settings.reviewReminderHour,
                weeklyCheckInEnabled: snapshot.profile.settings.weeklyCheckInEnabled,
                weeklyCheckInDay: snapshot.profile.settings.weeklyCheckInDay,
                weeklyCheckInHour: snapshot.profile.settings.weeklyCheckInHour
            )
        }

        // Update RPG state
        let rpgStates = (try? context.fetch(FetchDescriptor<RPGState>())) ?? []
        if let rpg = rpgStates.first {
            rpg.xp = snapshot.rpgState.xp
            rpg.level = snapshot.rpgState.level
            rpg.totalReviewsCompleted = snapshot.rpgState.totalReviewsCompleted
            rpg.totalSessionsCompleted = snapshot.rpgState.totalSessionsCompleted
            rpg.attributesData = snapshot.rpgState.attributesData
            rpg.lootInventoryData = snapshot.rpgState.lootInventoryData
            rpg.lootBoxesData = snapshot.rpgState.lootBoxesData
        }

        // Restore cards: delete existing cards, then re-create from snapshot
        let existingCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in existingCards {
            context.delete(card)
        }

        // Build a lookup for review snapshots by card ID
        var reviewsByCardId: [UUID: [ReviewSnapshot]] = [:]
        for review in snapshot.reviews {
            reviewsByCardId[review.cardId, default: []].append(review)
        }

        for cardSnap in snapshot.cards {
            let card = Card(
                front: cardSnap.front,
                back: cardSnap.back,
                type: CardType(rawValue: cardSnap.type) ?? .kanji,
                easeFactor: cardSnap.easeFactor,
                interval: cardSnap.interval,
                dueDate: cardSnap.dueDate,
                lapseCount: cardSnap.lapseCount,
                leechFlag: cardSnap.leechFlag
            )
            // Preserve original ID
            card.id = cardSnap.id
            context.insert(card)

            // Restore review logs for this card
            for reviewSnap in reviewsByCardId[cardSnap.id] ?? [] {
                let grade = Grade(rawValue: Int(reviewSnap.grade) ?? 3) ?? .good
                let log = ReviewLog(
                    card: card,
                    grade: grade,
                    responseTimeMs: reviewSnap.responseTimeMs,
                    timestamp: reviewSnap.timestamp
                )
                log.id = reviewSnap.id
                context.insert(log)
            }
        }

        do {
            try context.save()
        } catch {
            Logger.sync.error("Failed to save restored snapshot: \(error.localizedDescription)")
            throw BackupError.restoreFailed("Save failed: \(error.localizedDescription)")
        }
    }
}
