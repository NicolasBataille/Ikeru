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
/// wired from `Ikeru/Services/CloudSyncTriggers.swift` (foreground +
/// network-regain; session-end is provided but not yet called — see that
/// type's doc comment), plus the Settings cloud-sync toggle turning ON
/// (`SettingsView.handleCloudSyncToggleChange`). Both construct this type
/// with every initializer parameter defaulted, so the pull/push transports
/// and cursor store below MUST default to their live implementations —
/// anything else would leave production sync silently dormant regardless
/// of what this type's tests exercise.
///
/// ### Pull runs before push — lot 2
///
/// `syncNow()` pulls first, then pushes, so a merged/replayed local state
/// (rules 2/3 in `SyncMergeRules`) is what actually gets pushed back up in
/// the same cycle, rather than the pre-merge state. A pull FAILURE does
/// **not** abort the push that follows it — see `runPull`'s doc comment for
/// why that's a deliberate, not an accidental, choice.
public actor CloudSyncCoordinator {

    public enum SyncOutcome: Sendable, Equatable {
        case skippedConsentOff
        case skippedThrottled
        case success(pushedRowCount: Int, pull: PullOutcome)
        case failure(String)
    }

    /// What the pull half of a `syncNow()` cycle did — kept distinct from
    /// `SyncOutcome` (the push half's own success/failure is always
    /// reported via `.success`/`.failure`, never folded into this) because
    /// a pull failure does not, by itself, fail the overall sync — see
    /// `runPull`.
    public enum PullOutcome: Sendable, Equatable {
        /// Rule 1 fired: the account was brand new (empty on every synced
        /// table) and this device had local data, so nothing was pulled —
        /// the push that follows this in `syncNow()` seeds the server
        /// instead.
        case seededFromLocal
        /// The normal path: `rowCount` rows were created or updated locally
        /// across every pulled table this cycle (may be `0` on an
        /// already-caught-up device).
        case applied(rowCount: Int)
        /// The pull attempt threw — network error, a stalled cursor
        /// (`SyncPullActor.SyncPullActorError.cursorStalledOnFullPage`),
        /// etc. `message` is diagnostic only, same non-localized-copy
        /// contract as `SyncConsentStore.lastErrorMessage()`.
        case failed(String)
    }

    private let modelContainer: ModelContainer
    private let identity: AnonymousIdentityManager
    private let transport: any SyncDataTransport
    private let pullTransport: any SyncPullTransport
    private let cursorStore: any SyncCursorStore
    private let consentStore: any SyncConsentStore
    private let minSyncInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var syncModelActor: SyncModelActor?
    private var syncPullActor: SyncPullActor?

    public init(
        modelContainer: ModelContainer,
        identity: AnonymousIdentityManager = AnonymousIdentityManager(),
        transport: any SyncDataTransport = PostgRESTSyncTransport(),
        pullTransport: any SyncPullTransport = PostgRESTPullTransport(),
        cursorStore: any SyncCursorStore = UserDefaultsSyncCursorStore(),
        consentStore: any SyncConsentStore = UserDefaultsSyncConsentStore(),
        minSyncInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.identity = identity
        self.transport = transport
        self.pullTransport = pullTransport
        self.cursorStore = cursorStore
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

            // Pull BEFORE push (lot 2): merges/replays remote state into
            // the local store first, so the push below sends the
            // post-merge truth, not the pre-merge one. A pull failure is
            // swallowed into `PullOutcome.failed` rather than rethrown —
            // see `runPull`'s doc comment.
            let pullOutcome = await runPull(accessToken: accessToken)

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
            return .success(pushedRowCount: pushedCount, pull: pullOutcome)
        } catch {
            let message = String(describing: error)
            consentStore.recordError(message)
            Logger.sync.error("Cloud sync push failed: \(message)")
            return .failure(message)
        }
    }

    // MARK: - Pull

    /// Runs the pull half of one `syncNow()` cycle and reports what
    /// happened as a `PullOutcome` — never throws.
    ///
    /// A pull failure is deliberately NOT propagated to abort the push that
    /// follows it. Two reasons, not one:
    ///
    /// 1. **Local-first, per design spec §8.** A Supabase free-tier project
    ///    pauses after ~7 days idle; the spec is explicit that a sync
    ///    failure "doit être un non-événement pour l'apprenant." Push is
    ///    the backup half of this feature (lot 1) and stands entirely on
    ///    its own — it must not be held hostage to pull succeeding first.
    /// 2. **A push does not need a pull to have succeeded to be correct.**
    ///    Push only ever sends rows this device already knows are locally
    ///    dirty; a failed pull just means this cycle didn't learn about
    ///    remote changes yet, not that pushing local changes is unsafe.
    ///
    /// ⚠️ **Known cost of this ordering choice, stated plainly:** if pull
    /// fails and push then succeeds, this device's local tombstones/merges
    /// (rule 4) have NOT been reconciled against the server this cycle —
    /// the exact window "pull before push" exists to close re-opens until
    /// the next successful pull. Accepted as the lesser failure mode versus
    /// "one flaky pull request blocks the backup half of this feature
    /// entirely," not an oversight.
    private func runPull(accessToken: String) async -> PullOutcome {
        do {
            let actor = pullActor()
            let summary = try await actor.pullAll(
                transport: pullTransport,
                cursorStore: cursorStore,
                accessToken: accessToken
            )
            if summary.seededFromLocal {
                return .seededFromLocal
            }
            return .applied(rowCount: summary.totalApplied)
        } catch {
            let message = String(describing: error)
            Logger.sync.error("Cloud sync pull failed (push still proceeds): \(message)")
            return .failed(message)
        }
    }

    private func modelActor() -> SyncModelActor {
        if let syncModelActor { return syncModelActor }
        let actor = SyncModelActor(modelContainer: modelContainer)
        syncModelActor = actor
        return actor
    }

    private func pullActor() -> SyncPullActor {
        if let syncPullActor { return syncPullActor }
        let actor = SyncPullActor(modelContainer: modelContainer)
        syncPullActor = actor
        return actor
    }
}
