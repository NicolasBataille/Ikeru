import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Lot 3 — Sign in with Apple, and the promotion of an existing anonymous
/// identity onto that account, without losing a row.
///
/// Every cell of the task's transition matrix gets its own test here:
/// (a) nominal link, (b) fresh install, (c) Apple ID already linked
/// elsewhere, (d) errors — plus the two standalone safety fixes this lot
/// introduces: the link_identity guard (§2) and the demotion guard (§3).
///
/// `@MainActor`: the two coordinator-level tests hand back live `@Model`
/// instances (`UserProfile`, `Card`) from their seeding helpers, which are
/// NOT `Sendable` under this package's Swift 6 language mode — same
/// reasoning as `CloudSyncCoordinatorTests`'s own top-of-file comment.
///
/// Suite name deliberately does NOT contain "AnonymousIdentityManager",
/// "CloudSyncCoordinator", or "CloudDataDeletion" — those are pre-existing
/// CI `--filter` terms in `.github/workflows/ci.yml`'s green subset.
/// This suite's own name (`AppleIdentityLinking`) is a separate, explicit
/// term in that same filter list, alongside `SupabaseAuthTransportRequestShape`
/// — both added as part of this lot's remediation and confirmed to run
/// green in that filtered subset (630/630 as of the lot-3 verification pass).
@Suite("AppleIdentityLinking")
@MainActor
struct AppleIdentityLinkingTests {

    private func makeSession(userID: UUID = UUID(), expiresIn: TimeInterval = 3600, isAnonymous: Bool = true) -> SyncSession {
        SyncSession(
            userID: userID,
            accessToken: "access-\(UUID().uuidString)",
            refreshToken: "refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(expiresIn),
            isAnonymous: isAnonymous
        )
    }

    private func seed(_ session: SyncSession, in keychain: MockKeychainStore) throws {
        let data = try SyncJSON.encoder.encode(session)
        try keychain.save(key: SyncKeychainKeys.session, value: String(data: data, encoding: .utf8)!)
    }

    // MARK: - (a) Nominal link: anonymous + local data → linking

    @Test("(a) Nominal: an existing anonymous session links Apple and keeps the SAME user_id")
    func nominalLinkKeepsSameUserID() async throws {
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        let linked = makeSession(userID: anonID, isAnonymous: false) // SAME user_id
        let transport = MockSupabaseAuthTransport(linkAppleResult: .success(linked))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .linkedExistingIdentity(let userID) = outcome else {
            Issue.record("Expected .linkedExistingIdentity, got \(outcome)")
            return
        }
        #expect(userID == anonID)
        #expect(transport.linkAppleCallCount == 1)
        #expect(transport.signInWithAppleCallCount == 0)
        #expect(transport.lastLinkAccessToken == anon.accessToken)
        #expect(transport.lastAppleIDToken == "ID_TOKEN")
        // The RAW nonce, not a hash of it — hashing only ever happens on
        // the app-side `ASAuthorizationAppleIDRequest.nonce`, never here.
        #expect(transport.lastAppleRawNonce == "RAW_NONCE")

        // The adopted session really is persisted (not just cached in
        // memory) and now reports `isAnonymous == false`.
        let raw = try #require(try keychain.load(key: SyncKeychainKeys.session))
        let persisted = try SyncJSON.decoder.decode(SyncSession.self, from: Data(raw.utf8))
        #expect(persisted.userID == anonID)
        #expect(persisted.isAnonymous == false)
        #expect(try await manager.currentUserID() == anonID)
    }

    @Test("(a) Nominal link, at the coordinator level: same user_id does NOT trigger the identity-change reset — cursors survive untouched")
    func nominalLinkDoesNotTriggerIdentityChangeReset() async throws {
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        let linked = makeSession(userID: anonID, isAnonymous: false)
        let transport = MockSupabaseAuthTransport(linkAppleResult: .success(linked))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        // `identityStore` already remembers the anon user_id from a PRIOR
        // sync cycle (as it would on a real device that synced before
        // linking) — the coordinator must see NO change after linking,
        // since linking preserved the same user_id.
        let identityStore = MockSyncIdentityStore(lastKnownUserID: anonID)
        var cursors: [String: SyncCursorPosition] = [:]
        for table in SyncPullActor.pullOrder {
            cursors[table] = SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)), id: UUID())
        }
        let cursorStore = MockSyncCursorStore(cursors: cursors)
        let pullTransport = MockSyncPullTransport() // nothing queued — every table returns []

        let container = try makeEmptyContainer()
        let coordinator = CloudSyncCoordinator(
            modelContainer: container,
            identity: manager,
            transport: MockSyncDataTransport(),
            pullTransport: pullTransport,
            cursorStore: cursorStore,
            skipTracker: MockSyncSkipTracker(),
            identityStore: identityStore,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        _ = await coordinator.syncNow()

        for table in SyncPullActor.pullOrder {
            #expect(cursorStore.cursor(forTable: table) != nil, "table \(table) cursor was reset even though linking preserved the user_id")
        }
    }

    // MARK: - (b) Fresh install → Sign in with Apple

    @Test("(b) Fresh install: no local session ⇒ plain sign-in, no link_identity, no Authorization")
    func freshInstallSignsInPlainly() async throws {
        let existingAccountID = UUID() // may already exist server-side; irrelevant here
        let session = makeSession(userID: existingAccountID, isAnonymous: false)
        let transport = MockSupabaseAuthTransport(signInWithAppleResult: .success(session))
        let manager = AnonymousIdentityManager(transport: transport, keychain: MockKeychainStore(), identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .switchedIdentity(let userID, let wasAlreadyLinkedElsewhere) = outcome else {
            Issue.record("Expected .switchedIdentity, got \(outcome)")
            return
        }
        #expect(userID == existingAccountID)
        #expect(wasAlreadyLinkedElsewhere == false)
        #expect(transport.linkAppleCallCount == 0)
        #expect(transport.signInWithAppleCallCount == 1)
    }

    // MARK: - (c) Apple ID already linked to another (populated) account

    @Test("(c) Already linked elsewhere: link is refused, falls back to plain sign-in AS that other account")
    func alreadyLinkedElsewhereFallsBackToSignIn() async throws {
        let anonID = UUID()
        let populatedAccountID = UUID() // a DIFFERENT, existing account
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        let transport = MockSupabaseAuthTransport(
            linkAppleResult: .failure(SyncAuthError.identityAlreadyLinked(status: 422, body: "{}")),
            signInWithAppleResult: .success(makeSession(userID: populatedAccountID, isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .switchedIdentity(let userID, let wasAlreadyLinkedElsewhere) = outcome else {
            Issue.record("Expected .switchedIdentity, got \(outcome)")
            return
        }
        #expect(userID == populatedAccountID)
        #expect(wasAlreadyLinkedElsewhere == true)
        #expect(transport.linkAppleCallCount == 1) // link WAS attempted first
        #expect(transport.signInWithAppleCallCount == 1) // then the fallback
        #expect(try await manager.currentUserID() == populatedAccountID)
    }

    @Test("(c) At the coordinator level: identity change to a POPULATED account still pushes stale local rows — regression test for the seedFromLocal-only gate")
    func identityChangeToPopulatedAccountStillMarksEverythingUnsynced() async throws {
        let container = try makeContainerWithProfileAndCard()
        let (profile, card) = container.seeded

        let previousUserID = UUID() // what this device last synced as (anon)
        let newUserID = UUID() // the populated account Apple linking switched to

        let session = makeSession(userID: newUserID, isAnonymous: false)
        let transport = MockSupabaseAuthTransport()
        // Pre-seed the Keychain directly with the "already switched" session
        // so `currentUserID()` reports `newUserID` without a network call —
        // equivalent to `linkOrSignInWithApple` having already run and
        // adopted it.
        let seededKeychain = MockKeychainStore()
        try seed(session, in: seededKeychain)
        let manager = AnonymousIdentityManager(transport: transport, keychain: seededKeychain, identityStore: MockSyncIdentityStore())

        let identityStore = MockSyncIdentityStore(lastKnownUserID: previousUserID)
        var cursors: [String: SyncCursorPosition] = [:]
        for table in SyncPullActor.pullOrder {
            cursors[table] = SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)), id: UUID())
        }
        let cursorStore = MockSyncCursorStore(cursors: cursors)

        // The NEW account is NOT empty — a remote `profiles` row is queued,
        // so `SyncPullActor` rule 1 (seededFromLocal) does NOT fire. This is
        // exactly what distinguishes case (c) from lot 2's original
        // re-provisioning scenario (always an EMPTY new account).
        let pullTransport = MockSyncPullTransport()
        let remoteProfile = UserProfile(displayName: "Remote (populated account)")
        remoteProfile.updatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        var profileRow = try SyncPayloadBuilder.row(for: remoteProfile)
        profileRow["server_updated_at"] = .string(SyncJSON.iso8601String(remoteProfile.updatedAt))
        pullTransport.enqueueRows([profileRow], forTable: "profiles")

        let dataTransport = MockSyncDataTransport()
        let coordinator = CloudSyncCoordinator(
            modelContainer: container.modelContainer,
            identity: manager,
            transport: dataTransport,
            pullTransport: pullTransport,
            cursorStore: cursorStore,
            skipTracker: MockSyncSkipTracker(),
            identityStore: identityStore,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        let outcome = await coordinator.syncNow()

        guard case .success(_, let pull) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        // The critical distinction from the lot-2 scenario: this pull is
        // `.applied`, NOT `.seededFromLocal` — the account was populated.
        if case .seededFromLocal = pull {
            Issue.record("Expected an .applied pull (populated remote account), got .seededFromLocal")
        }

        // The regression this test exists for: WITHOUT the fix, a card
        // already stamped `syncedAt` from the OLD identity reads as
        // "already synced" forever once `seededFromLocal` never fires.
        let pushedCardIDs = dataTransport.rows(forTable: "cards").compactMap { row -> String? in
            guard case .string(let value) = row["id"] else { return nil }
            return value
        }
        #expect(pushedCardIDs.contains(card.id.uuidString))
        _ = profile
    }

    // MARK: - The link_identity guard (§2)

    @Test("GUARD: a link call that returns a DIFFERENT user_id is refused, never adopted")
    func guardRefusesMismatchedUserID() async throws {
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        // Simulates the server silently ignoring `link_identity: true` —
        // HTTP 2xx, but for a completely unrelated user_id.
        let wrongUserID = UUID()
        let transport = MockSupabaseAuthTransport(linkAppleResult: .success(makeSession(userID: wrongUserID, isAnonymous: false)))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: AppleLinkError.linkIdentityGuardTripped) {
            _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")
        }

        // Nothing was adopted — the ORIGINAL anonymous session is still the
        // one on disk, byte for byte.
        let raw = try #require(try keychain.load(key: SyncKeychainKeys.session))
        let persisted = try SyncJSON.decoder.decode(SyncSession.self, from: Data(raw.utf8))
        #expect(persisted.userID == anonID)
        #expect(persisted.accessToken == anon.accessToken)
        // A guard trip must NEVER fall back to a plain sign-in — that would
        // adopt the very identity switch the guard exists to refuse.
        #expect(transport.signInWithAppleCallCount == 0)
    }

    // MARK: - (d) Errors

    @Test("(d) Apple token rejected by the server: propagates as a distinguishable error, nothing adopted")
    func rejectedAppleTokenPropagates() async throws {
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        let transport = MockSupabaseAuthTransport(
            linkAppleResult: .failure(SyncAuthError.requestFailed(status: 401, errorCode: "invalid_grant", body: ""))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: SyncAuthError.self) {
            _ = try await manager.linkOrSignInWithApple(idToken: "BAD_TOKEN", rawNonce: "RAW_NONCE")
        }

        // The pre-existing anonymous session is untouched.
        #expect(try await manager.currentUserID() == anonID)
        // A rejected id_token is NOT the "already linked elsewhere" signal —
        // must not fall back to a plain sign-in either.
        #expect(transport.signInWithAppleCallCount == 0)
    }

    @Test("(d) Network failure while linking: propagates, nothing adopted, no fallback")
    func networkFailureWhileLinkingPropagates() async throws {
        struct NetworkFailure: Error, Equatable {}
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)

        let transport = MockSupabaseAuthTransport(linkAppleResult: .failure(NetworkFailure()))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: NetworkFailure.self) {
            _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")
        }
        #expect(transport.signInWithAppleCallCount == 0)
    }

    // MARK: - The demotion guard (§3) — a LINKED session must never be

    // silently re-minted as anonymous on a rejected refresh.

    @Test("DEMOTION GUARD: a LINKED session's rejected refresh throws reauthenticationRequired, never mints a fresh anonymous identity")
    func linkedSessionRejectedRefreshThrowsInsteadOfReminting() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false) // LINKED, about to expire
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            signInResult: .success(makeSession()), // would mint an unrelated identity if ever reached
            refreshResult: .failure(SyncAuthError.requestFailed(status: 401, errorCode: "invalid_grant", body: ""))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: SyncAuthError.reauthenticationRequired) {
            _ = try await manager.validAccessToken()
        }

        #expect(transport.signInCallCount == 0, "a LINKED session must never be silently re-minted as anonymous")
        // The old (linked) session is still what's on disk.
        let raw = try #require(try keychain.load(key: SyncKeychainKeys.session))
        let persisted = try SyncJSON.decoder.decode(SyncSession.self, from: Data(raw.utf8))
        #expect(persisted.userID == linkedID)
    }

    @Test("Baseline preserved: an ANONYMOUS session's rejected refresh still mints a fresh anonymous identity, unchanged from lot 1/2")
    func anonymousSessionRejectedRefreshStillRemints() async throws {
        let expiring = makeSession(expiresIn: 10, isAnonymous: true)
        let fresh = makeSession(isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            signInResult: .success(fresh),
            refreshResult: .failure(SyncAuthError.requestFailed(status: 401, errorCode: "invalid_grant", body: ""))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let userID = try await manager.currentUserID()

        #expect(userID == fresh.userID)
        #expect(transport.signInCallCount == 1)
    }

    // MARK: - The dead-session reconnect path

    @Test("A LINKED session's dead refresh IS reachable via Apple sign-in — the recovery path for reauthenticationRequired actually works")
    func deadLinkedSessionReconnectsViaAppleSignIn() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        // The refresh attempt made INSIDE `linkOrSignInWithApple`'s own
        // `existingSessionAccessToken()` call is rejected the same way...
        let transport = MockSupabaseAuthTransport(
            refreshResult: .failure(SyncAuthError.requestFailed(status: 401, errorCode: "invalid_grant", body: "")),
            // ...but signing in with Apple again reaches the SAME account:
            // GoTrue returns the same user_id for the same Apple identity.
            signInWithAppleResult: .success(makeSession(userID: linkedID, isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .reauthenticatedAfterDeadSession(let userID) = outcome else {
            Issue.record("Expected .reauthenticatedAfterDeadSession, got \(outcome)")
            return
        }
        #expect(userID == linkedID)
        // Never attempted `linkAppleIdentity` — there was no valid access
        // token to link FROM.
        #expect(transport.linkAppleCallCount == 0)
        #expect(transport.signInWithAppleCallCount == 1)
        #expect(try await manager.currentUserID() == linkedID)
    }

    @Test("A 5xx / network failure while refreshing does NOT fall back to plain sign-in — only an explicit rejection does")
    func serverErrorWhileRefreshingDoesNotFallBackToSignIn() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            refreshResult: .failure(SyncAuthError.requestFailed(status: 503, errorCode: nil, body: "")),
            signInWithAppleResult: .success(makeSession(userID: UUID(), isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        // `existingSessionAccessToken()`'s OWN refresh attempt is what
        // throws here — a 5xx from IT is not in `(400..<500)`, so
        // `linkOrSignInWithApple`'s narrow catch does not match, and the
        // raw error propagates unchanged (never reinterpreted as "no local
        // session"). `.reauthenticationRequired` is a DIFFERENT method's
        // (`currentSession()`) error for a DIFFERENT call path
        // (`validAccessToken()`/`currentUserID()`) — not what this one
        // throws.
        await #expect(throws: SyncAuthError.requestFailed(status: 503, errorCode: nil, body: "")) {
            _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")
        }
        #expect(transport.signInWithAppleCallCount == 0, "a 5xx means \"couldn't tell,\" not \"rejected\" — must not be treated as a dead session")
    }

    // MARK: - Keychain backward compatibility (SyncSession.isAnonymous)

    @Test("A SyncSession persisted BEFORE lot 3 (no isAnonymous key) decodes with isAnonymous == true")
    func preLot3PersistedSessionDefaultsToAnonymousTrue() throws {
        let userID = UUID()
        // Deliberately hand-built JSON with NO "isAnonymous" key — exactly
        // what every Keychain entry written before this lot looks like.
        let json = """
        {
          "userID": "\(userID.uuidString)",
          "accessToken": "old-access-token",
          "refreshToken": "old-refresh-token",
          "expiresAt": "\(SyncJSON.iso8601String(Date().addingTimeInterval(3600)))"
        }
        """
        let decoded = try SyncJSON.decoder.decode(SyncSession.self, from: Data(json.utf8))
        #expect(decoded.isAnonymous == true)
        #expect(decoded.userID == userID)
    }

    // MARK: - Remediation, Critique #1: the wasLinked marker survives an
    // empty Keychain (iPhone A links → iCloud restore onto iPhone B).

    @Test("CRITIQUE #1: empty Keychain + wasLinked marker true (iCloud-restore-onto-new-device) throws reauthenticationRequired, never mints an anonymous ghost")
    func emptyKeychainWithWasLinkedMarkerThrowsInsteadOfMinting() async throws {
        let keychain = MockKeychainStore() // nothing seeded — the Keychain entry never restores (ThisDeviceOnly)
        let identityStore = MockSyncIdentityStore(wasLinked: true) // UserDefaults DID restore this marker
        let transport = MockSupabaseAuthTransport(signInResult: .success(makeSession())) // would mint if ever reached
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: identityStore)

        await #expect(throws: SyncAuthError.reauthenticationRequired) {
            _ = try await manager.validAccessToken()
        }
        #expect(transport.signInCallCount == 0, "must never mint an anonymous ghost identity on a device that was previously linked")
    }

    @Test("Baseline preserved: empty Keychain + wasLinked marker false (genuine first install) still mints anonymously — no regression")
    func emptyKeychainNeverLinkedStillMintsAnonymously() async throws {
        let keychain = MockKeychainStore()
        let identityStore = MockSyncIdentityStore(wasLinked: false)
        let fresh = makeSession()
        let transport = MockSupabaseAuthTransport(signInResult: .success(fresh))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: identityStore)

        let userID = try await manager.currentUserID()

        #expect(userID == fresh.userID)
        #expect(transport.signInCallCount == 1)
    }

    @Test("The wasLinked marker is set the moment a linked session is adopted, and isLinkedToExternalIdentity() reports the bound state correctly")
    func wasLinkedMarkerSetOnAdoptionAndBoundStateAccessor() async throws {
        let anonID = UUID()
        let anon = makeSession(userID: anonID, isAnonymous: true)
        let keychain = MockKeychainStore()
        try seed(anon, in: keychain)
        let identityStore = MockSyncIdentityStore()
        #expect(identityStore.wasLinked() == false)

        let linked = makeSession(userID: anonID, isAnonymous: false)
        let transport = MockSupabaseAuthTransport(linkAppleResult: .success(linked))
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: identityStore)

        #expect(await manager.isLinkedToExternalIdentity() == false, "still anonymous before linking")

        _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        #expect(identityStore.wasLinked() == true, "the persisted marker must survive even if the Keychain entry is later lost")
        #expect(await manager.isLinkedToExternalIdentity() == true, "the bound accessor must reflect the just-adopted linked session")
    }

    // MARK: - Remediation, Important #3: a 429 must not be treated as a dead session

    @Test("IMPORTANT #3: a 429 (rate limit) while refreshing during Apple link does NOT fall back to plain sign-in — propagates so the caller can retry")
    func rateLimitWhileLinkingDoesNotFallBackToSignIn() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            refreshResult: .failure(SyncAuthError.requestFailed(status: 429, errorCode: "over_request_rate_limit", body: "")),
            signInWithAppleResult: .success(makeSession(userID: UUID(), isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        await #expect(throws: SyncAuthError.requestFailed(status: 429, errorCode: "over_request_rate_limit", body: "")) {
            _ = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")
        }
        #expect(
            transport.signInWithAppleCallCount == 0,
            "a 429 means retry-later, not dead — must not orphan a live linked/anonymous session by minting a brand-new unrelated identity via plain sign-in"
        )
    }

    @Test("IMPORTANT #3 baseline: a 403 while refreshing during Apple link IS still treated as a dead session — falls back to reconnect via Apple")
    func status403WhileLinkingStillFallsBackToSignIn() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            refreshResult: .failure(SyncAuthError.requestFailed(status: 403, errorCode: nil, body: "")),
            signInWithAppleResult: .success(makeSession(userID: linkedID, isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .reauthenticatedAfterDeadSession(let userID) = outcome else {
            Issue.record("Expected .reauthenticatedAfterDeadSession, got \(outcome)")
            return
        }
        #expect(userID == linkedID)
        #expect(transport.signInWithAppleCallCount == 1)
    }

    // MARK: - Remediation, Mineur #8: one freshness evaluation, not two

    @Test("MINEUR #8: the access token and previousUserID come from ONE freshness evaluation, not two independent ones (no double refresh)")
    func singleFreshnessEvaluationAvoidsDoubleRefresh() async throws {
        let linkedID = UUID()
        let expiring = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false) // within the 60s default margin
        // The refreshed session ALSO comes back still within the margin —
        // so a SECOND, independently-timed needsRefresh() evaluation would
        // see it as needing refresh AGAIN, which is exactly the race this
        // fix closes.
        let refreshed = makeSession(userID: linkedID, expiresIn: 10, isAnonymous: false)
        let keychain = MockKeychainStore()
        try seed(expiring, in: keychain)

        let transport = MockSupabaseAuthTransport(
            refreshResult: .success(refreshed),
            linkAppleResult: .success(makeSession(userID: linkedID, isAnonymous: false))
        )
        let manager = AnonymousIdentityManager(transport: transport, keychain: keychain, identityStore: MockSyncIdentityStore())

        let outcome = try await manager.linkOrSignInWithApple(idToken: "ID_TOKEN", rawNonce: "RAW_NONCE")

        guard case .linkedExistingIdentity(let userID) = outcome else {
            Issue.record("Expected .linkedExistingIdentity (the guard must NOT trip on a correctly-preserved user_id), got \(outcome)")
            return
        }
        #expect(userID == linkedID)
        #expect(
            transport.refreshCallCount == 1,
            "the access token and previousUserID must be derived from ONE freshness evaluation, not two independent (and independently-timed) ones"
        )
    }

    // MARK: - Remediation, Mineur #5: the reauthenticationRequiredMessage constant

    @Test("MINEUR #5: SyncAuthError.reauthenticationRequiredMessage is exactly the string CloudSyncCoordinator.syncNow() writes to lastErrorMessage — proved end-to-end on the CRITIQUE #1 restore scenario")
    @MainActor
    func reauthenticationRequiredMessageMatchesCoordinatorWrite() async throws {
        let keychain = MockKeychainStore() // empty — the restored-onto-new-device Keychain
        let identityStore = MockSyncIdentityStore(wasLinked: true) // UserDefaults DID restore
        let authTransport = MockSupabaseAuthTransport(signInResult: .success(makeSession())) // would mint if ever reached
        let manager = AnonymousIdentityManager(transport: authTransport, keychain: keychain, identityStore: identityStore)

        let container = try makeEmptyContainer()
        let consentStore = MockSyncConsentStore(consentGiven: true)
        let coordinator = CloudSyncCoordinator(
            modelContainer: container,
            identity: manager,
            transport: MockSyncDataTransport(),
            pullTransport: MockSyncPullTransport(),
            cursorStore: MockSyncCursorStore(),
            skipTracker: MockSyncSkipTracker(),
            identityStore: MockSyncIdentityStore(),
            consentStore: consentStore
        )

        let outcome = await coordinator.syncNow()

        guard case .failure(let message) = outcome else {
            Issue.record("Expected .failure, got \(outcome)")
            return
        }
        #expect(message == SyncAuthError.reauthenticationRequiredMessage)
        #expect(await coordinator.lastErrorMessage() == SyncAuthError.reauthenticationRequiredMessage)
        #expect(authTransport.signInCallCount == 0, "must never mint an anonymous ghost, even routed through the full syncNow() cycle")
    }
}

// MARK: - Fixtures shared across the matrix's coordinator-level tests

extension AppleIdentityLinkingTests {

    @MainActor
    private func makeEmptyContainer() throws -> ModelContainer {
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

    private struct SeededContainer {
        let modelContainer: ModelContainer
        let seeded: (profile: UserProfile, card: Card)
    }

    @MainActor
    private func makeContainerWithProfileAndCard() throws -> SeededContainer {
        let container = try makeEmptyContainer()
        let context = container.mainContext
        let profile = UserProfile(displayName: "Test Learner")
        context.insert(profile)
        try context.save()

        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        // Already carries a `syncedAt` stamp from the OLD identity — exactly
        // what's left on disk by a device that fully synced before the
        // Apple ID turned out to already belong to someone else.
        card.syncedAt = card.updatedAt
        context.insert(card)
        try context.save()

        return SeededContainer(modelContainer: container, seeded: (profile, card))
    }
}
