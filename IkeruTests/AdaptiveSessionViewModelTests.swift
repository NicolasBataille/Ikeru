import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("SessionViewModel — Adaptive Sessions")
@MainActor
struct AdaptiveSessionViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Drop any active-profile id left in UserDefaults by an earlier test;
        // the resolver persists it there, and it crosses test boundaries.
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeViewModel(container: ModelContainer) -> SessionViewModel {
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        return SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container
        )
    }

    /// Resolves (creating if needed) the active profile, and marks it active.
    ///
    /// Cards MUST be attached to it: `CardRepository` scopes every query to
    /// `profile.cards` (see `CardModelActor.activeProfileCards`), so a card
    /// inserted with `profile == nil` is invisible to the planner and the
    /// session composes to nothing. These suites predate per-profile scoping
    /// and were never updated, because a crashing runner meant they never ran
    /// — every "session never starts" failure here traced back to this.
    @discardableResult
    private func ensureProfile(container: ModelContainer) throws -> UserProfile {
        let context = container.mainContext
        if let existing = ActiveProfileResolver.fetchActiveProfile(in: context) {
            return existing
        }
        let profile = UserProfile(displayName: "Test")
        context.insert(profile)
        try context.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return profile
    }

    private func seedDueCards(container: ModelContainer, count: Int) throws -> [UUID] {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        var ids: [UUID] = []
        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                // `reps: 1` is what makes these REVIEWS. The planner's
                // `pickReviews` filters on `dueDate <= now && reps > 0`; a
                // never-reviewed card is NEW content, which is deliberately
                // dripped roughly one per session. Seeded with the default
                // `reps == 0`, this helper produced new cards while its name
                // and every assertion said "due reviews", so a 3-card seed
                // composed a 1-item session. The product was right; the
                // fixture was lying.
                fsrsState: FSRSState(difficulty: 5.0, stability: 5.0, reps: 1, lapses: 0,
                                     lastReview: Date().addingTimeInterval(-86_400)),
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    private func seedMixedCards(container: ModelContainer) throws {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        let types: [CardType] = [.kanji, .vocabulary, .grammar, .listening]
        for i in 0..<20 {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: types[i % types.count],
                fsrsState: FSRSState(reps: 1),
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    // MARK: - Session Preview Tests

    @Test("loadSessionPreview populates session preview")
    func loadSessionPreviewPopulates() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.loadSessionPreview()

        #expect(vm.sessionPreview.cardCount > 0)
        #expect(vm.sessionPreview.estimatedMinutes >= 0)
        #expect(vm.estimatedCardCount > 0)
    }

    @Test("loadSessionPreview with no cards produces empty preview")
    func loadSessionPreviewEmpty() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.loadSessionPreview()

        // KNOWN PRODUCT ISSUE (GAP-10, surfaced 2026-08-16): an EMPTY store
        // previews a 25-item session — 22 of them reading — instead of an
        // empty one. Nothing is due, nothing has been studied, and the app
        // still proposes twenty minutes of work.
        //
        // The question this raises is a product decision, not a test bug:
        // what do we show a learner with nothing to review? The same
        // question is open on the UI side (`SessionAnswerFlowUITests`, left
        // red on purpose in PR #106). Both are recorded rather than papered
        // over: the assertion below states what the app SHOULD do, and this
        // will start failing as "known issue not recorded" the moment the
        // planner learns to return an empty plan for an empty store.
        withKnownIssue("planner composes a 25-item session from an empty store") {
            #expect(vm.sessionPreview.cardCount == 0)
            #expect(vm.sessionPreview == SessionPreview.empty)
        }
    }

    @Test("loadSessionPreview with custom config")
    func loadSessionPreviewCustomConfig() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 15)
        let vm = makeViewModel(container: container)

        let config = SessionConfig(availableTimeMinutes: 3) // Micro
        await vm.loadSessionPreview(config: config)

        // Micro session should cap at 10 cards
        #expect(vm.sessionPreview.cardCount <= 10)
    }

    // MARK: - Adaptive Session Start Tests

    @Test("startAdaptiveSession sets active with SRS cards")
    func startAdaptiveSessionSetsActive() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        let config = SessionConfig(availableTimeMinutes: 20)
        await vm.startAdaptiveSession(config: config)

        #expect(vm.isActive == true)
        #expect(!vm.sessionQueue.isEmpty)
        #expect(vm.currentIndex == 0)
        #expect(vm.reviewedCount == 0)
    }

    @Test("startAdaptiveSession falls back to basic when no content")
    func startAdaptiveSessionFallback() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        let config = SessionConfig(availableTimeMinutes: 20)
        await vm.startAdaptiveSession(config: config)

        // Should still be active (falls back to basic)
        #expect(vm.isActive == true)
        // Same known product issue as `loadSessionPreviewEmpty` above, seen
        // from the session side: with no cards at all the planner still fills
        // a session, so it does not start out complete.
        withKnownIssue("planner composes a non-empty session from an empty store") {
            #expect(vm.isSessionComplete == true) // No cards
        }
    }

    @Test("startSession backward compatibility preserved")
    func startSessionBackwardCompatibility() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        // Original method should still work
        await vm.startSession()

        #expect(vm.isActive == true)
        #expect(vm.sessionQueue.count == 3)
    }
}
