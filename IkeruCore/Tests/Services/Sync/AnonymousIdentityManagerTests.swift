import Testing
import Foundation
@testable import IkeruCore

@Suite("AnonymousIdentityManager")
struct AnonymousIdentityManagerTests {

    private func makeSession(userID: UUID = UUID(), expiresIn: TimeInterval = 3600, isAnonymous: Bool = true) -> SyncSession {
        SyncSession(
            userID: userID,
            accessToken: "access-\(UUID().uuidString)",
            refreshToken: "refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(expiresIn),
            isAnonymous: isAnonymous
        )
    }

    @Test("First call with no stored session signs in anonymously and persists the result")
    func firstCallSignsInAnonymously() async throws {
        let session = makeSession()
        let transport = MockSupabaseAuthTransport(signInResult: .success(session))
        let keychain = MockKeychainStore()
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let token = try await manager.validAccessToken()

        #expect(token == session.accessToken)
        #expect(transport.signInCallCount == 1)
        #expect(transport.refreshCallCount == 0)
        // Persisted, not just cached in memory.
        #expect(try keychain.load(key: SyncKeychainKeys.session) != nil)
    }

    @Test("A cached, non-expiring session is reused without a second sign-in call")
    func reusesCachedSession() async throws {
        let session = makeSession(expiresIn: 3600)
        let transport = MockSupabaseAuthTransport(signInResult: .success(session))
        let keychain = MockKeychainStore()
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        _ = try await manager.validAccessToken()
        _ = try await manager.validAccessToken()

        #expect(transport.signInCallCount == 1)
    }

    @Test("A session already on disk (fresh Keychain state, cold manager) is loaded, not re-signed-in")
    func loadsStoredSessionWithoutSigningInAgain() async throws {
        let session = makeSession(expiresIn: 3600)
        let keychain = MockKeychainStore()
        let data = try SyncJSON.encoder.encode(session)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)

        let transport = MockSupabaseAuthTransport(signInResult: .failure(SyncAuthError.invalidResponse))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let token = try await manager.validAccessToken()

        #expect(token == session.accessToken)
        #expect(transport.signInCallCount == 0)
    }

    @Test("An expiring stored session is refreshed, not re-signed-in")
    func refreshesExpiringStoredSession() async throws {
        let expiring = makeSession(expiresIn: 10) // within the 60s default margin
        let refreshed = makeSession(userID: expiring.userID, expiresIn: 3600)

        let keychain = MockKeychainStore()
        let data = try SyncJSON.encoder.encode(expiring)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)

        let transport = MockSupabaseAuthTransport(
            signInResult: .failure(SyncAuthError.invalidResponse),
            refreshResult: .success(refreshed)
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let token = try await manager.validAccessToken()

        #expect(token == refreshed.accessToken)
        #expect(transport.refreshCallCount == 1)
        #expect(transport.lastRefreshToken == expiring.refreshToken)
        #expect(transport.signInCallCount == 0)
    }

    @Test("A rejected refresh token falls back to a fresh anonymous sign-in")
    func rejectedRefreshFallsBackToSignIn() async throws {
        let expiring = makeSession(expiresIn: 10)
        let fresh = makeSession() // new user_id

        let keychain = MockKeychainStore()
        let data = try SyncJSON.encoder.encode(expiring)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)

        let transport = MockSupabaseAuthTransport(
            signInResult: .success(fresh),
            refreshResult: .failure(SyncAuthError.requestFailed(status: 401, errorCode: "invalid_grant", body: ""))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let userID = try await manager.currentUserID()

        #expect(userID == fresh.userID)
        #expect(transport.refreshCallCount == 1)
        #expect(transport.signInCallCount == 1)
    }

    @Test("forgetSession clears both the in-memory cache and Keychain, forcing a fresh sign-in next call")
    func forgetSessionForcesFreshSignIn() async throws {
        let first = makeSession()
        let second = makeSession()
        let transport = MockSupabaseAuthTransport(signInResult: .success(first))
        let keychain = MockKeychainStore()
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        _ = try await manager.validAccessToken()
        try await manager.forgetSession()
        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)

        transport.signInResult = .success(second)
        let token = try await manager.validAccessToken()

        #expect(token == second.accessToken)
        #expect(transport.signInCallCount == 2)
    }

    // MARK: - 2026-08 lot-3 round-2 remediation: the ordinary path's `try?`

    /// K1. Before this fix, `currentSession()`'s refresh call was
    /// `if let refreshed = try? ...` — ANY failure, including a 429 rate
    /// limit, fell straight through to the anonymous-mint fallback below.
    /// For a still-live anonymous session, that meant a rate-limited
    /// refresh silently abandoned the live account and started a brand-new
    /// one, orphaning every row synced under the old `user_id`. A 429 must
    /// propagate instead, exactly like `linkOrSignInWithApple`'s matching
    /// guard already does.
    @Test("K1: a 429 while refreshing an anonymous session does NOT fall back to minting a new one — propagates so the caller can retry")
    func rateLimitOnAnonymousRefreshDoesNotMintNewIdentity() async throws {
        let expiring = makeSession(expiresIn: 10, isAnonymous: true)
        let keychain = MockKeychainStore()
        let data = try SyncJSON.encoder.encode(expiring)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)

        let transport = MockSupabaseAuthTransport(
            signInResult: .success(makeSession()), // would mint a NEW, unrelated identity if reached
            refreshResult: .failure(SyncAuthError.requestFailed(status: 429, errorCode: "over_request_rate_limit", body: ""))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: SyncAuthError.requestFailed(status: 429, errorCode: "over_request_rate_limit", body: "")) {
            _ = try await manager.validAccessToken()
        }
        #expect(
            transport.signInCallCount == 0,
            "a 429 means retry-later, not dead — must not orphan a live anonymous session by minting a brand-new unrelated identity"
        )
    }

    /// K2. Same blind `try?`, opposite direction: for a LINKED session, a
    /// plain network failure (offline, timeout — NOT an explicit
    /// 400/401/403 rejection) used to fall through to the demotion guard
    /// just below and throw `.reauthenticationRequired` — a learner who
    /// opens the app in airplane mode would be told to sign in again for no
    /// reason. Nothing was actually lost; the server just could not be
    /// reached. The raw network error must propagate untranslated instead.
    @Test("K2: a network failure while refreshing a LINKED session does NOT throw reauthenticationRequired — propagates the raw failure")
    func networkFailureOnLinkedRefreshDoesNotForceReauthentication() async throws {
        let expiring = makeSession(expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        let data = try SyncJSON.encoder.encode(expiring)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)

        let networkError = URLError(.notConnectedToInternet)
        let transport = MockSupabaseAuthTransport(
            signInResult: .success(makeSession()),
            refreshResult: .failure(networkError)
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        do {
            _ = try await manager.validAccessToken()
            Issue.record("Expected the network failure to propagate")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet, "the ORIGINAL network error must propagate untranslated")
        } catch {
            Issue.record("Expected URLError(.notConnectedToInternet), got \(error) — a network failure must never be reinterpreted as SyncAuthError.reauthenticationRequired")
        }
        #expect(transport.signInCallCount == 0, "no fallback sign-in on a merely-unreachable refresh")
    }
}
