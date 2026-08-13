import Foundation
import SwiftData
import os

/// Public entry point for cloud-sync lot 1 (push-only, anonymous identity —
/// `docs/design-specs/2026-08-10-cloud-sync-design.md`, lot breakdown §10).
///
/// ### Consent vs. first-launch auth — how this lot resolves the contradiction
///
/// Task item 1 describes `signInAnonymously()` "at first launch"; item 5
/// requires nothing to leave the device before opt-in. Taken literally,
/// those conflict: minting a server-side anonymous user IS something
/// leaving the device, before consent exists. This type resolves it as
/// **zero network activity — auth included — until the learner turns the
/// Settings toggle on**; sign-in then happens lazily, on the FIRST
/// consented `syncNow()` call, via `AnonymousIdentityManager`. That's also
/// the only reading this lot's file perimeter permits: with no access to
/// app-lifecycle files (`IkeruApp.swift` etc.), there is no call site
/// available to trigger a first-launch sign-in even if the literal reading
/// were adopted.
///
/// ### The only live caller, today
///
/// Foreground/session-end/network-regain triggers (design spec §5.2) are
/// NOT wired — those call sites live in app-lifecycle / session files
/// outside this lot's perimeter (`Ikeru/Views/Settings/SettingsView.swift`
/// is the only app-target file in scope, for a status row). The Settings
/// cloud-sync toggle turning ON is, as shipped, the ONLY call path that
/// invokes `syncNow()` — see that view's `cloudSyncToggleRow` /
/// `handleCloudSyncToggleChange`. This is declared in this task's final
/// notes; treat it as an open integration item for a follow-up lot, not as
/// "the triggers exist but are untested."
public actor CloudSyncCoordinator {

    public enum SyncOutcome: Sendable, Equatable {
        case skippedConsentOff
        case skippedThrottled
        case success(pushedRowCount: Int)
        case failure(String)
    }

    private let modelContainer: ModelContainer
    private let identity: AnonymousIdentityManager
    private let transport: any SyncDataTransport
    private let consentStore: any SyncConsentStore
    private let minSyncInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var syncModelActor: SyncModelActor?

    public init(
        modelContainer: ModelContainer,
        identity: AnonymousIdentityManager = AnonymousIdentityManager(),
        transport: any SyncDataTransport = PostgRESTSyncTransport(),
        consentStore: any SyncConsentStore = UserDefaultsSyncConsentStore(),
        minSyncInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.identity = identity
        self.transport = transport
        self.consentStore = consentStore
        self.minSyncInterval = minSyncInterval
        self.now = now
    }

    // MARK: - Consent

    public func isConsentGiven() -> Bool {
        consentStore.isConsentGiven()
    }

    /// Flips the opt-in flag only. Does NOT itself push — callers (the
    /// Settings toggle) decide whether/when to also call `syncNow()`, so
    /// "the learner said yes" and "a network request happened" stay two
    /// separately auditable events.
    public func setConsent(_ enabled: Bool) {
        consentStore.setConsentGiven(enabled)
    }

    // MARK: - Status (for an honest Settings row — task item 5)

    public func lastSuccessDate() -> Date? { consentStore.lastSuccessDate() }
    public func lastAttemptDate() -> Date? { consentStore.lastAttemptDate() }
    public func lastErrorMessage() -> String? { consentStore.lastErrorMessage() }

    // MARK: - Push

    /// Runs one push cycle across every synced, opted-in table. No-ops
    /// (returns `.skippedConsentOff`) when consent is off — this is the
    /// enforcement point for "rien ne part sans consentement", not just a
    /// UI-level gate. Throttled to at most once per `minSyncInterval`
    /// (default 60s) regardless of caller — cheap insurance against a
    /// caller invoking this in a loop, though nothing in this lot's shipped
    /// call path currently does.
    @discardableResult
    public func syncNow() async -> SyncOutcome {
        guard consentStore.isConsentGiven() else { return .skippedConsentOff }

        let attemptTime = now()
        if let lastAttempt = consentStore.lastAttemptDate(),
           attemptTime.timeIntervalSince(lastAttempt) < minSyncInterval {
            return .skippedThrottled
        }
        consentStore.recordAttempt(at: attemptTime)

        do {
            let accessToken = try await identity.validAccessToken()
            let actor = modelActor()

            var pushedCount = 0
            pushedCount += try await actor.pushAllProfiles(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushAllRPGStates(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushDirtyCards(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushDirtyReviewLogs(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushDirtyVocabularyEntries(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushDirtyVocabularyEncounters(using: transport, accessToken: accessToken)
            pushedCount += try await actor.pushDirtyExerciseOutcomeLogs(using: transport, accessToken: accessToken)
            // companion_chat_messages: intentionally never pushed by this
            // lot — see `SyncPayloadBuilder`'s trailing comment.

            consentStore.recordSuccess(at: now())
            consentStore.recordError(nil)
            return .success(pushedRowCount: pushedCount)
        } catch {
            let message = String(describing: error)
            consentStore.recordError(message)
            Logger.sync.error("Cloud sync push failed: \(message)")
            return .failure(message)
        }
    }

    private func modelActor() -> SyncModelActor {
        if let syncModelActor { return syncModelActor }
        let actor = SyncModelActor(modelContainer: modelContainer)
        syncModelActor = actor
        return actor
    }
}
