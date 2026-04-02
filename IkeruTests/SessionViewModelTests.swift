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
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeViewModel(container: ModelContainer) -> SessionViewModel {
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        return SessionViewModel(plannerService: planner, cardRepository: repo)
    }

    private func seedDueCards(container: ModelContainer, count: Int) throws -> [UUID] {
        let context = container.mainContext
        var ids: [UUID] = []
        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600)
            )
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
        let vm = makeViewModel(container: container)

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
        let vm = makeViewModel(container: container)

        await vm.startSession()
        let firstCardId = vm.currentCard?.id

        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.currentIndex == 1)
        #expect(vm.currentCard?.id != firstCardId)
        #expect(vm.reviewedCount == 1)
    }

    @Test("gradeAndAdvance earns 10 XP for good grade")
    func gradeGoodEarns10XP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.xpEarned == 10)
    }

    @Test("gradeAndAdvance earns 10 XP for easy grade")
    func gradeEasyEarns10XP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .easy)

        #expect(vm.xpEarned == 10)
    }

    @Test("gradeAndAdvance earns 5 XP for hard grade")
    func gradeHardEarns5XP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .hard)

        #expect(vm.xpEarned == 5)
    }

    @Test("gradeAndAdvance earns 5 XP for again grade")
    func gradeAgainEarns5XP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .again)

        #expect(vm.xpEarned == 5)
    }

    @Test("Session completes when all cards graded")
    func sessionCompletesWhenAllGraded() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.isSessionComplete == true)
        #expect(vm.currentCard == nil)
        #expect(vm.reviewedCount == 2)
        #expect(vm.xpEarned == 20)
    }

    @Test("Session progress tracks correctly")
    func sessionProgressTracks() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

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
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.pauseSession()

        #expect(vm.isPaused == true)
    }

    @Test("resumeSession clears isPaused")
    func resumeSessionClearsFlag() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.pauseSession()
        vm.resumeSession()

        #expect(vm.isPaused == false)
    }

    @Test("Pause/resume preserves session state")
    func pauseResumePreservesState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

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
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        vm.endSession()

        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 2) // Only 2 were actually reviewed
        #expect(vm.xpEarned == 20)
    }

    // MARK: - Dismiss Tests

    @Test("dismissSession resets all state")
    func dismissSessionResetsState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

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
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.currentCard != nil)
        #expect(vm.nextCard != nil)
        #expect(vm.currentCard?.id != vm.nextCard?.id)
    }

    @Test("nextCard is nil on last card")
    func nextCardNilOnLastCard() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)

        // Now on the last card
        #expect(vm.currentCard != nil)
        #expect(vm.nextCard == nil)
    }

    // MARK: - Estimate Tests

    @Test("loadSessionEstimate sets estimated card count")
    func loadSessionEstimateSetsCount() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

        await vm.loadSessionEstimate()

        #expect(vm.estimatedCardCount == 4)
    }
}
