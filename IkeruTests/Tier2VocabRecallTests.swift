import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Phase 4.1 Tier-2 (part 2) coverage for the LIVE vocabulary-recall completion
/// path.
///
/// `.vocabularyStudy` is now un-filtered by `DefaultSessionPlanner.finalize`, so
/// it can reach `SessionViewModel` inside a real session. It is XP-only — there
/// is NO backing FSRS card (vocabulary lives only in the read-only content DB) —
/// so completing one must award XP and advance the exercise pointer WITHOUT
/// moving the SRS queue pointer (`currentIndex`) or writing any `ReviewLog`. The
/// mocked-planner injection mirrors `Tier2AudioDrillCompletionTests`.
@Suite("Tier-2 vocab-recall completion (4.1)")
@MainActor
struct Tier2VocabRecallTests {

    // MARK: - Helpers (mirror Tier2AudioDrillCompletionTests' seam)

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
            exerciseBreakdown: [.reading: exercises.count]
        )
    }

    private func dto(_ front: String, in dtos: [CardDTO]) throws -> CardDTO {
        try #require(dtos.first { $0.front == front })
    }

    // MARK: - Tests

    @Test("vocabularyStudy completion is XP-only: advances the exercise, not the SRS queue, writes no FSRS grade")
    func vocabularyStudyIsXPOnly() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let leading = ExerciseItem.vocabularyStudy(UUID())

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([leading, .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)          // only A is a .srsReview
        #expect(vm.currentExercise == leading)
        #expect(vm.currentCard?.id == a.id)

        await vm.completeCurrentExercise(grade: .good)

        // XP was awarded for the completion (perGrade base × N5 multiplier).
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

    @Test("An incorrect vocab recall (.again) is still XP-only and still advances the session")
    func vocabularyStudyIncorrectStillXPOnly() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let leading = ExerciseItem.vocabularyStudy(UUID())

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([leading, .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        // An incorrect answer maps to `.again` (DrillGradeMapping.vocabularyRecall).
        await vm.completeCurrentExercise(grade: .again)

        // `.again` still awards XP (perGrade → xpForGrade(.again) > 0) and still
        // advances the exercise pointer without touching the SRS queue or FSRS.
        #expect(vm.xpEarned > 0)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentIndex == 0)
        #expect(vm.reviewedCount == 1)
        let aLogs = await repo.reviewLogs(for: a.id)
        #expect(aLogs.isEmpty)
    }

    @Test("A trailing vocab recall after the last SRS card is presented, not dropped")
    func trailingVocabRecallNotDropped() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let vocabID = UUID()

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.srsReview(a), .vocabularyStudy(vocabID)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)

        // Grade the only SRS card. The trailing vocab recall must remain.
        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .vocabularyStudy(vocabID))

        // Completing the trailing drill ends the session cleanly.
        await vm.completeCurrentExercise(grade: .good)
        #expect(vm.isSessionComplete == true)
        #expect(vm.currentExerciseIndex == 2)
        #expect(vm.reviewedCount == 2)
    }
}
