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
/// (`SettingsView.handleCloudSyncToggleChange`). **`CloudSyncTriggers.shared`
/// is the sole constructor of this type** — `start(modelContainer:)` builds
/// it once at launch, and `SettingsView` now asks
/// `CloudSyncTriggers.shared.sharedCoordinator(modelContainer:)` for that SAME
/// instance rather than building its own (fixed post-review: two live
/// coordinators over one `ModelContainer` each ran their own
/// `SyncPullActor`, and nothing stopped both from inserting the same
/// `ReviewLog` id — see `isSyncing` below for the other half of that fix).
/// Every initializer parameter here still defaults to its live
/// implementation regardless, so the pull/push transports and cursor store
/// MUST default to their live implementations — anything else would leave
/// production sync silently dormant regardless of what this type's tests
/// exercise.
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
        /// A `syncNow()` call arrived while this SAME actor instance was
        /// already mid-cycle — the `isSyncing` reentrance guard fired, not
        /// the `minSyncInterval` throttle. Kept distinct from
        /// `.skippedThrottled` rather than reusing it: this can legitimately
        /// happen well inside the throttle window (e.g. foreground trigger
        /// and a Settings toggle landing at the same instant), and a caller
        /// diagnosing "why didn't this push" benefits from knowing which
        /// guard actually fired.
        case skippedAlreadySyncing
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
        /// already-caught-up device). `skippedRowCount` and
        /// `permanentlyDroppedRowCount` surface `SyncPullActor.PullSummary`'s
        /// same-named totals — both `0` on a clean cycle; `syncNow()` uses
        /// them to set a calm, honest "restore incomplete" status distinct
        /// from both "up to date" and an outright pull failure (see
        /// `pullDegradedMessagePrefix`).
        case applied(rowCount: Int, skippedRowCount: Int, permanentlyDroppedRowCount: Int)
        /// The pull attempt threw — network error, a stalled cursor
        /// (`SyncPullActor.SyncPullActorError.cursorStalledOnFullPage`),
        /// etc. `message` is diagnostic only, same non-localized-copy
        /// contract as `SyncConsentStore.lastErrorMessage()`.
        case failed(String)
    }

    /// Marker prefix `SyncConsentStore.recordError` messages carry when the
    /// PUSH half of a cycle succeeded but the PULL half failed
    /// (post-review CRITICAL fix: `recordError(nil)` used to run
    /// unconditionally after a successful push, wiping any pull failure and
    /// leaving Settings claiming "up to date" while pulls stayed broken
    /// indefinitely). `SettingsView.cloudSyncStatusValue` checks for this
    /// prefix to show an honest, non-alarming status instead. Lives here
    /// (not as a second `SyncConsentStore` method) because that protocol is
    /// declared in `SyncPreferences.swift`, outside this lot's file
    /// perimeter — this reuses the existing single error slot rather than
    /// widening the protocol.
    public static let pullFailureMessagePrefix = "pull-failed: "

    /// Marker prefix for the "push succeeded, pull succeeded (or seeded),
    /// but some rows are stuck or were permanently abandoned" status —
    /// distinct from `pullFailureMessagePrefix` (the pull itself THREW)
    /// and from a clean cycle (no prefix, error slot cleared). Reuses the
    /// exact same single-error-slot mechanism `pullFailureMessagePrefix`
    /// established (see that constant's doc comment for why this lives
    /// here rather than widening `SyncConsentStore`) — this is the "point
    /// E/F/G" observability fix: before this existed, `PullSummary.skippedRowCounts`
    /// / `permanentlyDroppedRowCounts` were computed and read by nobody, so
    /// a table stuck on a poison row (see `SyncPullActor`'s poison-row
    /// policy) was completely invisible in production — the backup half of
    /// sync can be working perfectly while the restore half quietly limps.
    public static let pullDegradedMessagePrefix = "pull-degraded: "

    private let modelContainer: ModelContainer
    private let identity: AnonymousIdentityManager
    private let transport: any SyncDataTransport
    private let pullTransport: any SyncPullTransport
    private let cursorStore: any SyncCursorStore
    private let skipTracker: any SyncSkipTracker
    private let identityStore: any SyncIdentityStore
    private let consentStore: any SyncConsentStore
    private let minSyncInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var syncModelActor: SyncModelActor?
    private var syncPullActor: SyncPullActor?

    /// Real anti-reentrance guard for `syncNow()`, distinct from the
    /// `minSyncInterval` throttle below and from `CloudSyncTriggers` now
    /// handing out a single shared instance (see the type doc comment).
    /// Those two fixes stop two DIFFERENT actor instances — or the same
    /// instance called too soon after itself — from racing; neither stops
    /// two `syncNow()` calls that land on the SAME instance from
    /// interleaving mid-cycle. Swift actors are reentrant at every `await`:
    /// a second call arriving while the first is suspended (on the
    /// network, or inside `SyncPullActor`) would otherwise run its own
    /// pull/push pass concurrently with the first, over the same
    /// `ModelContainer` — the exact double-`ReviewLog`-insert risk this
    /// guard closes. A plain `Bool` is sufficient here specifically because
    /// every read/write of it below sits on either side of an `await`, never
    /// between one — so no other task can ever observe it mid-update.
    private var isSyncing = false

    /// Set by `setConsent(false)` when it fires WHILE `isSyncing` is true —
    /// honored in `syncNow()`'s `defer`, once the in-flight cycle is fully
    /// done writing cursors, rather than reset immediately (IMPORTANT C
    /// remediation).
    ///
    /// Swift actors are reentrant at every `await`: `setConsent` itself has
    /// no `await` in it, so it always runs start-to-finish without
    /// interleaving — but `syncNow()` has MANY, and `setConsent(false)` can
    /// be dispatched to this actor while `syncNow()` is suspended on one of
    /// them (a network call, `SyncPullActor`'s SwiftData work). Resetting
    /// `cursorStore` immediately in that case used to be silently undone:
    /// the in-flight cycle would resume moments later and keep calling
    /// `cursorStore.setCursor`/`advanceCursor` per table as it finishes its
    /// OWN pull, leaving fresh, non-`nil` cursors sitting right on top of
    /// the reset that was supposed to have cleared them — consent was
    /// revoked, but the NEXT opt-back-in would see stale cursors and skip
    /// rule 1's cold-start guard, the exact hazard `setConsent`'s own doc
    /// comment on the (non-reentrant) reset already explains. Deferring the
    /// reset until the in-flight cycle's `defer` fires closes that window:
    /// whatever cursors that cycle wrote get wiped right back out
    /// afterward, deterministically, regardless of how the two calls
    /// interleaved.
    private var pendingCursorReset = false

    public init(
        modelContainer: ModelContainer,
        identity: AnonymousIdentityManager = AnonymousIdentityManager(),
        transport: any SyncDataTransport = PostgRESTSyncTransport(),
        pullTransport: any SyncPullTransport = PostgRESTPullTransport(),
        cursorStore: any SyncCursorStore = UserDefaultsSyncCursorStore(),
        skipTracker: any SyncSkipTracker = UserDefaultsSyncSkipTracker(),
        identityStore: any SyncIdentityStore = UserDefaultsSyncIdentityStore(),
        consentStore: any SyncConsentStore = UserDefaultsSyncConsentStore(),
        minSyncInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.identity = identity
        self.transport = transport
        self.pullTransport = pullTransport
        self.cursorStore = cursorStore
        self.skipTracker = skipTracker
        self.identityStore = identityStore
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
    ///
    /// Revoking consent (`enabled == false`) also resets every pull cursor
    /// (IMPORTANT 6 remediation). Without this, turning backup back on
    /// later — same device, same still-installed Keychain identity, or a
    /// freshly re-provisioned one after `CloudDataDeletionService` wiped the
    /// server — would resume pulling with STALE, non-nil cursors. That
    /// defeats `SyncPullActor`'s rule-1 cold-start guard
    /// (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`,
    /// `SyncPullActor.swift`): a genuinely fresh/empty server account would
    /// no longer look like a cold start, so the guard that stops an empty
    /// cloud from ever being read as "nothing to merge" (and, one push
    /// later, the guard that seeds the server FROM local instead of
    /// wrongly treating local as already represented) never fires. Resetting
    /// here makes the next opted-back-in pull a true cold start again.
    public func setConsent(_ enabled: Bool) {
        consentStore.setConsentGiven(enabled)
        if !enabled {
            if isSyncing {
                // A cycle is in flight on THIS instance right now — defer
                // the reset to `syncNow()`'s own `defer`, once that cycle
                // is done writing cursors, instead of resetting immediately
                // only to have it silently undone. See `pendingCursorReset`'s
                // doc comment for the full reentrance story.
                pendingCursorReset = true
            } else {
                cursorStore.resetAll()
                skipTracker.resetAll()
            }
        }
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
    /// call path currently does. Also refuses to run a second, overlapping
    /// cycle on this SAME instance — see `isSyncing`'s doc comment.
    ///
    /// - Parameter ignoringThrottle: Bypasses ONLY the `minSyncInterval`
    ///   time-window check above — `isSyncing` and the consent gate are
    ///   untouched, so this can never run two overlapping cycles or leak
    ///   data without consent. `false` by default; the one caller that
    ///   passes `true` is `NameEntryView.performRestoreSync()` (onboarding's
    ///   "I already have an account" restore), because that call is an
    ///   explicit, one-shot learner action — not a background trigger the
    ///   throttle exists to protect against — and the throttle's own outcome
    ///   (`.skippedThrottled`) reads to that screen as "still finishing up",
    ///   which is actively misleading when nothing is actually in flight.
    @discardableResult
    public func syncNow(ignoringThrottle: Bool = false) async -> SyncOutcome {
        guard consentStore.isConsentGiven() else { return .skippedConsentOff }
        guard !isSyncing else { return .skippedAlreadySyncing }

        let attemptTime = now()
        if !ignoringThrottle,
           let lastAttempt = consentStore.lastAttemptDate(),
           attemptTime.timeIntervalSince(lastAttempt) < minSyncInterval {
            return .skippedThrottled
        }

        isSyncing = true
        defer {
            isSyncing = false
            // Honor a consent revocation that arrived WHILE this cycle was
            // in flight — see `pendingCursorReset`'s doc comment. Runs
            // AFTER `isSyncing` flips back to `false` so a `setConsent`
            // call racing this very `defer` (vanishingly unlikely — this
            // block has no `await`, so nothing can interleave with it —
            // but not structurally impossible to reason about otherwise)
            // still sees a consistent `isSyncing` state.
            if pendingCursorReset {
                pendingCursorReset = false
                cursorStore.resetAll()
                skipTracker.resetAll()
            }
        }
        consentStore.recordAttempt(at: attemptTime)

        do {
            let accessToken = try await identity.validAccessToken()

            // IDENTITY RE-PROVISIONING GUARD (2026-08 lot-2 pull review,
            // round 4 CRITICAL). A rejected refresh token makes
            // `AnonymousIdentityManager` silently mint a brand-new
            // anonymous `user_id` (see that type's `currentSession()` doc
            // comment) — the server-side account behind THAT id is empty
            // by definition, even though THIS device's pull cursors are
            // still non-nil from the previous, now-orphaned account. Left
            // unchecked, `SyncPullActor`'s rule-1 cold-start guard
            // (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`)
            // can never fire in that state — a device that has already
            // synced always has non-nil cursors on every table — so the
            // pull below would read the fresh, empty account as "nothing
            // changed" rather than "nothing has EVER been pushed here."
            // `PullOutcome.seededFromLocal` (and the `markEverythingUnsynced()`
            // call below gated on it) would stay unreachable, and
            // cards/review_logs/vocabulary would silently never reach the
            // new account — only `profiles`/`rpg_states` (pushed
            // unconditionally every cycle) would, while `SettingsView`
            // keeps reporting "up to date" throughout.
            //
            // Comparing the identity manager's CURRENT `user_id` against
            // the one persisted the last time this method ran
            // (`SyncIdentityStore`) catches the mismatch here and resets
            // both `cursorStore` and `skipTracker` — the same pairing
            // `setConsent(false)` already uses, for the same reason (see
            // that method's doc comment: a stale skip-tracker strike count
            // surviving a cursor reset could drop a brand-new account's
            // row after inheriting strikes from a completely unrelated
            // previous account) — so the pull that follows genuinely IS a
            // cold start again, and rule 1's existing machinery takes it
            // from there unchanged.
            let currentUserID = try await identity.currentUserID()
            // Lot 3 (Apple linking): also true the cycle a LINKED session
            // switches this device onto a DIFFERENT, already-populated
            // account (matrix case (c) — the Apple ID was already linked to
            // someone else's account elsewhere). Read alongside the
            // `markEverythingUnsynced` call below — see its own comment for
            // why an identity change alone, regardless of WHICH of the two
            // causes produced it, is what that call is now conditioned on.
            var identityChangedThisCycle = false
            if let lastKnownUserID = identityStore.lastKnownUserID() {
                if lastKnownUserID != currentUserID {
                    cursorStore.resetAll()
                    skipTracker.resetAll()
                    identityStore.setLastKnownUserID(currentUserID)
                    identityChangedThisCycle = true
                }
            } else {
                // Nothing stored yet — a fresh install, OR a device
                // mid-history that simply never ran this check before this
                // fix shipped. Neither is a re-provisioning signal by
                // itself: recording without resetting is what keeps this
                // guard from wiping an already-seeded, perfectly healthy
                // cursor set the very first time it runs.
                identityStore.setLastKnownUserID(currentUserID)
            }

            // Pull BEFORE push (lot 2): merges/replays remote state into
            // the local store first, so the push below sends the
            // post-merge truth, not the pre-merge one. A pull failure is
            // swallowed into `PullOutcome.failed` rather than rethrown —
            // see `runPull`'s doc comment.
            let pullOutcome = await runPull(accessToken: accessToken)

            // IMPORTANT C, second half: consent can be revoked WHILE this
            // cycle was suspended inside `runPull` above (network I/O,
            // `SyncPullActor`'s SwiftData work) — `syncNow()` used to check
            // consent only at entry, so a mid-cycle revocation didn't stop
            // the 7 `pushDirty*` calls below from still running. That is
            // not a minor inefficiency: it means data left the device
            // AFTER the learner had already withdrawn consent to send it,
            // which is a consent violation, not just a UX rough edge.
            // Re-checking here, between pull and the first push call,
            // closes that window (a THIRD revocation, arriving mid-push
            // itself, is not closed by this — see the file's known-limits
            // notes — but every push call is a single non-cancellable
            // network request, so there is no later "between pushes" point
            // to re-check at without adding a check inside every one of
            // the 7 calls for a race this narrow).
            guard consentStore.isConsentGiven() else {
                return .skippedConsentOff
            }

            // CRITIQUE B: a pull that just seeded-from-local (rule 1: empty
            // remote account, populated local store) needs every local row
            // marked unsynced BEFORE the push below, or the push's delta
            // filters silently skip everything whose `syncedAt` still
            // points at a previous, now-gone server-side account — see
            // `SyncModelActor.markEverythingUnsynced()`'s doc comment for
            // the full failure mode this closes.
            //
            // Lot 3 fix: ALSO run this on ANY identity change this cycle,
            // not only when the pull happened to come back seeded-from-local.
            // `seededFromLocal` only fires when the NEW account is EMPTY —
            // true for a re-provisioned anonymous identity (lot 2's
            // original case), but matrix case (c) breaks that assumption:
            // an Apple ID already linked to a DIFFERENT, POPULATED account
            // switches `currentUserID` just the same, yet the pull above is
            // a perfectly normal `.applied` (rule 1 never fires — the
            // remote account is not empty). Without this, every local row
            // still carrying a `syncedAt` stamp from the OLD identity reads
            // as "already synced" forever and never reaches the new
            // account — only `profiles`/`rpg_states` would. Safe to call
            // unconditionally on every identity change: `markEverythingUnsynced`
            // is idempotent (see its own doc comment), and this runs AFTER
            // the pull above has already merged whatever the new account
            // actually had, so it cannot discard real remote data — it only
            // re-offers this device's local state to the push's delta
            // comparison below.
            if case .seededFromLocal = pullOutcome {
                try await modelActor().markEverythingUnsynced()
            } else if identityChangedThisCycle {
                try await modelActor().markEverythingUnsynced()
            }

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

            // Push itself just completed without throwing — that success is
            // real and must be recorded regardless of how the pull half
            // went (per-design: "ne pas dramatiser", a failed pull does not
            // put the backup itself in question).
            consentStore.recordSuccess(at: now())
            // But do NOT unconditionally wipe the error slot with
            // `recordError(nil)` here (CRITICAL fix): if the pull half of
            // THIS cycle failed, that failure must stay visible — silently
            // clearing it left `SettingsView` showing "up to date" while
            // pulls stayed broken indefinitely, with no signal anywhere
            // that the merge/replay half of sync was not actually running.
            // A degraded-but-not-failed pull (some rows stuck or
            // permanently dropped this cycle — see `pullDegradedMessagePrefix`)
            // gets its own, calmer status instead of either extreme. A
            // pull that is fully clean (or hit rule 1's `seededFromLocal`)
            // still clears any older error, same as before.
            switch pullOutcome {
            case .failed(let pullMessage):
                consentStore.recordError(Self.pullFailureMessagePrefix + pullMessage)
            case .applied(_, let skippedRowCount, let permanentlyDroppedRowCount)
                where skippedRowCount > 0 || permanentlyDroppedRowCount > 0:
                consentStore.recordError(
                    Self.pullDegradedMessagePrefix +
                        "\(skippedRowCount) row(s) stuck, \(permanentlyDroppedRowCount) permanently dropped this cycle"
                )
            default:
                consentStore.recordError(nil)
            }
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
                skipTracker: skipTracker,
                accessToken: accessToken
            )
            if summary.seededFromLocal {
                return .seededFromLocal
            }
            return .applied(
                rowCount: summary.totalApplied,
                skippedRowCount: summary.totalSkipped,
                permanentlyDroppedRowCount: summary.totalPermanentlyDropped
            )
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
