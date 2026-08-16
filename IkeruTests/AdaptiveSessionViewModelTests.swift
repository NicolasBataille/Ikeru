import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("SessionViewModel — Caught-up sessions")
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

    // MARK: - Caught-up sessions (nothing due)

    /// Seeds cards that are STARTED but not yet due — the "approfondir" pool.
    /// `daysUntilDue` varies so the retrievability ordering has something to
    /// sort on.
    @discardableResult
    private func seedNotYetDueCards(container: ModelContainer, count: Int) throws -> [UUID] {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        var ids: [UUID] = []
        for i in 0..<count {
            let card = Card(
                front: "Known \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double(i + 2),
                    reps: 3,
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86_400)
                ),
                dueDate: Date().addingTimeInterval(Double(i + 1) * 86_400)
            )
            card.profile = profile
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    /// Seeds never-reviewed cards — the "découvrir" pool.
    ///
    /// Kana fronts by default: `NewCardPresentationScheduler` only inserts its
    /// ungraded presentation phase for `card.isKana` (pre-existing scope, task
    /// #21) — and `isKana` is decided by the FRONT being in the kana catalog,
    /// not by `CardType`, which has no `.kana` case at all. A first version of
    /// this helper seeded "New 0"-style fronts and the presentation assertion
    /// failed. Correctly: the test was wrong, not the code. See
    /// `discoverAnnouncesNewKanaButNotOtherTypes`, which records the
    /// limitation instead of hiding it behind a kana-only fixture.
    private func seedUnseenCards(
        container: ModelContainer,
        count: Int,
        kanaFronts: Bool = true
    ) throws {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        let kana = Array("あいうえおかきくけこ")
        for i in 0..<count {
            let card = Card(
                front: kanaFronts ? String(kana[i % kana.count]) : "New word \(i)",
                back: "Back \(i)",
                type: .vocabulary,
                fsrsState: FSRSState(),
                dueDate: Date()
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    /// The behaviour this whole feature exists for: nothing due must not mean
    /// nothing offered. Replaces `loadSessionPreviewEmpty` and
    /// `startAdaptiveSessionFallback`, whose `withKnownIssue` wrappers pinned
    /// the 25-item filler of a pipeline no user could reach (deleted
    /// 2026-08-16 — see `PlannerService`'s header for what it did).
    @Test("Deepen composes from started-but-not-yet-due cards")
    func deepenComposesFromKnownCards() async throws {
        let container = try makeContainer()
        try seedNotYetDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        let started = await vm.startCaughtUpSession(offer: .deepen)

        #expect(started == true)
        #expect(vm.isActive == true)
        #expect(vm.sessionQueue.isEmpty == false)
        #expect(
            vm.sessionQueue.allSatisfy { $0.fsrsState.reps > 0 },
            "deepen must never introduce new content — that is what discover is for"
        )
    }

    @Test("Discover composes from never-seen cards")
    func discoverComposesFromUnseenCards() async throws {
        let container = try makeContainer()
        try seedUnseenCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

        let started = await vm.startCaughtUpSession(offer: .discover)

        #expect(started == true)
        #expect(vm.sessionQueue.allSatisfy { $0.fsrsState.reps == 0 })
        #expect(
            vm.cardsNeedingPresentation.isEmpty == false,
            "new content must be ANNOUNCED as new — that is the presentation phase"
        )
    }

    /// The honest limit of "announced as new", recorded rather than papered
    /// over.
    ///
    /// The owner's decision was that discovery must present new content AS
    /// new. `NewCardPresentationScheduler` does exactly that — but only for
    /// kana (`card.isKana`), a scope that predates this feature. So a
    /// discovery session that surfaces a vocabulary or kanji card introduces
    /// it with no presentation phase, exactly as the normal new-content drip
    /// already does.
    ///
    /// This is asserted, not fixed here: widening the presentation phase to
    /// every card type would change the ORDINARY session too, which is a
    /// separate decision with its own pacing consequences. This test is what
    /// makes the gap visible instead of letting it hide behind a kana-only
    /// fixture.
    @Test("Discovery of non-kana content gets no presentation phase — known limit")
    func discoverAnnouncesNewKanaButNotOtherTypes() async throws {
        let container = try makeContainer()
        try seedUnseenCards(container: container, count: 4, kanaFronts: false)
        let vm = makeViewModel(container: container)

        let started = await vm.startCaughtUpSession(offer: .discover)

        #expect(started == true)
        #expect(
            vm.cardsNeedingPresentation.isEmpty,
            """
            if this starts failing, the presentation phase was widened beyond \
            kana — good news, but update this test and the doc above
            """
        )
    }

    /// The offer must fail honestly rather than open a hollow session. This is
    /// the same guard `startSession()` has, and the reason the UI refreshes
    /// instead of presenting when it returns false.
    @Test("An offer with an empty pool does not start a session")
    func emptyPoolDoesNotStart() async throws {
        let container = try makeContainer()
        try ensureProfile(container: container)
        let vm = makeViewModel(container: container)

        let deepen = await vm.startCaughtUpSession(offer: .deepen)
        let discover = await vm.startCaughtUpSession(offer: .discover)

        #expect(deepen == false)
        #expect(discover == false)
        #expect(vm.isActive == false)
    }

    /// Availability drives which buttons Home renders, so it must agree with
    /// what the planner can actually compose — otherwise the proposal shows a
    /// control that does nothing, which is the defect being removed.
    @Test("Availability matches what the planner can compose")
    func availabilityMatchesComposition() async throws {
        let container = try makeContainer()
        try seedNotYetDueCards(container: container, count: 2)
        let repo = CardRepository(modelContainer: container)
        let cards = await repo.allCards()

        let offers = DefaultSessionPlanner.caughtUpAvailability(cards: cards)

        #expect(offers.contains(.deepen))
        #expect(offers.contains(.discover) == false, "no unseen card was seeded")
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
