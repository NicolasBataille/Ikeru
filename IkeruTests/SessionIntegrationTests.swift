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

    // MARK: - Full Flow Tests

    @Test("Full flow: seed content -> compose session -> review cards -> complete -> summary data correct")
    func fullSessionFlow() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

        // Step 1: Seed content
        let allCards = await repo.allCards()
        let seeded = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: allCards.count
        )
        #expect(seeded.count == 5)

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
        #expect(vm.xpEarned == 50) // 5 cards * 10 XP each
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

        // Seed cards
        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

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

    @Test("Empty queue shows All caught up state")
    func emptyQueueAllCaughtUp() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

        // Start session with no cards
        await vm.startSession()

        #expect(vm.isActive == true)
        #expect(vm.isSessionComplete == true)
        #expect(vm.sessionQueue.isEmpty)
        #expect(vm.currentCard == nil)
        #expect(vm.reviewedCount == 0)
        #expect(vm.xpEarned == 0)
    }

    @Test("End session preserves partial progress and review logs")
    func endSessionPartialProgress() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

        let planner = PlannerService(cardRepository: repo)
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

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
        #expect(vm.xpEarned == 15) // 10 (good) + 5 (hard) -- unchanged

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
        let vm = SessionViewModel(plannerService: planner, cardRepository: repo, modelContainer: container)

        await vm.startSession()

        await vm.gradeAndAdvance(grade: .easy)  // 10 XP
        await vm.gradeAndAdvance(grade: .good)   // 10 XP
        await vm.gradeAndAdvance(grade: .hard)   // 5 XP
        await vm.gradeAndAdvance(grade: .again)  // 2 XP

        #expect(vm.xpEarned == 27)
        #expect(vm.reviewedCount == 4)
    }

    @Test("Dismiss session after summary resets state for next session")
    func dismissAndRestartSession() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)

        await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: repo,
            existingCardCount: 0
        )

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
}
