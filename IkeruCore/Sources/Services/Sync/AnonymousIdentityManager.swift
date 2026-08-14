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
        try persist(refreshed)
        return refreshed.accessToken
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
                try persist(refreshed)
                return refreshed
            }
            // Refresh token was rejected (expired, or already rotated away
            // by a previous attempt that crashed after the server issued a
            // new one but before we persisted it). Falling through to a
            // fresh anonymous sign-in mints a NEW user_id — rows already
            // pushed under the old id are orphaned server-side. Acceptable
            // for a push-only lot (design spec §5.4's stated risk
            // tolerance: worst case is a stale/split server mirror, never
            // lost local data) but worth being loud about, not silent.
            Logger.sync.error("Cloud sync: refresh token rejected, minting a new anonymous identity (previous user_id's server rows are orphaned).")
        }

        let fresh = try await transport.signInAnonymously()
        try persist(fresh)
        return fresh
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
