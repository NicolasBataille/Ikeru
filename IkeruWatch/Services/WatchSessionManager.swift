import Foundation
import WatchConnectivity
import WatchKit
import IkeruCore
import os

// MARK: - WatchSessionManager

/// Manages WatchConnectivity on the Watch side.
/// Receives state from iPhone and sends session results back.
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    /// Latest synced RPG state from iPhone.
    @Published private(set) var syncedXP: Int = 0
    @Published private(set) var syncedLevel: Int = 1
    @Published private(set) var syncedDueCards: Int = 0

    /// Pending session results to send when connectivity is restored.
    private var pendingResults: [WatchSessionResult] = []

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        Logger.sync.info("Watch WCSession activated")
    }

    // MARK: - Send Results to iPhone

    /// Sends a completed nano-session result to iPhone.
    /// Uses transferUserInfo for guaranteed delivery (queued if offline).
    func sendSessionResult(_ result: WatchSessionResult) {
        guard WCSession.default.activationState == .activated else {
            pendingResults.append(result)
            Logger.sync.info("Queued session result (offline): \(result.drillType.rawValue)")
            return
        }

        WCSession.default.transferUserInfo(result.toDictionary())
        Logger.sync.info("Sent session result: \(result.drillType.rawValue), +\(result.xpEarned) XP")
    }

    /// Flushes any pending results when connectivity is restored.
    private func flushPendingResults() {
        guard !pendingResults.isEmpty else { return }
        Logger.sync.info("Flushing \(self.pendingResults.count) pending results")
        for result in pendingResults {
            WCSession.default.transferUserInfo(result.toDictionary())
        }
        pendingResults.removeAll()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Logger.sync.error("Watch WCSession failed: \(error.localizedDescription)")
        } else {
            Logger.sync.info("Watch WCSession activated: \(activationState.rawValue)")
            flushPendingResults()
        }
    }

    /// Receives application context from iPhone (latest RPG state).
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = WatchSyncPayload.fromDictionary(applicationContext) else {
            Logger.sync.warning("Watch received unrecognized applicationContext")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.syncedXP = payload.xp
            self?.syncedLevel = payload.level
            self?.syncedDueCards = payload.dueCardCount
        }

        Logger.sync.info("Watch received state: level=\(payload.level), xp=\(payload.xp)")
    }
}
