import Testing
import Foundation
@testable import IkeruCore

@Suite("AnonymousIdentityManager")
struct AnonymousIdentityManagerTests {

    private func makeSession(userID: UUID = UUID(), expiresIn: TimeInterval = 3600) -> SyncSession {
        SyncSession(
            userID: userID,
            accessToken: "access-\(UUID().uuidString)",
            refreshToken: "refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    @Test("First call with no stored session signs in anonymously and persists the result")
    func firstCallSignsInAnonymously() async throws {
        let session = makeSession()
        let transport = MockSupabaseAuthTransport(signInResult: .success(session))
        let keychain = MockKeychainStore()
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

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
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

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
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

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
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

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
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

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
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain)

        _ = try await manager.validAccessToken()
        try await manager.forgetSession()
        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)

        transport.signInResult = .success(second)
        let token = try await manager.validAccessToken()

        #expect(token == second.accessToken)
        #expect(transport.signInCallCount == 2)
    }
}
