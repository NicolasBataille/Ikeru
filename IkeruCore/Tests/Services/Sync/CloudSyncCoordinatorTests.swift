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

    private func makeCoordinator(
        container: ModelContainer,
        identity: AnonymousIdentityManager? = nil,
        dataTransport: MockSyncDataTransport = MockSyncDataTransport(),
        consentStore: MockSyncConsentStore = MockSyncConsentStore(),
        minSyncInterval: TimeInterval = 60
    ) -> CloudSyncCoordinator {
        CloudSyncCoordinator(
            modelContainer: container,
            identity: identity ?? makeIdentityManager().manager,
            transport: dataTransport,
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
