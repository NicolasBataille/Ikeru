import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Phase 4.1 Tier-2 (part 1) coverage for the LIVE audio-drill completion path.
///
/// `.listeningExercise` and `.speakingExercise` are now un-filtered by
/// `DefaultSessionPlanner.finalize`, so they can reach `SessionViewModel` inside
/// a real session. Both are XP-only — there is no backing FSRS card — so
/// completing one must award XP and advance the exercise pointer WITHOUT moving
/// the SRS queue pointer (`currentIndex`) or writing any `ReviewLog`. The
/// mocked-planner injection mirrors `SessionDecouplingTests` / `Tier1DrillTests`.
@Suite("Tier-2 audio-drill completion (4.1)")
@MainActor
struct Tier2AudioDrillCompletionTests {

    // MARK: - Helpers (mirror Tier1DrillTests' seam)

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

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

    /// Seeds one overdue `.kanji` card per front string, attached to the active
    /// profile (used as the trailing SRS card so the session actually starts —
    /// `startSession` refuses an all-non-SRS plan).
    private func seedCards(container: ModelContainer, fronts: [String]) throws {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        for (i, front) in fronts.enumerated() {
            let card = Card(
                front: front,
                back: "Back \(front)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600 + Double(i))
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    private func makeVM(container: ModelContainer, planner: any SessionPlanner) -> SessionViewModel {
        let repo = CardRepository(modelContainer: container)
        let plannerService = PlannerService(cardRepository: repo)
        return SessionViewModel(
            plannerService: plannerService,
            cardRepository: repo,
            modelContainer: container,
            sessionPlanner: planner
        )
    }

    private func buildPlan(_ exercises: [ExerciseItem]) -> SessionPlan {
        SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(1, exercises.count / 3),
            exerciseBreakdown: [.listening: exercises.count]
        )
    }

    private func dto(_ front: String, in dtos: [CardDTO]) throws -> CardDTO {
        try #require(dtos.first { $0.front == front })
    }

    /// Shared assertion body: a leading XP-only audio drill followed by one SRS
    /// review card. Completing the drill must award XP and advance the exercise
    /// pointer without touching the SRS queue pointer or writing a ReviewLog.
    private func assertXPOnlyDrill(
        leading: ExerciseItem,
        expectedNext a: CardDTO,
        vm: SessionViewModel,
        repo: CardRepository
    ) async throws {
        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)          // only A is a .srsReview
        #expect(vm.currentExercise == leading)
        #expect(vm.currentCard?.id == a.id)

        await vm.completeCurrentExercise(grade: .good)

        // XP was awarded for the completion (perCompletion base × N5 multiplier).
        #expect(vm.xpEarned > 0)
        // The exercise pointer advanced to the trailing SRS review…
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .srsReview(a))
        // …but the SRS queue pointer did NOT move — A is still current, ungraded.
        #expect(vm.currentIndex == 0)
        #expect(vm.currentCard?.id == a.id)
        // Session is not prematurely complete; one completion was counted.
        #expect(vm.isSessionComplete == false)
        #expect(vm.reviewedCount == 1)
        // No backing FSRS card → no ReviewLog written anywhere (A is untouched).
        let aLogs = await repo.reviewLogs(for: a.id)
        #expect(aLogs.isEmpty)
    }

    // MARK: - Tests

    @Test("listeningExercise completion is XP-only: advances the exercise, not the SRS queue, writes no FSRS grade")
    func listeningExerciseIsXPOnly() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let leading = ExerciseItem.listeningExercise(UUID())

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([leading, .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        try await assertXPOnlyDrill(leading: leading, expectedNext: a, vm: vm, repo: repo)
    }

    @Test("speakingExercise completion is XP-only: advances the exercise, not the SRS queue, writes no FSRS grade")
    func speakingExerciseIsXPOnly() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let leading = ExerciseItem.speakingExercise(UUID())

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([leading, .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        try await assertXPOnlyDrill(leading: leading, expectedNext: a, vm: vm, repo: repo)
    }

    @Test("A trailing audio drill after the last SRS card is presented, not dropped")
    func trailingAudioDrillNotDropped() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let listeningID = UUID()

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.srsReview(a), .listeningExercise(listeningID)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)

        // Grade the only SRS card. The trailing listening drill must remain.
        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .listeningExercise(listeningID))

        // Completing the trailing drill ends the session cleanly.
        await vm.completeCurrentExercise(grade: .good)
        #expect(vm.isSessionComplete == true)
        #expect(vm.currentExerciseIndex == 2)
        #expect(vm.reviewedCount == 2)
    }
}
