import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("SessionViewModel")
@MainActor
struct SessionViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Clear cross-test active-profile leakage from UserDefaults.
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Constructs a `SessionViewModel` whose composition is driven by a
    /// `MockSessionPlanner`. The mock's plan defaults to `.empty`; tests
    /// that need a deterministic queue should call `plannerWithSeededCards(...)`
    /// to populate it before invoking `startSession`.
    private func makeViewModel(
        container: ModelContainer,
        sessionPlanner: any SessionPlanner = MockSessionPlanner()
    ) -> SessionViewModel {
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        return SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: sessionPlanner
        )
    }

    /// Builds a `MockSessionPlanner` that returns a plan composed of exactly
    /// the SRS reviews for the cards already seeded in `container`. Tests use
    /// this so the queue shape is independent of `DefaultSessionPlanner`'s
    /// 40/30/20/10 budget composition (which adds variety / new-content
    /// tiles whose count tests don't control).
    private func plannerWithSeededCards(
        container: ModelContainer
    ) async -> MockSessionPlanner {
        let repo = CardRepository(modelContainer: container)
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

    /// Returns the active profile, creating one (and persisting its id)
    /// when missing. Cards must be attached to a profile because
    /// `CardRepository` queries are scoped to `profile.cards`.
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

    /// Marks the active profile's RPGState as "already had a session today"
    /// so `SessionBonusService.evaluate` returns `bonusXP == 0` when the test
    /// session reaches `finalizeSession`. Use in tests that grade every card
    /// (so the session completes) and assert on raw per-card XP values.
    /// Without this, the first-session-of-day bonus (+30 XP) inflates
    /// `xpEarned`/`totalXP` and breaks fine-grained XP assertions.
    private func suppressFirstSessionBonus(container: ModelContainer) throws {
        let context = container.mainContext
        _ = try ensureProfile(container: container)
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            return
        }
        state.lastSessionDate = Date()
        try context.save()
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
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    // MARK: - Start Session Tests

    @Test("startSession composes queue and sets active")
    func startSessionSetsActive() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()

        #expect(vm.isActive == true)
        #expect(vm.sessionQueue.count == 3)
        #expect(vm.currentIndex == 0)
        #expect(vm.currentCard != nil)
        #expect(vm.reviewedCount == 0)
        #expect(vm.xpEarned == 0)
    }

    @Test("startSession with no cards results in empty queue")
    func startSessionEmptyQueue() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.isActive == true)
        #expect(vm.sessionQueue.isEmpty)
        #expect(vm.isSessionComplete == true)
        #expect(vm.currentCard == nil)
    }

    // MARK: - Grading Tests

    @Test("gradeAndAdvance advances to next card")
    func gradeAndAdvanceAdvances() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        let firstCardId = vm.currentCard?.id

        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.currentIndex == 1)
        #expect(vm.currentCard?.id != firstCardId)
        #expect(vm.reviewedCount == 1)
    }

    @Test("gradeAndAdvance earns flat XP for good grade")
    func gradeGoodEarnsFlatXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.xpEarned == RPGConstants.xpForGrade(.good))
    }

    @Test("gradeAndAdvance earns flat XP for easy grade")
    func gradeEasyEarnsFlatXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .easy)

        #expect(vm.xpEarned == RPGConstants.xpForGrade(.easy))
    }

    @Test("gradeAndAdvance earns flat XP for hard grade")
    func gradeHardEarnsFlatXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .hard)

        #expect(vm.xpEarned == RPGConstants.xpForGrade(.hard))
    }

    @Test("gradeAndAdvance earns reduced XP for again grade")
    func gradeAgainEarnsReducedXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .again)

        #expect(vm.xpEarned == RPGConstants.xpForGrade(.again))
    }

    @Test("Session completes when all cards graded")
    func sessionCompletesWhenAllGraded() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.isSessionComplete == true)
        #expect(vm.currentCard == nil)
        #expect(vm.reviewedCount == 2)
        #expect(vm.xpEarned == 2 * RPGConstants.xpForGrade(.good))
    }

    @Test("Session progress tracks correctly")
    func sessionProgressTracks() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        #expect(vm.sessionProgress == 0.0)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.sessionProgress == 0.25)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.sessionProgress == 0.5)
    }

    // MARK: - Pause/Resume Tests

    @Test("pauseSession sets isPaused")
    func pauseSessionSetsFlag() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        vm.pauseSession()

        #expect(vm.isPaused == true)
    }

    @Test("resumeSession clears isPaused")
    func resumeSessionClearsFlag() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        vm.pauseSession()
        vm.resumeSession()

        #expect(vm.isPaused == false)
    }

    @Test("Pause/resume preserves session state")
    func pauseResumePreservesState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good) // Review first card

        let indexBeforePause = vm.currentIndex
        let reviewedBeforePause = vm.reviewedCount
        let xpBeforePause = vm.xpEarned

        vm.pauseSession()
        vm.resumeSession()

        #expect(vm.currentIndex == indexBeforePause)
        #expect(vm.reviewedCount == reviewedBeforePause)
        #expect(vm.xpEarned == xpBeforePause)
        #expect(vm.isActive == true)
    }

    // MARK: - End Session Tests

    @Test("endSession marks session complete with partial progress")
    func endSessionWithPartialProgress() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        vm.endSession()

        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 2) // Only 2 were actually reviewed
        #expect(vm.xpEarned == 2 * RPGConstants.xpForGrade(.good))
    }

    // MARK: - Dismiss Tests

    @Test("dismissSession resets all state")
    func dismissSessionResetsState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        vm.dismissSession()

        #expect(vm.isActive == false)
        #expect(vm.isPaused == false)
        #expect(vm.sessionQueue.isEmpty)
        #expect(vm.currentIndex == 0)
    }

    // MARK: - Next Card Tests

    @Test("nextCard provides peek at upcoming card")
    func nextCardPeek() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()

        #expect(vm.currentCard != nil)
        #expect(vm.nextCard != nil)
        #expect(vm.currentCard?.id != vm.nextCard?.id)
    }

    @Test("nextCard is nil on last card")
    func nextCardNilOnLastCard() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        // Now on the last card
        #expect(vm.currentCard != nil)
        #expect(vm.nextCard == nil)
    }

    // MARK: - RPG Integration Tests

    @Test("gradeAndAdvance updates totalXP")
    func gradeAndAdvanceUpdatesTotalXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        #expect(vm.totalXP == 0)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.totalXP == RPGConstants.xpForGrade(.good))
    }

    @Test("gradeAndAdvance persists RPG state to SwiftData")
    func gradeAndAdvancePersistsRPGState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        // Verify persisted state
        let descriptor = FetchDescriptor<RPGState>()
        let states = try container.mainContext.fetch(descriptor)
        #expect(states.count == 1)
        #expect(states.first?.xp == RPGConstants.xpForGrade(.good))
    }

    @Test("startSession creates RPGState if none exists")
    func startSessionCreatesRPGState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()

        let descriptor = FetchDescriptor<RPGState>()
        let states = try container.mainContext.fetch(descriptor)
        #expect(states.count == 1)
        #expect(vm.currentLevel == 1)
        #expect(vm.totalXP == 0)
    }

    @Test("XP accumulates across multiple grades in session")
    func xpAccumulatesAcrossGrades() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        try suppressFirstSessionBonus(container: container)
        let planner = await plannerWithSeededCards(container: container)
        let vm = makeViewModel(container: container, sessionPlanner: planner)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .hard)
        await vm.gradeAndAdvance(grade: .again)

        let expected = RPGConstants.xpForGrade(.good)
            + RPGConstants.xpForGrade(.hard)
            + RPGConstants.xpForGrade(.again)
        #expect(vm.xpEarned == expected)
        #expect(vm.totalXP == expected)
    }

}

// MARK: - Test Doubles

/// Test-only `SessionPlanner` that returns a fixed `SessionPlan` regardless
/// of inputs. Lets tests assert against a deterministic queue shape without
/// being coupled to `DefaultSessionPlanner`'s 40/30/20/10 budget composition
/// (which adds variety / new-content tiles whose count is not under the
/// individual test's control).
final class MockSessionPlanner: SessionPlanner, @unchecked Sendable {

    /// Plan returned by `compose(...)`. Defaults to `.empty`; configure
    /// before `startSession()` to drive a specific scenario.
    var plan: SessionPlan = .empty

    func compose(inputs: SessionPlannerInputs) async -> SessionPlan {
        plan
    }
}
