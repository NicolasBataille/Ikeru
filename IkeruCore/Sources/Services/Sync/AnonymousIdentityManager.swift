import Foundation
import os

/// Local Keychain key for the persisted `SyncSession` JSON. Lives here
/// (not in `KeychainKeys`, `Utilities/KeychainHelper.swift`) — this lot's
/// file perimeter excludes that file, and a distinct raw string key needs no
/// coordination with it.
///
/// `public`: referenced as a default-argument value on `AnonymousIdentityManager`'s
/// public initializer below, and Swift requires default-argument values to be
/// at least as visible as the initializer itself.
public enum SyncKeychainKeys {
    public static let session = "com.ikeru.cloudsync.session"
}

// MARK: - Apple identity linking outcomes (lot 3)

/// What `AnonymousIdentityManager.linkOrSignInWithApple` actually did — the
/// UI layer (`Ikeru/Services/…`, the ASAuthorization flow) reads this to
/// decide what to tell the learner. See that method's doc comment for the
/// full decision tree each case corresponds to.
public enum AppleLinkOutcome: Sendable, Equatable {
    /// Matrix case (a) — this device's EXISTING session now also has an
    /// Apple identity attached, under the SAME `user_id` as before. Nothing
    /// about this device's already-synced data changes meaning; the next
    /// `CloudSyncCoordinator.syncNow()` sees no identity change.
    case linkedExistingIdentity(userID: UUID)
    /// Matrix cases (b) and (c) — this device is now authenticated as a
    /// DIFFERENT `user_id` than whatever it had before (or had nothing at
    /// all). `wasAlreadyLinkedElsewhere` distinguishes a genuinely fresh
    /// install/first sign-in (`false`) from an already-anonymous device
    /// whose Apple ID turned out to already belong to a separate, existing
    /// account (`true`) — `CloudSyncCoordinator`'s existing identity-change
    /// detection treats both identically on the next `syncNow()` (full
    /// re-sync, cursors reset, local rows always re-offered — see that
    /// type's `markEverythingUnsynced` handling).
    case switchedIdentity(userID: UUID, wasAlreadyLinkedElsewhere: Bool)
    /// This device's PREVIOUS session had its refresh token explicitly
    /// REJECTED by the server (dead, not just unreachable — see
    /// `currentSession()`'s demotion guard below), so this call was treated
    /// as if no local session existed and signed in fresh, no
    /// `link_identity`. `userID` may equal the previous linked identity
    /// (the common, intended case: reconnecting as yourself after a dead
    /// session) or differ (a dead ANONYMOUS session simply starting over) —
    /// callers must not assume either without comparing against what they
    /// already knew.
    case reauthenticatedAfterDeadSession(userID: UUID)
}

/// The single most important error type in lot 3 — see
/// `AnonymousIdentityManager.linkOrSignInWithApple`'s doc comment.
public enum AppleLinkError: Error, Sendable, Equatable {
    /// `linkAppleIdentity` returned HTTP 2xx, but for a DIFFERENT `user_id`
    /// than the one this call was made to preserve. Never adopted, never
    /// silently treated as success — see the guard's doc comment at the
    /// call site for exactly why.
    case linkIdentityGuardTripped
}

/// Owns the device's anonymous Supabase identity: signs in on first use,
/// persists the session to Keychain, and refreshes it transparently.
///
/// **Never called except from within `CloudSyncCoordinator.syncNow()`**,
/// which itself only runs after the learner has opted in — see that type's
/// doc comment for why "sign in at first launch" (task item 1) and "nothing
/// leaves until opt-in" (task item 5) are reconciled as *lazy* sign-in
/// gated by consent, not an unconditional first-launch call. This actor
/// itself has no opinion on consent — it just makes talking to Supabase
/// Auth safe and idempotent whenever a caller decides to.
public actor AnonymousIdentityManager {

    private let transport: any SupabaseAuthTransport
    private let keychain: any KeychainStore
    private let sessionKey: String
    /// Where the `wasLinked` marker lives (Critique #1, lot 3) —
    /// `UserDefaults`-backed by default, deliberately a SEPARATE concern
    /// from `CloudSyncCoordinator`'s own `identityStore` param (that one
    /// tracks `lastKnownUserID` for the re-provisioning guard; this one
    /// tracks "has this device ever held a linked session"). Both may
    /// point at the same real `UserDefaults.standard` suite in production
    /// — different keys, no collision — but tests MUST inject their own
    /// `MockSyncIdentityStore` here, never rely on the default: it reads
    /// real `UserDefaults.standard`, which persists across test runs in
    /// the same process (see `MockSyncIdentityStore`'s own doc comment).
    private let identityStore: any SyncIdentityStore

    private var cachedSession: SyncSession?

    /// Bumped by every call that deliberately erases this actor's Keychain
    /// session — `signOut()` and `forgetSessionAfterAccountDeletion()` — so
    /// a token refresh suspended on the network can tell, once it resumes,
    /// whether one of those ran while it was away.
    ///
    /// Same shape of problem `CloudSyncCoordinator.pendingCursorReset`
    /// exists for (see that property's doc comment), but the fix runs in
    /// the opposite direction: `pendingCursorReset` lets an in-flight cycle
    /// finish and THEN applies the pending reset. Here there is nothing to
    /// defer — `signOut()`'s own Keychain delete + `wasLinked` reset are
    /// synchronous and complete immediately, in full, the moment they run
    /// (actors are only reentrant at `await`, and neither `signOut()` nor
    /// `forgetSessionAfterAccountDeletion()` awaits anything). The hazard is
    /// the SUSPENDED caller instead: `existingSyncSession()`/`currentSession()`
    /// read a stored session, `await transport.refreshSession(...)`, and
    /// only then call `persist()` — Keychain write plus, for a linked
    /// session, `identityStore.setWasLinked(true)`. If a sign-out lands
    /// during that `await`, the eventual `persist()` would silently
    /// resurrect exactly what sign-out just deleted, undoing it with no
    /// error and no trace (2026-08 sign-out remediation — the same
    /// enforced-consent kind of gap `AppleSignInFlow`'s doc comment on
    /// `cloudSyncConsentEnabled` describes, one call site over).
    ///
    /// Capturing this counter immediately before the `await` and comparing
    /// it immediately after closes that window: a mismatch means one of the
    /// two erasing calls ran to completion in between, so the refreshed
    /// session must be treated as stale and discarded rather than persisted.
    /// A plain `Int` is sufficient — every read/write of it sits on either
    /// side of an `await`, never between one, so no two callers can ever
    /// observe or update it mid-change.
    private var identityGeneration = 0

    public init(
        transport: any SupabaseAuthTransport = URLSessionSupabaseAuthTransport(),
        keychain: any KeychainStore = KeychainHelper(),
        sessionKey: String = SyncKeychainKeys.session,
        identityStore: any SyncIdentityStore = UserDefaultsSyncIdentityStore()
    ) {
        self.transport = transport
        self.keychain = keychain
        self.sessionKey = sessionKey
        self.identityStore = identityStore
    }

    /// A currently-valid access token — signs in anonymously (first call
    /// ever) or refreshes (expiring/expired session) as needed.
    public func validAccessToken() async throws -> String {
        try await currentSession().accessToken
    }

    /// The device's Supabase `user_id` — becomes `auth.uid()` server-side.
    public func currentUserID() async throws -> UUID {
        try await currentSession().userID
    }

    /// A valid access token for the identity **already stored on this
    /// device**, or `nil` if this device has never had one.
    ///
    /// Deliberately NOT `validAccessToken()`, and the difference is the
    /// whole point: that method's contract is "get me a usable token by any
    /// means", so it happily mints a brand-new anonymous identity when none
    /// is stored or when a refresh token is rejected. That is right for
    /// pushing (a new identity just starts a new server mirror) and
    /// catastrophic for deleting — the request would erase a freshly-minted
    /// EMPTY account, report success, and leave the learner's real rows on
    /// the server under the old `user_id` with nothing left to address them
    /// by. An erasure request that silently erases the wrong (empty) account
    /// is worse than one that fails visibly.
    ///
    /// So this method only ever works with what is already in the Keychain:
    /// - nothing stored → `nil` (there is genuinely nothing to delete);
    /// - stored and still valid → that token;
    /// - stored but needing a refresh → refresh it, and **throw** if the
    ///   refresh fails, rather than falling through to a fresh sign-in.
    public func existingSessionAccessToken() async throws -> String? {
        try await existingSyncSession()?.accessToken
    }

    /// Same freshness/refresh evaluation `existingSessionAccessToken()`
    /// performs, but returns the whole `SyncSession` instead of just the
    /// token.
    ///
    /// ⚠️ Mineur #8 fix: this is now the SINGLE source both
    /// `existingSessionAccessToken()` and `linkOrSignInWithApple` derive
    /// their value from. Before this existed, `linkOrSignInWithApple`
    /// called `existingSessionAccessToken()` for the token and, separately,
    /// `currentUserID()` (→ `currentSession()`) for `previousUserID` — TWO
    /// independent `needsRefresh()` evaluations, each reading the wall
    /// clock at a different instant. If the session sat exactly on the
    /// refresh margin, the two calls could disagree: the first might
    /// return the still-valid token as-is, while the second — a few
    /// milliseconds later — decided a refresh (or even a fresh mint, on
    /// the anonymous/dead-session path) was now needed, producing a
    /// `previousUserID` that did NOT belong to the `accessToken` actually
    /// sent to `linkAppleIdentity`. The link_identity guard then compared
    /// the server's response against the WRONG previous id and refused an
    /// otherwise-correct link. Deriving both values from one session,
    /// evaluated once, makes that race structurally impossible instead of
    /// merely unlikely.
    private func existingSyncSession() async throws -> SyncSession? {
        if let cachedSession, !cachedSession.needsRefresh() {
            return cachedSession
        }
        guard let stored = loadStoredSession() else { return nil }
        if !stored.needsRefresh() {
            cachedSession = stored
            return stored
        }
        // Captured before the suspension below — see `identityGeneration`'s
        // doc comment for the race this guards against.
        let generationBeforeRefresh = identityGeneration
        let refreshed = try await transport.refreshSession(refreshToken: stored.refreshToken)
        guard generationBeforeRefresh == identityGeneration else {
            Logger.sync.info("Cloud sync: a sign-out ran while a token refresh was in flight — discarding the refreshed session instead of persisting it.")
            throw SyncAuthError.reauthenticationRequired
        }
        let carried = carryingIsAnonymous(from: stored, onto: refreshed)
        try persist(carried)
        return carried
    }

    /// The BOUND, current-device state — "does this device's own stored
    /// session already carry a linked (non-anonymous) identity right
    /// now?" Consulted by the app layer (`SettingsView`, the ASAuthorization
    /// flow) instead of a self-maintained `@AppStorage` flag, which could
    /// drift from what is actually in the Keychain. Deliberately reads
    /// straight off `loadStoredSession()` — the durable, on-disk truth —
    /// rather than `cachedSession`, so a caller asking "am I linked?"
    /// right after a cold launch (nothing cached yet) still gets the
    /// right answer without forcing a network round-trip.
    ///
    /// NOT the same question as `identityStore`'s `wasLinked` marker
    /// below: this answers "linked RIGHT NOW, per the Keychain"; that one
    /// answers "was EVER linked, even if the Keychain is currently empty"
    /// — see `currentSession()`'s guard for why the distinction matters.
    public func isLinkedToExternalIdentity() -> Bool {
        loadStoredSession()?.isAnonymous == false
    }

    /// The DURABLE, restore-surviving question: "has this device EVER
    /// persisted a linked (non-anonymous) `SyncSession`, even if the
    /// Keychain is empty right now?" — a thin pass-through to
    /// `identityStore.wasLinked()`, exposed on the actor (next to
    /// `isLinkedToExternalIdentity()` above) so callers never need to reach
    /// past this type into `SyncIdentityStore` directly.
    ///
    /// The two accessors answer genuinely different questions and must NOT
    /// be conflated (2026-08 lot-3 round-2 remediation, Critique CRITIQUE):
    /// `isLinkedToExternalIdentity()` reads the Keychain, which never
    /// migrates across devices; this one reads `UserDefaults`, which DOES
    /// restore from an iCloud backup. A device restored from a backup taken
    /// after linking Apple has `isLinkedToExternalIdentity() == false`
    /// (empty Keychain) but `hasEverHeldLinkedSession() == true` — exactly
    /// the state `CloudDataDeletionService.deleteAllCloudData()` must not
    /// mistake for "nothing to delete", and the state
    /// `SettingsView+AppleSignIn`'s reconnect row must not mistake for
    /// "ordinary, never-linked sign-in".
    public func hasEverHeldLinkedSession() -> Bool {
        identityStore.wasLinked()
    }

    /// Deletes the locally cached and Keychain-persisted session. Does NOT
    /// delete the server-side anonymous user (no lot 1 endpoint for that),
    /// and does NOT clear the `identityStore`'s `wasLinked` marker either —
    /// the next `validAccessToken()` call signs in fresh, minting a new
    /// `user_id`, ONLY if this device's `wasLinked` marker is still `false`
    /// (never held a linked session). On a device that WAS linked, this
    /// instead reproduces exactly the empty-Keychain-plus-`wasLinked`
    /// state `currentSession()`'s demotion guard exists to catch — the
    /// next call throws `SyncAuthError.reauthenticationRequired` rather
    /// than minting, same as a real iCloud-restore-onto-a-new-device would.
    /// That is intentional, not a gap: an already-linked device forgetting
    /// its session locally (this method) should behave identically to one
    /// that lost it to a backup restore — both are "no session, but this
    /// account is real" — the reachable recovery path is the same either
    /// way (`linkOrSignInWithApple`'s `.reauthenticatedAfterDeadSession`).
    /// Exposed for tests and for a future "reset sync identity" action.
    /// `CloudDataDeletionService` deliberately does NOT call this one —
    /// see `forgetSessionAfterAccountDeletion()` below for why a confirmed
    /// server-side account deletion needs different semantics.
    public func forgetSession() throws {
        cachedSession = nil
        try keychain.delete(key: sessionKey)
    }

    /// The counterpart to `forgetSession()` for use ONLY after
    /// `CloudDataDeletionService.deleteAllCloudData()` has confirmed the
    /// server-side account no longer exists — never for an ordinary "forget
    /// my local session" action. Clears the Keychain session exactly like
    /// `forgetSession()`, but ALSO resets the `wasLinked` marker back to
    /// `false` (2026-08 lot-3 round-2 remediation, Critique CRITIQUE item 4).
    ///
    /// `forgetSession()`'s own doc comment explains why `wasLinked` must
    /// normally survive a merely-local session loss (a dead refresh token,
    /// a reinstall, a backup restore onto a new device): the demotion guard
    /// in `currentSession()` has to keep protecting a linked account across
    /// all of those, because the account is still real on the server. None
    /// of that reasoning applies here — the account itself was just erased
    /// server-side, so there is nothing left for the guard to protect.
    /// Leaving `wasLinked` at `true` after a real deletion would turn the
    /// guard into a permanent lock-out instead: every future
    /// `currentSession()` call would throw `SyncAuthError
    /// .reauthenticationRequired` forever, on a device whose only way back
    /// in is signing in with the SAME Apple ID — which recreates an account
    /// and immediately hits the same guard again. Resetting the marker lets
    /// this device mint a fresh anonymous identity next time, exactly like
    /// a genuinely first-ever install.
    ///
    /// See `signOut()` below for the sibling method: same Keychain/`wasLinked`
    /// mechanics, but for a voluntary disconnect where the account survives —
    /// never call THIS method for that case, its contract requires a
    /// server-confirmed deletion.
    public func forgetSessionAfterAccountDeletion() throws {
        cachedSession = nil
        try keychain.delete(key: sessionKey)
        identityStore.setWasLinked(false)
        // Bumped so a refresh already suspended on the network (see
        // `identityGeneration`'s doc comment) discards its result instead
        // of resurrecting the session/marker this call just erased.
        identityGeneration += 1
    }

    /// Voluntary sign-out (Settings → "Sign out") — the counterpart to
    /// `forgetSessionAfterAccountDeletion()` above for a device whose
    /// account is NOT being erased, just deliberately disconnected. Ikeru
    /// is local-first: signing out never touches local SwiftData — it only
    /// ends THIS device's claim to the server-side identity, which
    /// survives untouched (see `CloudSyncCoordinator.signOut()`'s doc
    /// comment for the full picture, including why the cursor/skip-tracker/
    /// consent reset live there instead of here).
    ///
    /// Same body as `forgetSessionAfterAccountDeletion()` — clear the
    /// Keychain session AND reset `wasLinked` back to `false` — but a
    /// DIFFERENT name and a DIFFERENT contract, because the two are not
    /// interchangeable: that method may be called ONLY once the server has
    /// CONFIRMED the account itself no longer exists; this one is for an
    /// ordinary, reversible disconnect where the account is still real.
    /// Reusing the deletion-named method here would have been correct by
    /// accident (the Keychain/`wasLinked` mechanics really are identical)
    /// but wrong by name — a future reader could reasonably assume that
    /// call site means the account was erased, when it was not.
    ///
    /// `wasLinked` MUST reset to `false` here, exactly like the deletion
    /// path (⚠️ CRITICAL — do not drop this line). `forgetSession()`'s own
    /// doc comment explains why the marker must normally SURVIVE a
    /// merely-local session loss (a dead refresh token, a reinstall, a
    /// backup restore) — the account is still real in all of those, so
    /// `currentSession()`'s demotion guard must keep protecting it. None of
    /// that reasoning applies to a DELIBERATE sign-out: the learner
    /// explicitly chose to stop being connected, so there is nothing left
    /// for the guard to protect either — leaving `wasLinked` at `true`
    /// would instead make every future `currentSession()` call throw
    /// `SyncAuthError.reauthenticationRequired` forever, locking a learner
    /// who chose to step away out of even an anonymous, no-account backup
    /// afterward. That is the exact permanent lock-out
    /// `forgetSessionAfterAccountDeletion()`'s own doc comment warns
    /// against, reproduced here for a voluntary disconnect instead of a
    /// confirmed deletion.
    public func signOut() throws {
        cachedSession = nil
        try keychain.delete(key: sessionKey)
        identityStore.setWasLinked(false)
        // ⚠️ Bumped so a refresh already suspended on the network — a
        // `syncNow()` mid-cycle when the learner tapped "Sign out" — cannot
        // resurrect the Keychain session or `wasLinked` once it resumes.
        // See `identityGeneration`'s doc comment for the full race and
        // `CloudSyncSignOutTests.signOutDuringInFlightRefreshIsNotUndone`
        // for the reproduction.
        identityGeneration += 1
    }

    // MARK: - Apple identity linking (lot 3)

    /// Adopts a session obtained OUTSIDE the normal anonymous
    /// sign-in/refresh flow this actor otherwise owns end-to-end —
    /// currently only `linkOrSignInWithApple`'s successful paths call this.
    /// Same ordering `persist()` already enforces everywhere else in this
    /// file (Keychain write first, THEN the in-memory cache) — exposed
    /// publicly here, rather than making `persist` itself public, so every
    /// OTHER caller keeps going through this actor's own sign-in/refresh
    /// machinery instead of bypassing it.
    public func adoptSession(_ session: SyncSession) throws {
        try persist(session)
    }

    /// Links the caller's already-verified Apple identity token to this
    /// device's identity — the sole Core entry point the ASAuthorization
    /// flow (`Ikeru/Services/…`, app target; `AuthenticationServices` has no
    /// place in this dependency-free Core package) calls once it has a
    /// completed `ASAuthorizationAppleIDCredential`. `idToken` is that
    /// credential's `identityToken`, UTF-8 decoded; `rawNonce` is the RAW
    /// (unhashed) nonce the caller generated before requesting the
    /// credential — its SHA-256 hex went into `ASAuthorizationAppleIDRequest
    /// .nonce`, but Supabase wants the raw value (it hashes server-side).
    ///
    /// ### Which of two request shapes reaches the server
    ///
    /// - **This device already holds a session** (`existingSessionAccessToken()`
    ///   returns non-nil, refreshing if needed): attempts to GRAFT the Apple
    ///   identity onto that EXACT `user_id` —
    ///   `SupabaseAuthTransport.linkAppleIdentity`, `link_identity: true`.
    ///   Guarded below; a refusal specifically because the identity already
    ///   belongs to a DIFFERENT existing account
    ///   (`SyncAuthError.identityAlreadyLinked`) falls back to the no-session
    ///   path — see `AppleLinkOutcome.switchedIdentity`'s doc comment for why
    ///   that is a legitimate, expected outcome, not an error.
    /// - **No session** — a fresh install, a device whose session was
    ///   already forgotten, OR the fallback above, OR the stored session's
    ///   refresh token was explicitly REJECTED (a 400/401/403 from
    ///   `existingSyncSession()`'s own refresh attempt — dead, not merely
    ///   unreachable or rate-limited; see that catch clause below for
    ///   exactly which statuses count and why 429 must NOT — and see the
    ///   demotion guard in `currentSession()` for why a dead session must
    ///   never be papered over by silently minting a new anonymous
    ///   identity instead) — a plain
    ///   `SupabaseAuthTransport.signInWithApple`, no `link_identity`, no
    ///   `Authorization` header. Deliberately NOT catching network failures
    ///   or 5xx here: those mean "couldn't tell," not "the server said no,"
    ///   and must keep propagating as a genuine error rather than being
    ///   quietly reinterpreted as "start over."
    ///
    /// ### ⚠️ The guard — this method's single most important lines
    ///
    /// A successful `linkAppleIdentity` call is trusted ONLY if the
    /// `user_id` it returns is IDENTICAL to the one captured immediately
    /// before making the call. If the server silently ignored
    /// `link_identity: true` — wrong GoTrue version, "manual linking"
    /// toggled back off, any future regression — the call still returns
    /// HTTP 2xx and a perfectly valid session, just for a DIFFERENT
    /// account. Adopting that response anyway would silently switch this
    /// device onto a brand-new-or-unrelated identity and orphan every
    /// already-synced row with no trace and no error surfaced anywhere.
    /// Comparing first, and throwing `AppleLinkError.linkIdentityGuardTripped`
    /// instead of persisting on any mismatch, is what turns that failure
    /// mode from silent data loss into a loud, attributable one. Never
    /// weaken this to a warning; never fall back to `signInWithApple` on a
    /// guard trip either — that would be adopting the very identity switch
    /// the guard exists to refuse, just one call later.
    public func linkOrSignInWithApple(idToken: String, rawNonce: String) async throws -> AppleLinkOutcome {
        let existingSession: SyncSession?
        do {
            // Mineur #8 fix: ONE evaluation of freshness, yielding BOTH the
            // access token to link FROM and the `user_id` the guard below
            // compares against — see `existingSyncSession()`'s doc comment
            // for the race this closes versus calling
            // `existingSessionAccessToken()` and `currentUserID()`
            // separately.
            existingSession = try await existingSyncSession()
        } catch SyncAuthError.requestFailed(let status, _, _) where [400, 401, 403].contains(status) {
            // Important #3 fix: an EXPLICIT refresh-token rejection —
            // 400/401 (GoTrue's own "invalid_grant" shapes) or 403 (a
            // rejected API key/credential on this specific request) — dead,
            // not just unreachable. Treated identically to "no local
            // session at all" so this is a reachable recovery path for the
            // `.reauthenticationRequired` error `currentSession()`'s
            // demotion guard throws: signing in with Apple on a
            // LINKED-but-dead session re-authenticates as the SAME account
            // (the server returns the same `user_id` for the same Apple
            // identity), so the next `CloudSyncCoordinator.syncNow()` sees
            // no identity change and every cursor survives untouched — a
            // true reconnect. A dead ANONYMOUS session re-authenticating as
            // whatever account Apple reports is no worse than the
            // unreachable anonymous mirror it replaces.
            //
            // ⚠️ Deliberately NOT the full `(400..<500)` range this used to
            // be: that range also matched 429 (rate limit) and other 4xx
            // that mean "try again," not "this token is dead." A 429 here
            // used to make a perfectly live anonymous session fall through
            // to `signInWithApple` with NO `link_identity` and NO
            // `Authorization` header — minting a brand-new, unrelated
            // `user_id` and silently orphaning the live one, on the exact
            // rate-limit response that should have just been retried. A
            // 429 (or any other 4xx not in this list) now propagates
            // unchanged, same as a 5xx already did.
            let session = try await transport.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try adoptSession(session)
            return .reauthenticatedAfterDeadSession(userID: session.userID)
        }

        guard let existingSession else {
            let session = try await transport.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try adoptSession(session)
            return .switchedIdentity(userID: session.userID, wasAlreadyLinkedElsewhere: false)
        }

        let accessToken = existingSession.accessToken
        // The value the guard below compares the response against — drawn
        // from the SAME `existingSession` the access token above came from,
        // never re-derived via a second, independently-timed call (see
        // `existingSyncSession()`'s doc comment).
        let previousUserID = existingSession.userID

        do {
            let linked = try await transport.linkAppleIdentity(idToken: idToken, rawNonce: rawNonce, accessToken: accessToken)

            guard linked.userID == previousUserID else {
                Logger.sync.fault("Cloud sync: Apple link_identity call returned a DIFFERENT user_id than requested (\(previousUserID, privacy: .public) → \(linked.userID, privacy: .public)) — refusing to adopt it.")
                throw AppleLinkError.linkIdentityGuardTripped
            }

            try adoptSession(linked)
            return .linkedExistingIdentity(userID: linked.userID)

        } catch SyncAuthError.identityAlreadyLinked {
            // Matrix case (c): this Apple identity already has its own,
            // separate (possibly populated) Supabase account. GoTrue will
            // not merge two already-existing accounts, so fall back to
            // signing in AS that account instead. The resulting `user_id`
            // genuinely differs from `previousUserID` — that is the whole
            // point, not a guard violation (the guard only ever applies to
            // `linkAppleIdentity`'s own response, never to this fallback
            // call).
            let session = try await transport.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try adoptSession(session)
            return .switchedIdentity(userID: session.userID, wasAlreadyLinkedElsewhere: true)
        }
    }

    // MARK: - Private

    private func currentSession() async throws -> SyncSession {
        if let cachedSession, !cachedSession.needsRefresh() {
            return cachedSession
        }

        if let stored = loadStoredSession() {
            if !stored.needsRefresh() {
                cachedSession = stored
                return stored
            }
            do {
                // Captured before the suspension below — see
                // `identityGeneration`'s doc comment for the race this
                // guards against: a `signOut()` (or account-deletion forget)
                // landing on this actor while the refresh below is in
                // flight must not have its Keychain erasure silently undone
                // once this call resumes.
                let generationBeforeRefresh = identityGeneration
                let refreshed = try await transport.refreshSession(refreshToken: stored.refreshToken)
                guard generationBeforeRefresh == identityGeneration else {
                    Logger.sync.info("Cloud sync: a sign-out ran while a token refresh was in flight — discarding the refreshed session instead of persisting it.")
                    throw SyncAuthError.reauthenticationRequired
                }
                let carried = carryingIsAnonymous(from: stored, onto: refreshed)
                try persist(carried)
                return carried
            } catch SyncAuthError.requestFailed(let status, _, _) where [400, 401, 403].contains(status) {
                // 2026-08 lot-3 round-2 remediation ("the blind try? of the
                // ordinary path"): this used to be `if let refreshed =
                // try? ...`, which swallowed EVERY refresh failure —
                // network unreachable, a 429 rate limit, a 5xx — and fell
                // straight through to the demotion-guard logic below as if
                // the token had been explicitly rejected. Mirrors
                // `linkOrSignInWithApple`'s matching catch clause above:
                // ONLY an explicit 400/401/403 rejection (dead, not merely
                // unreachable or rate-limited — see that clause's doc
                // comment for exactly why this range and no wider) is
                // treated as "this session is dead." Everything else is NOT
                // caught here and propagates unchanged out of this
                // function, exactly like a `try` with no `?` would. Two
                // proven failure modes this closes:
                //   - K1: a 429 on an ANONYMOUS session's refresh used to
                //     fall through to `signInAnonymously()` below, abandoning
                //     a live account and orphaning its rows, on a response
                //     that meant "retry later," not "start over."
                //   - K2: a plain network failure (offline, timeout) on a
                //     LINKED session's refresh used to fall through to the
                //     guard just below and throw `.reauthenticationRequired`
                //     — a learner who opens the app in airplane mode would
                //     be told to sign in again for no reason; nothing was
                //     actually lost, the server just couldn't be reached.
                // "Couldn't tell" must never be silently reinterpreted as
                // "the server said no."
            }
            // Refresh token was rejected (expired, or already rotated away
            // by a previous attempt that crashed after the server issued a
            // new one but before we persisted it).
            //
            // ⚠️ DEMOTION GUARD (lot 3 — this was a silent-data-loss bug
            // before this check existed). Falling through to a fresh
            // anonymous sign-in mints a NEW user_id — fine, by design, for
            // an anonymous session: worst case is a stale/split server
            // mirror, never lost local data (design spec §5.4's stated risk
            // tolerance for the push-only lot this comment used to describe
            // alone). It stops being fine the moment a session can be
            // LINKED to a real account: a signed-in learner whose refresh
            // token merely expired (device offline for a while, clock skew,
            // ordinary token rotation) would otherwise be silently demoted
            // to a brand-new anonymous ghost — `CloudSyncCoordinator`'s
            // identity-change detection would then treat this exactly like
            // a fresh device, reset every cursor, and the learner's real
            // account would never receive another row again. There is no
            // error, no crash, nothing to notice — just progress that quietly
            // stops reaching the account the learner thinks they're using.
            //
            // So: mint a fresh anonymous identity ONLY when the dead
            // session was itself anonymous. A dead LINKED session instead
            // throws `.reauthenticationRequired` — the caller (ultimately
            // `CloudSyncCoordinator.syncNow()`, surfaced as a failed sync
            // with a distinguishable error) must ask the learner to sign in
            // with Apple again, never invent a new identity on their
            // behalf. `linkOrSignInWithApple` below is the reachable
            // recovery path for that error: it treats this exact rejection
            // as "no local session" and re-authenticates via Apple, which
            // for a LINKED account returns the SAME `user_id` (a true
            // reconnect, not a fresh one) — see that method's doc comment.
            guard stored.isAnonymous else {
                Logger.sync.error("Cloud sync: a LINKED session's refresh token was rejected — refusing to silently re-mint an anonymous identity in its place. Reconnection required.")
                throw SyncAuthError.reauthenticationRequired
            }
            Logger.sync.error("Cloud sync: refresh token rejected, minting a new anonymous identity (previous user_id's server rows are orphaned).")
        }

        // ⚠️ CRITIQUE #1 GUARD (lot 3 remediation) — the Keychain-EMPTY half
        // of the demotion guard above, which only ever fires when
        // `loadStoredSession()` returned something. It fires for nothing
        // when the Keychain is EMPTY (`stored == nil`), which is exactly
        // what happens after an iCloud backup is restored onto a new
        // device: `UserDefaults` (and therefore `identityStore`'s
        // `wasLinked` marker) restores from the backup, but the Keychain
        // entry — persisted with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
        // — never does. Without this check, a learner who signed in with
        // Apple on device A and restores that backup onto device B would
        // fall straight through to `signInAnonymously()` below on the
        // first `syncNow()`: a brand-new, empty ghost identity that
        // `CloudSyncCoordinator`'s re-provisioning guard then treats as a
        // legitimate identity change, resetting every cursor and pushing
        // into an account the learner can never see their real data from
        // again. `identityStore.wasLinked()` is the one signal that
        // survives this exact asymmetry — see `SyncIdentityStore`'s type
        // doc comment. A device that has NEVER held a linked session
        // (`wasLinked() == false`, the ordinary first-install case) is
        // completely unaffected: it falls through to the anonymous mint
        // below exactly as before.
        guard !identityStore.wasLinked() else {
            Logger.sync.error("Cloud sync: no session in Keychain, but wasLinked marker is true (UserDefaults restore) — refusing to mint anonymous ghost.")
            throw SyncAuthError.reauthenticationRequired
        }

        let fresh = try await transport.signInAnonymously()
        try persist(fresh)
        return fresh
    }

    /// Carries `stored`'s `isAnonymous` flag forward onto a session that was
    /// just obtained by REFRESHING `stored`'s tokens — see
    /// `SyncSession.isAnonymous`'s doc comment for why a refresh must never
    /// be trusted to decide this value on its own.
    private func carryingIsAnonymous(from stored: SyncSession, onto refreshed: SyncSession) -> SyncSession {
        SyncSession(
            userID: refreshed.userID,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt,
            isAnonymous: stored.isAnonymous
        )
    }

    private func loadStoredSession() -> SyncSession? {
        // `try?` on a throwing function that itself returns `String?`
        // flattens to `String?` (SE-0230) — `raw` below is already the
        // unwrapped `String`, not a further optional.
        guard
            let raw = try? keychain.load(key: sessionKey),
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? SyncJSON.decoder.decode(SyncSession.self, from: data)
    }

    private func persist(_ session: SyncSession) throws {
        let data = try SyncJSON.encoder.encode(session)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        // Persist before updating the in-memory cache: if the Keychain
        // write throws, callers must not observe a session that isn't
        // actually durable (a crash right after would lose it silently).
        try keychain.save(key: sessionKey, value: string)
        cachedSession = session
        // Critique #1 fix: record the `wasLinked` marker in the SAME place
        // (`identityStore`, UserDefaults-backed) `CloudSyncCoordinator`
        // already keeps `lastKnownUserID` — the store that DOES restore
        // from an iCloud backup, unlike the Keychain entry just written
        // above. Only ever set to `true`, never back to `false`, by
        // anything in this lot: once a device has held a linked identity,
        // `currentSession()`'s guard must keep protecting it even across a
        // LATER anonymous session existing locally (there is no legitimate
        // flow that demotes a linked device back to "never linked").
        // Deliberately placed AFTER the `keychain.save` above succeeds,
        // same ordering rationale as `cachedSession` on the line above:
        // if the Keychain write throws, the marker must not claim a
        // linked session exists when nothing durable actually got written.
        if !session.isAnonymous {
            identityStore.setWasLinked(true)
        }
    }
}
