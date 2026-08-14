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

    private var cachedSession: SyncSession?

    public init(
        transport: any SupabaseAuthTransport = URLSessionSupabaseAuthTransport(),
        keychain: any KeychainStore = KeychainHelper(),
        sessionKey: String = SyncKeychainKeys.session
    ) {
        self.transport = transport
        self.keychain = keychain
        self.sessionKey = sessionKey
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
        if let cachedSession, !cachedSession.needsRefresh() {
            return cachedSession.accessToken
        }
        guard let stored = loadStoredSession() else { return nil }
        if !stored.needsRefresh() {
            cachedSession = stored
            return stored.accessToken
        }
        let refreshed = try await transport.refreshSession(refreshToken: stored.refreshToken)
        let carried = carryingIsAnonymous(from: stored, onto: refreshed)
        try persist(carried)
        return carried.accessToken
    }

    /// Deletes the locally cached and Keychain-persisted session. Does NOT
    /// delete the server-side anonymous user (no lot 1 endpoint for that);
    /// the next `validAccessToken()` call signs in fresh, minting a new
    /// `user_id`. Exposed for tests and for a future "reset sync identity"
    /// action — nothing in this lot's shipped call path invokes it.
    public func forgetSession() throws {
        cachedSession = nil
        try keychain.delete(key: sessionKey)
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
    ///   refresh token was explicitly REJECTED (a 4xx from
    ///   `existingSessionAccessToken()`'s own refresh attempt — dead, not
    ///   merely unreachable; see the demotion guard in `currentSession()`
    ///   for why that must never be papered over by silently minting a new
    ///   anonymous identity instead) — a plain
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
        let accessToken: String?
        do {
            accessToken = try await existingSessionAccessToken()
        } catch SyncAuthError.requestFailed(let status, _, _) where (400..<500).contains(status) {
            // The stored session's refresh token was explicitly REJECTED —
            // dead, not just unreachable. Treated identically to "no local
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
            let session = try await transport.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try adoptSession(session)
            return .reauthenticatedAfterDeadSession(userID: session.userID)
        }

        guard let accessToken else {
            let session = try await transport.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try adoptSession(session)
            return .switchedIdentity(userID: session.userID, wasAlreadyLinkedElsewhere: false)
        }

        // Captured BEFORE the linking call — the value the guard above
        // compares the response against.
        let previousUserID = try await currentUserID()

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
            if let refreshed = try? await transport.refreshSession(refreshToken: stored.refreshToken) {
                let carried = carryingIsAnonymous(from: stored, onto: refreshed)
                try persist(carried)
                return carried
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
    }
}
