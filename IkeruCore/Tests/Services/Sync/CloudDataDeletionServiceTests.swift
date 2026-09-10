import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Suite name deliberately does not collide with any other token in the CI
/// `--filter` regex (`.github/workflows/ci.yml`'s green-subset step) — it
/// must not accidentally match an existing alternation branch (e.g. it must
/// not contain "Sync" as a standalone match, which several existing filter
/// terms do substring-match against). "CloudDataDeletion" is now itself one
/// of the alternation terms in that filter, run alongside `CloudSyncCoordinator`.
@Suite("CloudDataDeletion")
struct CloudDataDeletionServiceTests {

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

    /// Seeds a `MockKeychainStore` with an already-valid session, exactly
    /// as `AnonymousIdentityManager` would have persisted it itself (same
    /// key, same `SyncJSON` codec) — see
    /// `AnonymousIdentityManagerTests.loadsStoredSessionWithoutSigningInAgain`
    /// for the identical pattern this is copied from.
    private func seed(_ session: SyncSession, into keychain: MockKeychainStore) throws {
        let data = try SyncJSON.encoder.encode(session)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)
    }

    @Test("Nominal success: deletes server-side, then forgets the local session")
    func nominalSuccessDeletesThenForgetsSession() async throws {
        let session = makeSession()
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)

        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        try await service.deleteAllCloudData()

        #expect(deletionTransport.callCount == 1)
        #expect(deletionTransport.lastAccessToken == session.accessToken)
        // Session purged locally only after server success.
        #expect(try keychain.load(key: SyncKeychainKeys.session) == nil)
    }

    @Test("No session ever existed: no-op success that never mints an identity")
    func noSessionSucceedsAsNoOp() async throws {
        let keychain = MockKeychainStore()
        // Sign-in is set up to SUCCEED here on purpose. The empty keychain
        // is the only thing that should decide this case, and the
        // assertions below prove it: an empty keychain means "nothing was
        // ever backed up", so the service must return without either
        // calling the deletion endpoint or signing in.
        let authTransport = MockSupabaseAuthTransport(signInResult: .success(makeSession()))
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        try await service.deleteAllCloudData() // must not throw

        #expect(deletionTransport.callCount == 0)
        // Minting an identity here would be actively harmful, not merely
        // wasteful: the deletion would then target a brand-new EMPTY user
        // and report success, which is the "erased the wrong account"
        // failure mode this whole code path is shaped to avoid.
        #expect(authTransport.signInCallCount == 0)
    }

    @Test("Stored session that cannot be refreshed: throws instead of claiming success")
    func unrefreshableSessionThrowsRatherThanFakingSuccess() async throws {
        let keychain = MockKeychainStore()
        // A session that exists but is already expired, so a refresh is
        // required — and that refresh fails (offline, or the refresh token
        // was rejected).
        try seed(makeSession(expiresIn: -3600), into: keychain)

        let authTransport = MockSupabaseAuthTransport(
            signInResult: .success(makeSession()),
            refreshResult: .failure(SyncAuthError.invalidResponse)
        )
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        // This is the regression this test exists for. The earlier version
        // swallowed every token failure as "nothing to delete", so an
        // offline learner was told their data had been erased while every
        // row was still on the server — an untrue claim about a GDPR
        // erasure request.
        await #expect(throws: (any Error).self) {
            try await service.deleteAllCloudData()
        }

        #expect(deletionTransport.callCount == 0)
        // No fallback sign-in: the real rows still belong to the stored
        // identity, and a fresh one could never address them.
        #expect(authTransport.signInCallCount == 0)
        // The session stays put so a later retry can still target it.
        #expect(try keychain.load(key: SyncKeychainKeys.session) != nil)
    }

    @Test("Server failure: propagates the error and the local session survives")
    func serverFailurePropagatesAndKeepsSession() async throws {
        let session = makeSession()
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)

        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport(
            errorToThrow: CloudDeletionError.requestFailed(status: 500, body: "boom")
        )
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        await #expect(throws: CloudDeletionError.self) {
            try await service.deleteAllCloudData()
        }

        // The whole point: a failed server-side deletion must NOT purge the
        // learner's only local proof of which server-side user_id was
        // theirs, or a retry would orphan the real data forever.
        #expect(try keychain.load(key: SyncKeychainKeys.session) != nil)
    }

    @Test("A second call after a successful deletion does not throw (idempotent)")
    func secondCallAfterSuccessIsIdempotent() async throws {
        let session = makeSession()
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)

        let authTransport = MockSupabaseAuthTransport(signInResult: .success(makeSession()))
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        try await service.deleteAllCloudData()
        try await service.deleteAllCloudData() // must not throw

        // The first call purged the session, so the second finds an empty
        // keychain and stops there. Tapping the button twice therefore does
        // NOT mint a throwaway identity just to delete it again — the
        // second tap is genuinely free, and no new server-side user is
        // created as a side effect of asking to be forgotten.
        #expect(deletionTransport.callCount == 1)
        #expect(authTransport.signInCallCount == 0)
    }

    // MARK: - 2026-08 lot-3 round-2 remediation, CRITIQUE: restored-device deletion

    /// The core scenario the round-2 critique proved by probe: a learner
    /// links Apple on device A, restores that backup onto device B (empty
    /// Keychain, `wasLinked` restored to `true` via `UserDefaults`), then
    /// taps "Delete my data from the server." Before this fix,
    /// `existingSessionAccessToken() == nil` alone made this a silent
    /// no-op success — `SettingsView` would show a green "your data has
    /// been deleted" toast while the account, the Apple identity, and every
    /// row survived untouched on the server. This is the regression test
    /// for that: a device that has EVER held a linked session must get a
    /// loud, attributable error instead of an unverified success claim.
    @Test("CRITIQUE: restored device (empty Keychain, wasLinked marker true) throws reauthenticationRequired instead of a silent no-op success")
    func restoredDeviceThrowsInsteadOfSilentNoOp() async throws {
        let keychain = MockKeychainStore() // empty — exactly a fresh restore's Keychain state
        let authTransport = MockSupabaseAuthTransport(signInResult: .success(makeSession()))
        let identity = AnonymousIdentityManager(
            transport: authTransport,
            keychain: keychain,
            identityStore: MockSyncIdentityStore(wasLinked: true) // the marker that DOES survive a restore
        )
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        await #expect(throws: SyncAuthError.reauthenticationRequired) {
            try await service.deleteAllCloudData()
        }

        // No fabricated success, and definitely no accidental deletion
        // request or fallback sign-in fired along the way.
        #expect(deletionTransport.callCount == 0)
        #expect(authTransport.signInCallCount == 0)
    }

    /// The mirror image, spelled out end-to-end (not just "the flag flipped
    /// back to false"): after a genuinely SUCCESSFUL deletion of a
    /// previously-linked account, this device must still be able to sync
    /// anonymously afterward. Without resetting `wasLinked`,
    /// `forgetSession()`'s own demotion guard would otherwise treat this
    /// exact post-deletion state — empty Keychain, `wasLinked == true` —
    /// as "a restored device whose real account is still out there," and
    /// permanently lock the device out with `reauthenticationRequired` on
    /// every future `currentSession()` call. That would be a learner who
    /// asked to delete their account never being able to use cloud sync
    /// again, on ANY account.
    @Test("CRITIQUE item 4: after a successful deletion, this device can mint a fresh anonymous identity again (wasLinked marker was reset)")
    func successfulDeletionAllowsFreshAnonymousSyncAfterward() async throws {
        let session = makeSession(isAnonymous: false) // a LINKED session, as a restored-and-relinked device would have
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)
        let identityStore = MockSyncIdentityStore(wasLinked: true)

        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: identityStore)
        let deletionTransport = MockCloudDeletionTransport()
        let service = CloudDataDeletionService(modelContainer: try makeContainer(), identity: identity, transport: deletionTransport)

        try await service.deleteAllCloudData()
        #expect(identityStore.wasLinked() == false, "the marker must be cleared once the account it protected no longer exists")

        // The real proof: a fresh anonymous mint must now succeed instead
        // of hitting the Critique #1 demotion guard.
        let freshSession = makeSession()
        authTransport.signInResult = .success(freshSession)
        let token = try await identity.validAccessToken()

        #expect(token == freshSession.accessToken)
        #expect(authTransport.signInCallCount == 1)
    }

    // MARK: - CRITIQUE B, call site (a): markEverythingUnsynced

    /// The other half of the CRITIQUE B fix (`SyncModelActor.markEverythingUnsynced()`'s
    /// doc comment) — this is the deletion-service call site, distinct from
    /// the `CloudSyncCoordinator` seed-path call site covered by
    /// `CloudSyncCoordinatorTests`. Proves `deleteAllCloudData()` itself
    /// clears `syncedAt` locally, not just the server-side rows and the
    /// pull cursors — without this, a card already `syncedAt`-stamped from
    /// the account that was just erased would read as "already synced" to
    /// `SyncModelActor.pushDirtyCards`'s delta filter forever after.
    @Test("A successful deletion marks every local row unsynced, not just the server-side rows and cursors")
    @MainActor
    func deletionMarksLocalRowsUnsynced() async throws {
        let session = makeSession()
        let keychain = MockKeychainStore()
        try seed(session, into: keychain)

        let authTransport = MockSupabaseAuthTransport()
        let identity = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: MockSyncIdentityStore())
        let deletionTransport = MockCloudDeletionTransport()
        let container = try makeContainer()

        // A card that looks fully synced — exactly what's left behind on
        // disk after a normal push to the account that's about to be
        // erased.
        let context = container.mainContext
        let profile = UserProfile(displayName: "Learner")
        context.insert(profile)
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        card.syncedAt = card.updatedAt
        context.insert(card)
        let log = ReviewLog(card: card, grade: .good, responseTimeMs: 500)
        log.syncedAt = log.updatedAt
        context.insert(log)
        // Same shape for `text_imports` (2026-08-19). This table is the one
        // that carries the learner's own prose, so a `syncedAt` left pointing
        // at the erased account is the worst version of CRITIQUE B: after
        // opting back in, `pushDirtyTextImports` reads every import as
        // "already synced" and the new account's backup silently contains no
        // text at all — while the reading journal on the device still shows
        // them, so nothing looks wrong until a reinstall.
        let textImport = TextImport(content: "猫が好きです。")
        textImport.syncedAt = textImport.updatedAt
        context.insert(textImport)
        try context.save()

        let service = CloudDataDeletionService(modelContainer: container, identity: identity, transport: deletionTransport)
        try await service.deleteAllCloudData()

        let freshContext = ModelContext(container)
        let cards = try freshContext.fetch(FetchDescriptor<Card>())
        let logs = try freshContext.fetch(FetchDescriptor<ReviewLog>())
        let profiles = try freshContext.fetch(FetchDescriptor<UserProfile>())
        let imports = try freshContext.fetch(FetchDescriptor<TextImport>())

        #expect(cards.first?.syncedAt == nil)
        #expect(logs.first?.syncedAt == nil)
        #expect(profiles.first?.syncedAt == nil)
        #expect(imports.first?.syncedAt == nil,
                "an imported text left marked synced would never be pushed to the new account")
    }
}
