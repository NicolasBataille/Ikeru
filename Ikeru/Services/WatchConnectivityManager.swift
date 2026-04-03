import Foundation
import WatchConnectivity
import SwiftData
import IkeruCore
import os

// MARK: - WatchConnectivityManager

/// Manages WatchConnectivity session on the iPhone side.
/// Sends RPG state updates to Watch and receives Watch session results.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    private var session: WCSession?
    private var modelContainer: ModelContainer?

    /// Pending session results received from Watch (queued while offline).
    @Published private(set) var pendingResults: [WatchSessionResult] = []

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Activates WatchConnectivity if supported.
    /// - Parameter container: The SwiftData model container for persisting received data.
    func activate(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard WCSession.isSupported() else {
            Logger.sync.info("WatchConnectivity not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        Logger.sync.info("WatchConnectivity session activated")
    }

    // MARK: - Send State to Watch

    /// Sends the current RPG state to the Watch via applicationContext.
    func sendStateToWatch() {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        guard let state = try? context.fetch(descriptor).first else { return }

        let cardRepo = CardRepository(modelContainer: container)
        Task { @MainActor in
            let dueCards = await cardRepo.dueCards(before: Date())

            let payload = WatchSyncPayload(
                xp: state.xp,
                level: state.level,
                totalReviews: state.totalReviewsCompleted,
                dueCardCount: dueCards.count,
                source: .iPhone
            )

            do {
                try session.updateApplicationContext(payload.toDictionary())
                Logger.sync.info("Sent state to Watch: level=\(state.level), xp=\(state.xp)")
            } catch {
                Logger.sync.error("Failed to send state to Watch: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Process Watch Results

    /// Processes a Watch session result by awarding XP and persisting.
    private func processWatchResult(_ result: WatchSessionResult) {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<RPGState>()

        guard let state = try? context.fetch(descriptor).first else { return }

        state.xp += result.xpEarned
        state.level = RPGConstants.levelForXP(state.xp)
        state.totalReviewsCompleted += result.totalQuestions

        do {
            try context.save()
        } catch {
            Logger.sync.error("Failed to save Watch session result: \(error.localizedDescription)")
        }
        Logger.sync.info(
            "Processed Watch session: +\(result.xpEarned) XP, drill=\(result.drillType.rawValue)"
        )

        // Send updated state back to Watch
        sendStateToWatch()
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Logger.sync.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            Logger.sync.info("WCSession activated: \(activationState.rawValue)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Logger.sync.info("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Logger.sync.info("WCSession deactivated — reactivating")
        session.activate()
    }

    /// Receives queued Watch session results via transferUserInfo.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let result = WatchSessionResult.fromDictionary(userInfo) else {
            Logger.sync.warning("Received unrecognized userInfo from Watch")
            return
        }

        Task { @MainActor in
            processWatchResult(result)
        }
    }

    /// Receives application context updates from Watch.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = WatchSyncPayload.fromDictionary(applicationContext) else {
            Logger.sync.warning("Received unrecognized applicationContext from Watch")
            return
        }

        Logger.sync.info("Received state from Watch: level=\(payload.level), xp=\(payload.xp)")

        Task { @MainActor in
            guard let container = modelContainer else { return }
            let context = container.mainContext
            let descriptor = FetchDescriptor<RPGState>()
            guard let state = try? context.fetch(descriptor).first else { return }

            let localPayload = WatchSyncPayload(
                xp: state.xp,
                level: state.level,
                totalReviews: state.totalReviewsCompleted,
                dueCardCount: 0,
                source: .iPhone
            )

            let winner = SyncConflictResolver.resolve(local: localPayload, remote: payload)
            if winner.source == .watch {
                state.xp = winner.xp
                state.level = winner.level
                state.totalReviewsCompleted = winner.totalReviews
                do {
                    try context.save()
                } catch {
                    Logger.sync.error("Failed to save synced Watch state: \(error.localizedDescription)")
                }
                Logger.sync.info("Applied Watch state: level=\(winner.level), xp=\(winner.xp)")
            }
        }
    }
}
