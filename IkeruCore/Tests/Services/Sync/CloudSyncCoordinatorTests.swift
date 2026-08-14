import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// End-to-end (fake-network) tests for the push engine: consent gating,
/// delta selection per entity class, idempotent `syncedAt` bookkeeping, and
/// throttling. No test in this file touches the network — `syncNow()` is
/// driven entirely by `MockSyncDataTransport` and an `AnonymousIdentityManager`
/// wired to `MockSupabaseAuthTransport` + `MockKeychainStore`.
///
/// The whole suite is `@MainActor`: the seed/verify helpers hand back live
/// `@Model` instances (`UserProfile`, `Card`, `ReviewLog`, …), which are
/// NOT `Sendable` — under this package's Swift 6 language mode (implied by
/// `swift-tools-version: 6.0`, no `swiftLanguageMode` override in
/// `Package.swift`), returning one of those across an actor boundary is a
/// compile error, not a runtime risk. Keeping every helper call on the same
/// (Main) actor as its caller sidesteps that entirely; only
/// `coordinator.syncNow()` — a real cross-actor call into
/// `CloudSyncCoordinator`, which is its own actor — still needs `await`.
@Suite("CloudSyncCoordinator")
@MainActor
struct CloudSyncCoordinatorTests {

    // MARK: - Fixtures

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
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Returns the manager AND its underlying auth mock — most tests only
    /// need the manager, but `consentOffPushesNothing` needs to assert on
    /// `authTransport.signInCallCount` directly (the literal proof that
    /// consent-off means Auth is never contacted at all, not just that no
    /// data rows were pushed).
    private func makeIdentityManager(userID: UUID = UUID()) -> (manager: AnonymousIdentityManager, authTransport: MockSupabaseAuthTransport) {
        let session = SyncSession(
            userID: userID,
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let authTransport = MockSupabaseAuthTransport(signInResult: .success(session))
        let manager = AnonymousIdentityManager(transport: authTransport, keychain: MockKeychainStore())
        return (manager, authTransport)
    }

    /// A `MockSyncCursorStore` pre-seeded with a cursor for every pulled
    /// table — the default `cursorStore` for every coordinator this suite
    /// builds, INCLUDING this file's own CRITIQUE-B / identity
    /// re-provisioning test below (which reaches rule 1 a different way —
    /// by triggering `CloudSyncCoordinator.syncNow()`'s identity-change
    /// check, not by starting cold — see that test's own comment).
    ///
    /// Without this, an unseeded `MockSyncCursorStore()` looks like a
    /// genuine cold start to `SyncPullActor`'s rule 1
    /// (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`),
    /// and every delta-selection test here seeds a non-empty LOCAL store
    /// against an (also unseeded, so "remote empty") `MockSyncPullTransport`
    /// — exactly rule 1's "empty remote + populated local" trigger.
    /// `syncNow()` correctly (CRITIQUE B's fix) marks every row unsynced
    /// before push in that case — right for a genuine fresh/re-provisioned
    /// account, but it silently defeated this suite's push-focused tests
    /// (`cardsDeltaSelection` etc.) BEFORE this fixture was added: their
    /// "already-synced" cards started reading as dirty again, because rule
    /// 1 fired on every single one of them by fixture accident, not by
    /// intent. Pre-seeding every table's cursor makes `isColdStart` false,
    /// so rule 1 never fires here BY ACCIDENT — this suite tests delta
    /// selection on an already-synced device, not rule 1 (that's
    /// `SyncPullDivergenceTests`'s job at the `SyncPullActor` level; this
    /// file's own re-provisioning test below is the coordinator-level
    /// equivalent, reaching rule 1 deliberately through the identity-change
    /// path rather than a bare fixture).
    private static func makeSeededCursorStore() -> MockSyncCursorStore {
        var cursors: [String: SyncCursorPosition] = [:]
        for table in SyncPullActor.pullOrder {
            cursors[table] = SyncCursorPosition(
                timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)),
                id: UUID()
            )
        }
        return MockSyncCursorStore(cursors: cursors)
    }

    private func makeCoordinator(
        container: ModelContainer,
        identity: AnonymousIdentityManager? = nil,
        dataTransport: MockSyncDataTransport = MockSyncDataTransport(),
        pullTransport: MockSyncPullTransport = MockSyncPullTransport(),
        cursorStore: MockSyncCursorStore = CloudSyncCoordinatorTests.makeSeededCursorStore(),
        skipTracker: MockSyncSkipTracker = MockSyncSkipTracker(),
        // A fresh, empty `MockSyncIdentityStore` by default — every test in
        // this suite except the identity-re-provisioning one below hits the
        // "nothing stored yet, just record it" branch on its single
        // `syncNow()` call, which must NOT reset the (seeded, by default)
        // cursor store — see `CloudSyncCoordinator.syncNow()`'s doc comment
        // on that branch. If this default ever starts resetting cursors on
        // a first call, most of this file's delta-selection tests break —
        // that's the regression net for defect 1's fix.
        identityStore: MockSyncIdentityStore = MockSyncIdentityStore(),
        consentStore: MockSyncConsentStore = MockSyncConsentStore(),
        minSyncInterval: TimeInterval = 60
    ) -> CloudSyncCoordinator {
        CloudSyncCoordinator(
            modelContainer: container,
            identity: identity ?? makeIdentityManager().manager,
            transport: dataTransport,
            pullTransport: pullTransport,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            identityStore: identityStore,
            consentStore: consentStore,
            minSyncInterval: minSyncInterval
        )
    }

    // MARK: - Consent gating

    @Test("Consent off: syncNow does nothing — no rows pushed, auth never contacted")
    func consentOffPushesNothing() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        _ = try seedCard(in: container, profile: profile, alreadySynced: false)

        let (identity, authTransport) = makeIdentityManager()
        let dataTransport = MockSyncDataTransport()
        let consentStore = MockSyncConsentStore(consentGiven: false)
        let coordinator = makeCoordinator(
            container: container,
            identity: identity,
            dataTransport: dataTransport,
            consentStore: consentStore
        )

        let outcome = await coordinator.syncNow()

        #expect(outcome == .skippedConsentOff)
        #expect(dataTransport.calls.isEmpty)
        #expect(authTransport.signInCallCount == 0) // consent off ⇒ Supabase Auth is never contacted at all
    }

    // MARK: - Delta selection

    @Test("Consent on: profiles and rpg_states push every time, even when already synced")
    func alwaysPushesProfilesAndRPGStates() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        try markProfileSynced(profile, in: container)

        let dataTransport = MockSyncDataTransport()
        let coordinator = makeCoordinator(
            container: container,
            dataTransport: dataTransport,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        let outcome = await coordinator.syncNow()

        guard case .success = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(dataTransport.rows(forTable: "profiles").count == 1)
        #expect(dataTransport.rows(forTable: "rpg_states").count == 1)
    }

    @Test("A never-synced card is pushed; an already-synced, unmodified card is not")
    func cardsDeltaSelection() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        let dirtyCard = try seedCard(in: container, profile: profile, alreadySynced: false)
        let cleanCard = try seedCard(in: container, profile: profile, alreadySynced: true)

        let dataTransport = MockSyncDataTransport()
        let coordinator = makeCoordinator(
            container: container,
            dataTransport: dataTransport,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        _ = await coordinator.syncNow()

        let pushedIDs = dataTransport.rows(forTable: "cards").compactMap { row -> String? in
            guard case .string(let value) = row["id"] else { return nil }
            return value
        }
        #expect(pushedIDs.contains(dirtyCard.id.uuidString))
        #expect(!pushedIDs.contains(cleanCard.id.uuidString))
    }

    @Test("An already-synced review log (append-only) is never re-pushed")
    func reviewLogsExactDeltaSelection() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        let card = try seedCard(in: container, profile: profile, alreadySynced: false)
        let syncedLog = try seedReviewLog(for: card, in: container, alreadySynced: true)
        let unsyncedLog = try seedReviewLog(for: card, in: container, alreadySynced: false)

        let dataTransport = MockSyncDataTransport()
        let coordinator = makeCoordinator(
            container: container,
            dataTransport: dataTransport,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        _ = await coordinator.syncNow()

        let pushedIDs = dataTransport.rows(forTable: "review_logs").compactMap { row -> String? in
            guard case .string(let value) = row["id"] else { return nil }
            return value
        }
        #expect(pushedIDs.contains(unsyncedLog.id.uuidString))
        #expect(!pushedIDs.contains(syncedLog.id.uuidString))
    }

    @Test("companion_chat_messages is never pushed by this lot, regardless of consent")
    func companionChatMessagesNeverPushed() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        _ = try seedCompanionMessage(profileID: profile.id, in: container)

        let dataTransport = MockSyncDataTransport()
        let coordinator = makeCoordinator(
            container: container,
            dataTransport: dataTransport,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        _ = await coordinator.syncNow()

        #expect(dataTransport.rows(forTable: "companion_chat_messages").isEmpty)
        #expect(dataTransport.calls.allSatisfy { $0.table != "companion_chat_messages" })
    }

    // MARK: - Idempotent bookkeeping

    @Test("A successful push marks the row's syncedAt so a second sync doesn't re-push it")
    func successfulPushMarksSyncedAt() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        let card = try seedCard(in: container, profile: profile, alreadySynced: false)

        let dataTransport = MockSyncDataTransport()
        let consentStore = MockSyncConsentStore(consentGiven: true)
        // minSyncInterval: 0 so the second call isn't throttled — this test
        // is about delta selection after a real push, not about throttling.
        let coordinator = makeCoordinator(container: container, dataTransport: dataTransport, consentStore: consentStore, minSyncInterval: 0)

        _ = await coordinator.syncNow()
        #expect(dataTransport.rows(forTable: "cards").count == 1)

        _ = await coordinator.syncNow()
        // Second sync: the same card must not be pushed again (its syncedAt
        // now equals its updatedAt) — only re-verify via a fresh fetch that
        // the persisted syncedAt was actually written, not just trust the
        // mock's call count.
        let refetched = try fetchCard(id: card.id, in: container)
        #expect(refetched?.syncedAt != nil)
        #expect(dataTransport.rows(forTable: "cards").count == 1) // still just the one push
    }

    // MARK: - Throttle

    @Test("A second syncNow within minSyncInterval is throttled, not pushed twice")
    func throttlesRapidCalls() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        _ = try seedCard(in: container, profile: profile, alreadySynced: false)

        let dataTransport = MockSyncDataTransport()
        let coordinator = makeCoordinator(
            container: container,
            dataTransport: dataTransport,
            consentStore: MockSyncConsentStore(consentGiven: true),
            minSyncInterval: 3600
        )

        let first = await coordinator.syncNow()
        let second = await coordinator.syncNow()

        guard case .success = first else {
            Issue.record("Expected first call to succeed, got \(first)")
            return
        }
        #expect(second == .skippedThrottled)
    }

    // MARK: - CRITIQUE B + identity re-provisioning: a device that HAS
    // already synced (non-nil cursors) still re-seeds cards and logs, not
    // just profiles/rpg_states, once its identity silently changes underneath
    // it

    @Test("Identity re-provisioning: seeded cursors + a changed user_id resets the cursors, so cards and logs — not just profiles/rpg_states — are still pushed to the new account")
    func identityReprovisioningResetsSeededCursorsAndPushesCardsAndLogs() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        // BOTH already carry a `syncedAt` stamp — exactly what's left on
        // disk by a device that fully synced under a PREVIOUS identity.
        // Before defect 1's fix, `pushDirtyCards`/`pushDirtyReviewLogs`'s
        // delta filters read these as "already synced" and pushed NEITHER
        // of them once the identity changed — only `profiles`/`rpg_states`
        // (pushed unconditionally) actually reached the new account.
        let card = try seedCard(in: container, profile: profile, alreadySynced: true)
        let log = try seedReviewLog(for: card, in: container, alreadySynced: true)

        let dataTransport = MockSyncDataTransport()
        // `makeSeededCursorStore()` — NON-nil cursors on every table, the
        // shape a device that has genuinely already synced actually has.
        // A bare `MockSyncCursorStore()` (this test's ORIGINAL fixture,
        // before this fix) can never represent a rejected-refresh-token
        // re-provisioning: that scenario always starts from an
        // already-synced device, and `SyncPullActor`'s rule-1 cold-start
        // guard (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`)
        // cannot fire while any cursor is non-nil — bare cursors made this
        // test pass for the wrong reason (a literal cold start), not
        // because re-provisioning was actually being exercised.
        let cursorStore = CloudSyncCoordinatorTests.makeSeededCursorStore()
        // "Last known" identity from BEFORE the rejected refresh — a
        // DIFFERENT id than the one `identity` below will report.
        let previousUserID = UUID()
        let identityStore = MockSyncIdentityStore(lastKnownUserID: previousUserID)
        // A fresh `AnonymousIdentityManager` that signs in as a DIFFERENT
        // user — standing in for `AnonymousIdentityManager` silently
        // minting a new anonymous identity after its stored refresh token
        // was rejected (that fallback itself is covered independently by
        // `AnonymousIdentityManagerTests.rejectedRefreshFallsBackToSignIn`;
        // this test only needs the OBSERVABLE end state that produces —
        // "the identity manager now reports a user_id this device has
        // never seen before").
        let reprovisionedUserID = UUID()
        let (identity, _) = makeIdentityManager(userID: reprovisionedUserID)

        let coordinator = makeCoordinator(
            container: container,
            identity: identity,
            dataTransport: dataTransport,
            cursorStore: cursorStore,
            identityStore: identityStore,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        let outcome = await coordinator.syncNow()

        guard case .success(_, let pull) = outcome, pull == .seededFromLocal else {
            Issue.record("Expected the identity mismatch to reset the cursors and produce a seeded-from-local pull, got \(outcome)")
            return
        }

        #expect(dataTransport.rows(forTable: "profiles").count == 1)
        // The actual regression this test exists for: BEFORE defect 1's
        // fix, both of these were empty — seeded cursors meant rule 1
        // could never fire at all, regardless of the identity change.
        let pushedCardIDs = dataTransport.rows(forTable: "cards").compactMap { row -> String? in
            guard case .string(let value) = row["id"] else { return nil }
            return value
        }
        let pushedLogIDs = dataTransport.rows(forTable: "review_logs").compactMap { row -> String? in
            guard case .string(let value) = row["id"] else { return nil }
            return value
        }
        #expect(pushedCardIDs.contains(card.id.uuidString))
        #expect(pushedLogIDs.contains(log.id.uuidString))

        // The "remember the new id" half of the fix — not just "reset",
        // but "reset AND stop comparing against the stale id forever after."
        #expect(identityStore.lastKnownUserID() == reprovisionedUserID)
    }

    @Test("setConsent(false) does NOT mark local rows unsynced — server-side data is still correct, so nothing needs re-pushing")
    func consentOffDoesNotMarkRowsUnsynced() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        let card = try seedCard(in: container, profile: profile, alreadySynced: true)

        let coordinator = makeCoordinator(container: container, consentStore: MockSyncConsentStore(consentGiven: true))
        await coordinator.setConsent(false)

        let refetched = try fetchCard(id: card.id, in: container)
        #expect(refetched?.syncedAt != nil)
    }

    // MARK: - Point E/F/G: a degraded-but-not-failed pull surfaces a
    // visible status, distinct from both "up to date" and a pull failure

    @Test("A pull that skips a row (poison, not yet dropped) records a pullDegradedMessagePrefix status, not silence")
    func degradedPullSurfacesVisibleStatus() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        _ = try seedCard(in: container, profile: profile, alreadySynced: true)

        let pullTransport = MockSyncPullTransport()
        // An undecodable `cards` row — never applies, never a network
        // error, exactly the "stuck table" `PullSummary.skippedRowCounts`
        // exists to make visible. Before this wiring existed
        // (`skippedRowCounts`/`permanentlyDroppedRowCounts` computed and
        // read by nobody), a cycle like this one looked IDENTICAL to a
        // clean one from `SettingsView`'s point of view.
        let badRow: SyncRow = [
            "id": .uuid(UUID()),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(Date(timeIntervalSince1970: 1_701_000_000)),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(Date(timeIntervalSince1970: 1_701_000_000))),
        ]
        pullTransport.enqueueRows([badRow], forTable: "cards")

        let coordinator = makeCoordinator(
            container: container,
            pullTransport: pullTransport,
            consentStore: MockSyncConsentStore(consentGiven: true)
        )

        let outcome = await coordinator.syncNow()
        guard case .success = outcome else {
            Issue.record("Expected success (push still proceeds even though the pull was degraded), got \(outcome)")
            return
        }

        let message = await coordinator.lastErrorMessage()
        #expect(message?.hasPrefix(CloudSyncCoordinator.pullDegradedMessagePrefix) == true)
        // Distinct from an outright pull failure — that prefix must NOT be
        // the one that fired.
        #expect(message?.hasPrefix(CloudSyncCoordinator.pullFailureMessagePrefix) != true)
    }

    // MARK: - IMPORTANT C: a consent revocation that lands mid-pull must
    // still block the push that follows, and must not lose its cursor reset

    @Test("IMPORTANT C: revoking consent WHILE a pull is in flight skips the push, and the deferred cursor reset still lands")
    func consentRevokedMidPullSkipsPushAndStillResetsCursors() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(in: container)
        _ = try seedCard(in: container, profile: profile, alreadySynced: false)

        let gate = PullGate()
        // A real `profiles` row, returned ONCE `fetchRows("profiles", ...)`
        // is released — this is what makes the reset-ordering assertion
        // below meaningful rather than vacuous: the in-flight pull must
        // ACTUALLY WRITE a fresh cursor for `profiles` after consent was
        // revoked, so the test can prove that write gets wiped back out
        // (deferred reset) rather than silently surviving (immediate
        // reset racing an in-flight cycle — see `pendingCursorReset`'s doc
        // comment for exactly this hazard).
        let remoteProfile = UserProfile(displayName: "Remote")
        remoteProfile.updatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        var profileRow = try SyncPayloadBuilder.row(for: remoteProfile)
        profileRow["server_updated_at"] = .string(SyncJSON.iso8601String(remoteProfile.updatedAt))
        let pullTransport = GatedPullTransport(gate: gate, rowsAfterRelease: ["profiles": [profileRow]])
        let dataTransport = MockSyncDataTransport()
        // Pre-seeded (NOT cold start) so the reset below is a meaningful
        // assertion, not a no-op that would pass even without the fix —
        // see `makeSeededCursorStore`'s doc comment for why an unseeded
        // store would instead hit rule 1's early return, before this
        // cycle's OWN per-table cursor writes could even be attempted.
        let cursorStore = CloudSyncCoordinatorTests.makeSeededCursorStore()
        let consentStore = MockSyncConsentStore(consentGiven: true)
        let coordinator = CloudSyncCoordinator(
            modelContainer: container,
            identity: makeIdentityManager().manager,
            transport: dataTransport,
            pullTransport: pullTransport,
            cursorStore: cursorStore,
            skipTracker: MockSyncSkipTracker(),
            consentStore: consentStore,
            minSyncInterval: 0
        )

        let syncTask = Task { await coordinator.syncNow() }

        // Wait until the pull is genuinely INSIDE a `fetchRows` call before
        // revoking — proves this is a mid-pull revocation, not a race that
        // happens to land before the pull even starts.
        await gate.waitUntilFirstCall()
        await coordinator.setConsent(false)
        gate.release()

        let outcome = await syncTask.value

        #expect(outcome == .skippedConsentOff)
        // The whole point: NOTHING left the device after consent was
        // revoked. Before this fix, `syncNow()` only checked consent at
        // entry, so a mid-cycle revocation didn't stop the 7 `pushDirty*`
        // calls that follow the pull — data left the device after the
        // learner had already said no.
        #expect(dataTransport.calls.isEmpty)
        // The deferred reset (`pendingCursorReset`) ran once the cycle
        // finished — every table's pre-seeded cursor is gone.
        for table in SyncPullActor.pullOrder {
            #expect(cursorStore.cursor(forTable: table) == nil)
        }
    }

    // MARK: - Seeding helpers (MainActor: SwiftData's mainContext)

    private func seedProfile(in container: ModelContainer) throws -> UserProfile {
        let context = container.mainContext
        let profile = UserProfile(displayName: "Test Learner")
        context.insert(profile)
        try context.save()
        return profile
    }

    private func markProfileSynced(_ profile: UserProfile, in container: ModelContainer) throws {
        let context = container.mainContext
        profile.syncedAt = profile.updatedAt
        try context.save()
    }

    private func seedCard(in container: ModelContainer, profile: UserProfile, alreadySynced: Bool) throws -> Card {
        let context = container.mainContext
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        if alreadySynced {
            card.syncedAt = card.updatedAt
        }
        context.insert(card)
        try context.save()
        return card
    }

    private func seedReviewLog(for card: Card, in container: ModelContainer, alreadySynced: Bool) throws -> ReviewLog {
        let context = container.mainContext
        let log = ReviewLog(card: card, grade: .good, responseTimeMs: 500)
        if alreadySynced {
            log.syncedAt = log.updatedAt
        }
        context.insert(log)
        try context.save()
        return log
    }

    private func seedCompanionMessage(profileID: UUID, in container: ModelContainer) throws -> CompanionChatMessage {
        let context = container.mainContext
        let message = CompanionChatMessage(role: .user, content: "こんにちは", profileId: profileID)
        context.insert(message)
        try context.save()
        return message
    }

    /// Uses a BRAND-NEW `ModelContext` rather than `container.mainContext` —
    /// `mainContext` already has `Card` registered in its identity map from
    /// seeding, and this project's own migration post-mortems
    /// (`Sources/Models/Schema/IkeruSchema.swift`) are proof this codebase
    /// has been bitten before by assuming cross-context state is trivially
    /// consistent. A fresh context has no cached identity-map entry to go
    /// stale, so this read is unambiguous regardless of SwiftData's
    /// same-context re-fetch/merge behavior (which this task's rules don't
    /// allow verifying empirically via a build).
    private func fetchCard(id: UUID, in container: ModelContainer) throws -> Card? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

// MARK: - PullGate / GatedPullTransport

/// Two one-shot signals a test can `await`, guarding a `SyncPullTransport`
/// that deliberately suspends mid-call — the infrastructure
/// `consentRevokedMidPullSkipsPushAndStillResetsCursors` (IMPORTANT C) needs
/// to land a `setConsent(false)` call WHILE `syncNow()` is genuinely
/// suspended inside a real pull, not merely before or after it. `@unchecked
/// Sendable`: guarded entirely by `NSLock`, same justification as
/// `MockSyncPullTransport`/`MockSyncDataTransport` elsewhere in this module.
private final class PullGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasBeenCalled = false
    private var calledContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Resumes once `GatedPullTransport.fetchRows` has been entered at
    /// least once. Called by the test, from OUTSIDE the suspended
    /// `syncNow()` task.
    func waitUntilFirstCall() async {
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

    /// Called by `GatedPullTransport.fetchRows` itself, the instant it's
    /// entered — signals `waitUntilFirstCall()` and then blocks the CALLER
    /// (the suspended `syncNow()` task) until `release()`.
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

    /// Releases every past and future call blocked in
    /// `signalCalledThenWaitForRelease()` — called by the test once it has
    /// done whatever it needed to do while the pull was suspended.
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

/// A `SyncPullTransport` whose every `fetchRows` call blocks on `gate` until
/// released. After release, returns `rowsAfterRelease[table]` exactly ONCE
/// per table (empty thereafter, and for any table not in that dictionary) —
/// letting the test prove the in-flight pull actually WRITES a cursor after
/// consent was revoked, not merely that it returned nothing. Used ONLY by
/// IMPORTANT C's test — every other test in this file uses
/// `MockSyncPullTransport`, which never blocks.
private final class GatedPullTransport: SyncPullTransport, @unchecked Sendable {
    let gate: PullGate
    private let rowsAfterRelease: [String: [SyncRow]]
    private let lock = NSLock()
    private var consumedTables: Set<String> = []

    init(gate: PullGate, rowsAfterRelease: [String: [SyncRow]] = [:]) {
        self.gate = gate
        self.rowsAfterRelease = rowsAfterRelease
    }

    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        await gate.signalCalledThenWaitForRelease()
        let alreadyConsumed: Bool = lock.withLock {
            if consumedTables.contains(table) { return true }
            consumedTables.insert(table)
            return false
        }
        return alreadyConsumed ? [] : (rowsAfterRelease[table] ?? [])
    }
}
