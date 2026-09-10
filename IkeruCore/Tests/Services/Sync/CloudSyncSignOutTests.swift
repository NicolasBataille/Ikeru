import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// `CloudSyncCoordinator.signOut()` — the "Settings → Sign out" action added
/// after lot 3 shipped Sign in with Apple without a way back off it.
///
/// Suite name deliberately does not collide with any other token in the CI
/// `--filter` regex (`.github/workflows/ci.yml`'s green-subset step): it must
/// not accidentally substring-match an existing alternation branch (several
/// existing terms — `CloudSyncCoordinator`, `AnonymousIdentityManager`,
/// `SyncCursorStore`, `SyncConsentStore` — would all match if this suite's
/// name or any `@Test` name in it happened to contain them). "CloudSyncSignOut"
/// is now itself one of the alternation terms in that filter.
///
/// Ikeru is local-first: signing out is deliberately never tested here
/// against any SwiftData row (`Card`, `ReviewLog`, `UserProfile`, …) — the
/// whole point of `CloudSyncCoordinator.signOut()` is that it never touches
/// them. Every assertion below is about the four `Sync*Store` protocols and
/// the Keychain-backed session, exactly the surfaces `signOut()` actually
/// changes.
@Suite("CloudSyncSignOut")
struct CloudSyncSignOutTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            ExerciseOutcomeLog.self,
            CompanionChatMessage.self,
            // `TextImport` is not optional in these containers: `SyncPullActor`
            // pulls `text_imports` and counts it in `localRowCount()`, so a
            // container without it makes every `pullAll` throw.
            TextImport.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSession(userID: UUID = UUID(), expiresIn: TimeInterval = 3600, isAnonymous: Bool = true) -> SyncSession {
        SyncSession(
            userID: userID,
            accessToken: "access-\(UUID().uuidString)",
            refreshToken: "refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(expiresIn),
            isAnonymous: isAnonymous
        )
    }

    /// Seeds a `MockKeychainStore` with an already-valid session, exactly as
    /// `AnonymousIdentityManager` would have persisted it itself (same key,
    /// same `SyncJSON` codec) — copied from
    /// `AnonymousIdentityManagerTests.loadsStoredSessionWithoutSigningInAgain`.
    private func seed(_ session: SyncSession, into keychain: MockKeychainStore) throws {
        let data = try SyncJSON.encoder.encode(session)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)
    }

    // MARK: - Local state reset

    @Test("signOut clears the Keychain session, the wasLinked marker, every pull cursor, the skip tracker, and consent")
    func signOutResetsEveryLocalStore() async throws {
        // A device that WAS linked to a real account: a linked session on
        // disk, `wasLinked` true, non-nil cursors on more than one table
        // (a device that has already synced for a while), a skip-tracker
        // strike recorded on one of them, and consent on.
        let session = makeSession(isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)
        let identityStore = MockSyncIdentityStore(wasLinked: true)

        let cursorStore = MockSyncCursorStore(cursors: [
            "cards": SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)), id: UUID()),
            "review_logs": SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)), id: UUID()),
        ])
        let skipTracker = MockSyncSkipTracker()
        skipTracker.recordSkip(table: "cards", headRowID: UUID())
        let consentStore = MockSyncConsentStore(consentGiven: true)

        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: identityStore)
        let coordinator = CloudSyncCoordinator(
            modelContainer: try makeContainer(),
            identity: identity,
            transport: MockSyncDataTransport(),
            pullTransport: MockSyncPullTransport(),
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            identityStore: identityStore,
            consentStore: consentStore
        )

        try await coordinator.signOut()

        // Keychain session gone.
        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)
        // ⚠️ The CRITICAL bit this whole lot exists for: `wasLinked` must
        // reset too, or the very next `currentSession()` call throws
        // `reauthenticationRequired` forever — see the other test below for
        // the end-to-end proof.
        #expect(identityStore.wasLinked() == false)
        // Every pull cursor and skip-tracker strike gone, so a future
        // reconnect is a genuine cold start rather than resuming mid-stream.
        #expect(cursorStore.cursor(forTable: "cards") == nil)
        #expect(cursorStore.cursor(forTable: "review_logs") == nil)
        #expect(skipTracker.currentCount(forTable: "cards") == nil)
        // Backup consent is off.
        #expect(consentStore.isConsentGiven() == false)
    }

    // MARK: - Anti-lockout (the whole point of resetting `wasLinked`)

    /// The most important test in this file. Before `AnonymousIdentityManager
    /// .signOut()` existed, the only two ways to clear a Keychain session
    /// were `forgetSession()` (deliberately leaves `wasLinked` at `true` —
    /// correct for a merely-local session loss where the account is still
    /// real) and `forgetSessionAfterAccountDeletion()` (only for a
    /// server-confirmed deletion). Using EITHER for a voluntary sign-out
    /// would have been wrong: the first re-creates the exact demotion-guard
    /// lock-out `CloudDataDeletionServiceTests
    /// .successfulDeletionAllowsFreshAnonymousSyncAfterward` already proved
    /// once for account deletion — a learner who deliberately signed out
    /// would find every subsequent sync throwing
    /// `SyncAuthError.reauthenticationRequired` forever, unable to even
    /// start a fresh anonymous backup.
    @Test("CRITICAL: a sync following sign-out does not throw reauthenticationRequired, and mints a fresh anonymous identity")
    func syncAfterSignOutDoesNotThrowAndMintsFreshIdentity() async throws {
        let session = makeSession(isAnonymous: false) // a linked session, as a signed-in device would have
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)
        let identityStore = MockSyncIdentityStore(wasLinked: true)

        let freshAnonymousSession = makeSession()
        let authTransport = MockSupabaseAuthTransport(signInResult: .success(freshAnonymousSession))
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: identityStore)
        let consentStore = MockSyncConsentStore(consentGiven: true)
        let coordinator = CloudSyncCoordinator(
            modelContainer: try makeContainer(),
            identity: identity,
            transport: MockSyncDataTransport(),
            pullTransport: MockSyncPullTransport(),
            cursorStore: MockSyncCursorStore(),
            skipTracker: MockSyncSkipTracker(),
            identityStore: identityStore,
            consentStore: consentStore
        )

        try await coordinator.signOut()
        // Simulate opting back in — `signOut()` itself turns consent off,
        // same as the Settings toggle would leave it; a learner has to
        // explicitly turn backup back on to sync again.
        await coordinator.setConsent(true)

        let outcome = await coordinator.syncNow()

        guard case .success = outcome else {
            Issue.record("Expected a successful sync after sign-out + re-opt-in, got \(outcome) — a reauthenticationRequired lock-out here is exactly the regression this test guards against")
            return
        }
        // The real proof: a BRAND NEW anonymous identity was minted, not a
        // reuse of the old (now-forgotten) linked one, and nothing refused
        // the attempt.
        #expect(authTransport.signInCallCount == 1)
    }

    // MARK: - No-op safety

    @Test("Signing out when no session exists does not throw")
    func signOutWithNoExistingSessionDoesNotThrow() async throws {
        let keychain = MockKeychainStore() // empty — never signed in on this device
        let identityStore = MockSyncIdentityStore() // wasLinked defaults to false
        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: identityStore)
        let consentStore = MockSyncConsentStore(consentGiven: false)
        let coordinator = CloudSyncCoordinator(
            modelContainer: try makeContainer(),
            identity: identity,
            transport: MockSyncDataTransport(),
            pullTransport: MockSyncPullTransport(),
            cursorStore: MockSyncCursorStore(),
            skipTracker: MockSyncSkipTracker(),
            identityStore: identityStore,
            consentStore: consentStore
        )

        try await coordinator.signOut() // must not throw

        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)
        #expect(identityStore.wasLinked() == false)
        #expect(consentStore.isConsentGiven() == false)
        #expect(authTransport.signInCallCount == 0) // no identity minted just to sign out of nothing
    }

    // MARK: - Race: sign-out landing mid-refresh

    /// The other half of this remediation, alongside the false "backup
    /// resumes automatically" dialog copy fixed elsewhere in the same lot.
    ///
    /// `AnonymousIdentityManager.currentSession()` (reached via
    /// `validAccessToken()`, the very first thing `CloudSyncCoordinator
    /// .syncNow()` calls) reads the stored session, `await`s a network token
    /// refresh, and only THEN calls `persist()` — a Keychain write plus,
    /// for a linked session, `identityStore.setWasLinked(true)`. If
    /// `AnonymousIdentityManager.signOut()` lands on this SAME actor
    /// instance while that refresh is suspended, actor reentrance lets it
    /// run to completion (Keychain deleted, `wasLinked` reset to `false`)
    /// before the refresh resumes. Without a guard, the refresh's `persist()`
    /// then silently rewrites both — resurrecting exactly what sign-out just
    /// erased, with no error anywhere. The next cycle's demotion guard
    /// (`currentSession()`'s `guard stored.isAnonymous else { throw
    /// .reauthenticationRequired }`) would then see a `wasLinked == true`
    /// marker with an inconsistent session and lock the learner into a
    /// forced reconnect — the exact lock-out
    /// `syncAfterSignOutDoesNotThrowAndMintsFreshIdentity` above proves is
    /// closed for the ORDINARY (non-racing) case.
    ///
    /// `AuthRefreshGate`/`GatedAuthTransport` below reproduce the race
    /// deterministically: the refresh genuinely suspends, `signOut()` is
    /// awaited to full completion WHILE it is suspended, and only then is
    /// the refresh released to resume — proving this is a true mid-await
    /// interleaving, not a coincidence of scheduling.
    @Test("RACE: signOut() landing while a token refresh is in flight is not undone once the refresh resumes")
    func signOutDuringInFlightRefreshIsNotUndone() async throws {
        // Close enough to expiry (default `needsRefresh()` margin is 60s)
        // that the very first `validAccessToken()` call below must refresh
        // it rather than reuse it as-is.
        let staleSession = makeSession(expiresIn: 30, isAnonymous: false)
        let refreshedSession = SyncSession(
            userID: staleSession.userID,
            accessToken: "refreshed-access-token",
            refreshToken: "refreshed-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            isAnonymous: false
        )
        let keychain = MockKeychainStore()
        try seed(staleSession, into: keychain)
        let identityStore = MockSyncIdentityStore(wasLinked: true)

        let gate = AuthRefreshGate()
        let transport = GatedAuthTransport(gate: gate, refreshResult: refreshedSession)
        let identity = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: identityStore)

        // Kicks off the refresh; suspends inside `GatedAuthTransport.refreshSession`.
        let refreshTask = Task { try await identity.validAccessToken() }

        // Wait until the refresh is genuinely IN FLIGHT before signing out —
        // proves this is a mid-refresh race, not a call that happens to
        // land before the refresh even starts.
        await gate.waitUntilCalled()
        try await identity.signOut()
        gate.release()

        // The suspended refresh must surface as a failure (its result is
        // stale — the device just deliberately disconnected) rather than
        // silently succeeding with a resurrected session.
        await #expect(throws: SyncAuthError.reauthenticationRequired) {
            try await refreshTask.value
        }

        // The real proof: `signOut()`'s erasure survives the refresh that
        // was in flight when it ran — nothing revived the Keychain entry or
        // the `wasLinked` marker.
        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)
        #expect(identityStore.wasLinked() == false)
    }
}

// MARK: - AuthRefreshGate / GatedAuthTransport

/// Same two-signal gate pattern as `PullGate`/`GatedPullTransport` in
/// `CloudSyncCoordinatorTests.swift`, but for `SupabaseAuthTransport
/// .refreshSession` instead of a pull's `fetchRows` — lets
/// `signOutDuringInFlightRefreshIsNotUndone` land a real `signOut()` call
/// WHILE `AnonymousIdentityManager.currentSession()` is genuinely suspended
/// inside a token refresh, not merely before or after it. `@unchecked
/// Sendable`: guarded entirely by `NSLock`, same justification as `PullGate`.
private final class AuthRefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasBeenCalled = false
    private var calledContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Resumes once `GatedAuthTransport.refreshSession` has been entered.
    /// Called by the test, from OUTSIDE the suspended refresh task.
    func waitUntilCalled() async {
        let alreadyCalled: Bool = lock.withLock { hasBeenCalled }
        if alreadyCalled { return }
        await withCheckedContinuation { continuation in
            lock.withLock {
                if hasBeenCalled {
                    continuation.resume()
                } else {
                    calledContinuation = continuation
                }
            }
        }
    }

    /// Called by `GatedAuthTransport.refreshSession` itself, the instant
    /// it's entered — signals `waitUntilCalled()` and then blocks the
    /// CALLER (the suspended refresh) until `release()`.
    func signalCalledThenWaitForRelease() async {
        let toResume: CheckedContinuation<Void, Never>? = lock.withLock {
            hasBeenCalled = true
            let continuation = calledContinuation
            calledContinuation = nil
            return continuation
        }
        toResume?.resume()

        let alreadyReleased: Bool = lock.withLock { isReleased }
        if alreadyReleased { return }
        await withCheckedContinuation { continuation in
            lock.withLock {
                if isReleased {
                    continuation.resume()
                } else {
                    releaseContinuation = continuation
                }
            }
        }
    }

    /// Releases the call blocked in `signalCalledThenWaitForRelease()` —
    /// called by the test once `signOut()` has been awaited to completion.
    func release() {
        let toResume: CheckedContinuation<Void, Never>? = lock.withLock {
            isReleased = true
            let continuation = releaseContinuation
            releaseContinuation = nil
            return continuation
        }
        toResume?.resume()
    }
}

/// A `SupabaseAuthTransport` whose `refreshSession` blocks on `gate` until
/// released, then returns `refreshResult`. Every other method throws — only
/// `refreshSession` is exercised by the race test this exists for.
/// `@unchecked Sendable`: `gate`/`refreshResult` are both immutable `let`s.
private final class GatedAuthTransport: SupabaseAuthTransport, @unchecked Sendable {
    let gate: AuthRefreshGate
    let refreshResult: SyncSession

    init(gate: AuthRefreshGate, refreshResult: SyncSession) {
        self.gate = gate
        self.refreshResult = refreshResult
    }

    func signInAnonymously() async throws -> SyncSession {
        throw SyncAuthError.invalidResponse
    }

    func refreshSession(refreshToken: String) async throws -> SyncSession {
        await gate.signalCalledThenWaitForRelease()
        return refreshResult
    }

    func linkAppleIdentity(idToken: String, rawNonce: String, accessToken: String) async throws -> SyncSession {
        throw SyncAuthError.invalidResponse
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> SyncSession {
        throw SyncAuthError.invalidResponse
    }
}
