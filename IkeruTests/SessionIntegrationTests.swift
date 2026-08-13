import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("Session Integration")
@MainActor
struct SessionIntegrationTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Reset cross-test active-profile leakage from UserDefaults.
        ActiveProfileResolver.setActiveProfileID(nil)
        let container = try ModelContainer(for: schema, configurations: [config])
        // Seed an active profile so the repository's per-profile queries
        // (and ContentSeedService) see this test's inserted cards.
        let profile = UserProfile(displayName: "Test")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return container
    }

    /// Returns the active profile of `container` (always non-nil because
    /// `makeContainer` seeds one).
    private func activeProfile(_ container: ModelContainer) -> UserProfile? {
        ActiveProfileResolver.fetchActiveProfile(in: container.mainContext)
    }

    /// Builds a `MockSessionPlanner` that returns a plan composed of exactly
    /// the SRS reviews for the cards already present in `container`. Tests
    /// use this so the queue shape is independent of `DefaultSessionPlanner`'s
    /// 40/30/20/10 budget composition (which adds variety / new-content
    /// tiles whose count integration tests don't control).
    private func plannerWithSeededCards(
        repo: CardRepository
    ) async -> MockSessionPlanner {
        let cards = await repo.allCards()
        let exercises = cards.map { ExerciseItem.srsReview($0) }
        let planner = MockSessionPlanner()
        planner.plan = SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(1, exercises.count / 3),
            exerciseBreakdown: [.reading: exercises.count]
        )
        return planner
    }

    /// Marks the active profile's RPGState as "already had a session today"
    /// so `SessionBonusService.evaluate` returns `bonusXP == 0` when the
    /// session reaches `finalizeSession`. Use in tests that grade every
    /// card and assert on raw per-card XP totals.
    private func suppressFirstSessionBonus(container: ModelContainer) throws {
        let context = container.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            return
        }
        state.lastSessionDate = Date()
        try context.save()
    }

    /// Inserts `count` overdue cards attached to the active profile.
    /// Due dates are staggered (most overdue first) so ordering
    /// assertions are deterministic.
    private func seedDueCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        let profile = activeProfile(container)
        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600 + Double(i))
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    /// Inserts `count` overdue `.vocabulary` cards (non-kana fronts,
    /// `Word N`/`Meaning N`) attached to the active profile. Used in place of
    /// `seedDueCards` where a test's XP assertion depends on the
    /// `.vocabularyStudy` rule (no bonus, matching `ExerciseXP.rule`) rather
    /// than `.kanjiStudy`'s +2 bonus — `seedDueCards` is `.kanji`-typed.
    /// Non-kana fronts are deliberate too: real kana fronts would trip
    /// `NewCardPresentationScheduler` (chantier #21) and duplicate each card
    /// into an intro + delayed-test pair, which these generic-flow tests
    /// don't expect. See `fullSessionFlow`'s comment for the full rationale.
    private func seedDueVocabularyCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        let profile = activeProfile(container)
        for i in 0..<count {
            let card = Card(
                front: "Word \(i)",
                back: "Meaning \(i)",
                type: .vocabulary,
                dueDate: Date().addingTimeInterval(-3600 + Double(i))
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    // MARK: - Full Flow Tests

    @Test("Full flow: seed content -> compose session -> review cards -> complete -> summary data correct")
    func fullSessionFlow() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        // Step 1: Seed content. Deliberately generic `.vocabulary` due cards
        // (`seedDueVocabularyCards`), NOT
        // `ContentSeedService.seedBeginnerKanaIfNeeded` — this test exercises
        // the generic session-flow plumbing (and asserts a FLAT
        // `.vocabularyStudy`-rule XP total below, which real kana cards also
        // resolve to), and real kana fronts would now ALSO trigger the
        // new-card presentation pass (chantier #21), doubling the queue and
        // breaking the "review N cards in N grades" loop below. See
        // `NewCardPresentationScheduler` in `SessionComposer.swift`.
        try seedDueVocabularyCards(container: container, count: 5)
        let seeded = await repo.allCards()
        #expect(seeded.count == 5)

        // Inject a planner that returns exactly the seeded cards, so the
        // queue size is deterministic and not coupled to the 40/30/20/10
        // budget composition in `DefaultSessionPlanner`.
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        try suppressFirstSessionBonus(container: container)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        // Step 2: Compose and start session
        await vm.startSession()
        #expect(vm.sessionQueue.count == 5)
        #expect(vm.isActive == true)

        // Step 3: Review all cards
        for _ in 0..<5 {
            #expect(vm.currentCard != nil)
            await vm.gradeAndAdvance(grade: .good)
        }

        // Step 4: Verify session completion
        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 5)
        #expect(vm.xpEarned == 5 * RPGConstants.xpForGrade(.good))
        #expect(vm.newItemsLearned == 5) // All were new (reps == 0)
        #expect(vm.currentCard == nil)

        // Step 5: Verify cards were persisted with updated state
        for card in seeded {
            let logs = await repo.reviewLogs(for: card.id)
            #expect(logs.count == 1)
            #expect(logs.first?.grade == .good)
        }
    }

    @Test("Pause/resume preserves session state during flow")
    func pauseResumePreservesState() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        // Seed cards. Generic `.kanji` due cards, not real kana — see
        // `fullSessionFlow`'s comment on why (chantier #21 new-card
        // presentation pass).
        try seedDueCards(container: container, count: 5)

        let planner = PlannerService(cardRepository: repo)
        // Inject a planner that returns exactly the seeded cards as SRS
        // reviews. With the real `DefaultSessionPlanner`'s 40/30/20/10
        // budget composition, the interleaved review segment for 5
        // brand-new cards can be much shorter than 5 — this test needs a
        // queue deep enough to grade three cards across the pause/resume
        // boundary, independent of that budget shape.
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()

        // Review 2 cards
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .easy)

        let indexBeforePause = vm.currentIndex
        let reviewedBeforePause = vm.reviewedCount
        let xpBeforePause = vm.xpEarned

        // Pause
        vm.pauseSession()
        #expect(vm.isPaused == true)
        #expect(vm.isActive == true)

        // Resume
        vm.resumeSession()
        #expect(vm.isPaused == false)

        // State should be preserved
        #expect(vm.currentIndex == indexBeforePause)
        #expect(vm.reviewedCount == reviewedBeforePause)
        #expect(vm.xpEarned == xpBeforePause)

        // Continue reviewing
        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.reviewedCount == reviewedBeforePause + 1)
    }

    @Test("Empty queue never activates the session")
    func emptyQueueAllCaughtUp() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

        // Start session with no cards. `startSession` guards against an
        // empty composed plan so no timer / Live Activity spins up for a
        // hollow session — it returns early with `isActive` left `false`
        // rather than entering an active-but-already-complete state.
        await vm.startSession()

        #expect(vm.isActive == false)
        #expect(vm.isSessionComplete == false)
        #expect(vm.sessionQueue.isEmpty)
        #expect(vm.currentCard == nil)
        #expect(vm.reviewedCount == 0)
        #expect(vm.xpEarned == 0)
    }

    @Test("End session preserves partial progress and review logs")
    func endSessionPartialProgress() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        // Generic `.vocabulary` due cards (FLAT `.vocabularyStudy`-rule XP,
        // matching the assertion below) and non-kana fronts — see
        // `fullSessionFlow`'s comment on why (chantier #21 new-card
        // presentation pass).
        try seedDueVocabularyCards(container: container, count: 5)

        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()

        // Review only 2 of 5 cards
        let firstCardId = vm.currentCard?.id
        await vm.gradeAndAdvance(grade: .good)
        let secondCardId = vm.currentCard?.id
        await vm.gradeAndAdvance(grade: .hard)

        // End session early
        vm.endSession()

        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 2)
        #expect(vm.xpEarned == RPGConstants.xpForGrade(.good) + RPGConstants.xpForGrade(.hard))

        // Verify review logs exist for reviewed cards
        if let id1 = firstCardId {
            let logs1 = await repo.reviewLogs(for: id1)
            #expect(logs1.count == 1)
        }
        if let id2 = secondCardId {
            let logs2 = await repo.reviewLogs(for: id2)
            #expect(logs2.count == 1)
        }
    }

    @Test("XP calculation correct for mixed grades")
    func xpCalculationMixedGrades() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create 4 due cards attached to the active profile.
        let profile = activeProfile(container)
        for i in 0..<4 {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        try suppressFirstSessionBonus(container: container)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()

        await vm.gradeAndAdvance(grade: .easy)
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .hard)
        await vm.gradeAndAdvance(grade: .again)

        // Cards are `.kanji`-typed, which route to `.kanjiStudy` in
        // `ExerciseXP.rule(for:grade:)` (+2 bonus over the flat
        // `RPGConstants.xpForGrade`), at the `.n5` multiplier (1.0x) a
        // brand-new profile resolves to.
        let expected = ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .easy)
            + ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .good)
            + ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .hard)
            + ExerciseXP.award(type: .kanjiStudy, level: .n5, grade: .again)
        #expect(vm.xpEarned == expected)
        #expect(vm.reviewedCount == 4)
    }

    @Test("Dismiss session after summary resets state for next session")
    func dismissAndRestartSession() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        // Generic `.kanji` due card, not real kana — see `fullSessionFlow`'s
        // comment on why (chantier #21 new-card presentation pass).
        try seedDueCards(container: container, count: 1)

        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

        // First session
        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        vm.endSession()
        vm.dismissSession()

        #expect(vm.isActive == false)
        #expect(vm.sessionQueue.isEmpty)
        #expect(vm.currentIndex == 0)
    }

    // MARK: - Planner Input Ordering

    @Test("startSession passes the full card pool to the planner, overdue and not-yet-due alike")
    func plannerReceivesDueSortedCards() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = activeProfile(container)

        // Deliberately shuffled due dates: tomorrow, 2h overdue, 1h overdue.
        let offsets: [TimeInterval] = [86_400, -7_200, -3_600]
        for (i, offset) in offsets.enumerated() {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(offset)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let recorder = RecordingSessionPlanner()
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: recorder
        )

        await vm.startSession()

        // `SessionViewModel` no longer pre-sorts the pool before invoking the
        // planner — that was a redundant "double sort" dropped when the
        // review-wave sort moved (and stayed) inside
        // `DefaultSessionPlanner.pickReviews`, which is due-sort-order-agnostic
        // on its input (see `DefaultSessionPlannerTests`'s "Review wave drills
        // most-overdue cards first, whatever the input order"). What
        // `SessionViewModel` must still guarantee is that the *entire* pool —
        // overdue, not-yet-due, all of it — reaches the planner unfiltered, so
        // segments like new-content/booster/variety (which draw from
        // not-yet-due or unseen cards) have the full set to choose from.
        #expect(recorder.capturedCards.count == 3)
        let capturedFronts = Set(recorder.capturedCards.map(\.front))
        #expect(capturedFronts == Set(["Card 0", "Card 1", "Card 2"]))
    }

    // MARK: - Mistake Tracking & Same-Day Re-Queue

    @Test("Hard grade is not a mistake; only again feeds missedCardIDs")
    func hardGradeIsNotAMistake() async throws {
        let container = try makeContainer()
        try seedDueCards(container: container, count: 4)

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()
        #expect(vm.sessionQueue.count == 4)

        // Slow-but-correct: no mistake tracked, no re-queue.
        await vm.gradeAndAdvance(grade: .hard)
        #expect(vm.missedCardIDs.isEmpty)
        #expect(vm.sessionQueue.count == 4)

        // Failed: tracked as a mistake and re-queued for same-day retry.
        let failedID = vm.currentCard?.id
        await vm.gradeAndAdvance(grade: .again)
        #expect(failedID != nil)
        if let failedID {
            #expect(vm.missedCardIDs == [failedID])
        }
        #expect(vm.sessionQueue.count == 5)
    }

    @Test("Hard grade counts as a recall success, not a miss, toward correctCount")
    func hardGradeCountsTowardRecallSuccess() async throws {
        let container = try makeContainer()
        try seedDueCards(container: container, count: 6)

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()
        #expect(vm.sessionQueue.count == 6)

        // 1 real miss (.again), 1 slow-but-correct (.hard), 4 clean passes.
        await vm.gradeAndAdvance(grade: .again)
        await vm.gradeAndAdvance(grade: .hard)
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .easy)
        await vm.gradeAndAdvance(grade: .easy)

        // Only `.again` is a miss (matches `missedCardIDs`'s semantics), so
        // 5 of the 6 reviews count toward the summary's recall % — not the
        // 4/6 (67%) you'd get if `.hard` were wrongly treated as a failure.
        #expect(vm.correctCount == 5)
        #expect(vm.missedCardIDs.count == 1)
    }

    @Test("Again re-queues the card 3-5 positions later in a normal session")
    func againRequeuesLaterInNormalSession() async throws {
        let container = try makeContainer()
        try seedDueCards(container: container, count: 6)

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()
        #expect(vm.sessionQueue.count == 6)

        let failedID = vm.currentCard?.id
        await vm.gradeAndAdvance(grade: .again)

        #expect(vm.sessionQueue.count == 7)
        // Graded at index 0 → the retry copy lands at index 4, 5, or 6
        // (3-5 positions after the next card, clamped to the queue end).
        let retryIndex = vm.sessionQueue.dropFirst().firstIndex { $0.id == failedID }
        #expect(retryIndex != nil)
        if let retryIndex {
            #expect((4...6).contains(retryIndex))
        }
        // Session must stay open so the retry is actually reachable.
        #expect(vm.isSessionComplete == false)
    }

    @Test("Same-day re-queue is capped at 2 retries per card")
    func requeueCapAndCompletion() async throws {
        let container = try makeContainer()
        try seedDueCards(container: container, count: 1)

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let mockPlanner = await plannerWithSeededCards(repo: repo)
        let vm = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: mockPlanner
        )

        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)

        // First failure — retry 1 queued, session stays open.
        await vm.gradeAndAdvance(grade: .again)
        #expect(vm.sessionQueue.count == 2)
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentCard != nil)

        // Second failure — retry 2 queued.
        await vm.gradeAndAdvance(grade: .again)
        #expect(vm.sessionQueue.count == 3)

        // Third failure — cap reached, no further re-queue; session ends.
        await vm.gradeAndAdvance(grade: .again)
        #expect(vm.sessionQueue.count == 3)
        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 3)
        // The brand-new card counts once despite three passes.
        #expect(vm.newItemsLearned == 1)
    }
}

// MARK: - Test Doubles

/// Test-only `SessionPlanner` that records the inputs it was composed with
/// and returns an empty plan. Used to assert what `SessionViewModel` feeds
/// the planner (e.g. due-sorted card pool) without depending on
/// `DefaultSessionPlanner` composition.
final class RecordingSessionPlanner: SessionPlanner, @unchecked Sendable {

    /// The `availableCards` from the most recent `compose(...)` call.
    var capturedCards: [CardDTO] = []

    func compose(inputs: SessionPlannerInputs) async -> SessionPlan {
        capturedCards = inputs.availableCards
        return .empty
    }
}
