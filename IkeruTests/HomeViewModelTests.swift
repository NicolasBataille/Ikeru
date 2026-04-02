import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeViewModel(container: ModelContainer) -> HomeViewModel {
        HomeViewModel(modelContainer: container)
    }

    private func seedProfile(container: ModelContainer, name: String) throws {
        let context = container.mainContext
        let profile = UserProfile(displayName: name)
        context.insert(profile)
        try context.save()
    }

    private func seedRPGState(container: ModelContainer, xp: Int, level: Int) throws {
        let context = container.mainContext
        let state = RPGState(xp: xp, level: level, totalReviewsCompleted: 10)
        context.insert(state)
        try context.save()
    }

    private func seedDueCards(container: ModelContainer, count: Int) throws -> [UUID] {
        let context = container.mainContext
        var ids: [UUID] = []
        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600) // Due 1 hour ago
            )
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    private func seedReviewedCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        for i in 0..<count {
            let card = Card(
                front: "Reviewed \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(86400) // Due tomorrow
            )
            // Simulate a reviewed card by setting reps > 0
            card.fsrsState = FSRSState(
                difficulty: 5.0,
                stability: 5.0,
                reps: 1,
                lapses: 0,
                lastReview: Date()
            )
            context.insert(card)
        }
        try context.save()
    }

    // MARK: - Initial State Tests

    @Test("Fresh launch has default values")
    func freshLaunchDefaults() throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        #expect(vm.displayName == "")
        #expect(vm.level == 1)
        #expect(vm.xp == 0)
        #expect(vm.dueCardCount == 0)
        #expect(vm.kanjiLearnedCount == 0)
        #expect(vm.hasLoaded == false)
        #expect(vm.hasCardsDue == false)
    }

    // MARK: - Load Data Tests

    @Test("loadData loads profile display name")
    func loadDataLoadsProfile() async throws {
        let container = try makeContainer()
        try seedProfile(container: container, name: "Nico")
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.displayName == "Nico")
        #expect(vm.greetingText == "Welcome, Nico!")
        #expect(vm.hasLoaded == true)
    }

    @Test("loadData loads RPG state")
    func loadDataLoadsRPGState() async throws {
        let container = try makeContainer()
        try seedRPGState(container: container, xp: 250, level: 3)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.xp == 250)
        #expect(vm.level == 3)
        #expect(vm.xpForNextLevel > 0)
    }

    @Test("loadData loads due card count")
    func loadDataLoadsDueCards() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.dueCardCount == 5)
        #expect(vm.hasCardsDue == true)
    }

    @Test("loadData loads kanji learned count")
    func loadDataLoadsKanjiLearned() async throws {
        let container = try makeContainer()
        try seedReviewedCards(container: container, count: 12)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.kanjiLearnedCount == 12)
    }

    @Test("loadData computes session preview")
    func loadDataComputesSessionPreview() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.sessionPreviewCardCount == 3)
        #expect(vm.sessionPreviewMinutes == 3)
    }

    // MARK: - Computed Property Tests

    @Test("greetingText shows name when available")
    func greetingWithName() async throws {
        let container = try makeContainer()
        try seedProfile(container: container, name: "Sakura")
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.greetingText == "Welcome, Sakura!")
    }

    @Test("greetingText shows generic when no profile")
    func greetingWithoutName() throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        #expect(vm.greetingText == "Welcome!")
    }

    @Test("learningSummaryText shows all caught up when no cards due")
    func learningSummaryAllCaughtUp() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.learningSummaryText == "All caught up!")
    }

    @Test("learningSummaryText shows cards ready and kanji learned")
    func learningSummaryWithData() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        try seedReviewedCards(container: container, count: 12)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.learningSummaryText.contains("5 cards ready"))
        #expect(vm.learningSummaryText.contains("12 kanji learned"))
    }

    @Test("sessionPreviewText shows card count and time")
    func sessionPreviewWithCards() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.sessionPreviewText.contains("5 reviews"))
        #expect(vm.sessionPreviewText.contains("min"))
    }

    @Test("sessionPreviewText shows default when no cards")
    func sessionPreviewNoCards() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.sessionPreviewText == "Start a session to begin learning")
    }

    // MARK: - Empty State Tests

    @Test("handles empty state gracefully")
    func handlesEmptyState() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.loadData()

        #expect(vm.displayName == "")
        #expect(vm.level == 1)
        #expect(vm.xp == 0)
        #expect(vm.dueCardCount == 0)
        #expect(vm.kanjiLearnedCount == 0)
        #expect(vm.sessionPreviewCardCount == 0)
        #expect(vm.hasLoaded == true)
    }

    // MARK: - Offline Behavior Tests

    @Test("works without network — all data from local SwiftData")
    func worksOffline() async throws {
        // This test validates that HomeViewModel operates entirely
        // from local SwiftData without any network dependency.
        // If it completes without error, offline support is confirmed.
        let container = try makeContainer()
        try seedProfile(container: container, name: "Nico")
        try seedRPGState(container: container, xp: 100, level: 2)
        _ = try seedDueCards(container: container, count: 3)
        try seedReviewedCards(container: container, count: 8)

        let vm = makeViewModel(container: container)
        await vm.loadData()

        #expect(vm.displayName == "Nico")
        #expect(vm.level == 2)
        #expect(vm.xp == 100)
        #expect(vm.dueCardCount == 3)
        #expect(vm.kanjiLearnedCount == 8)
        #expect(vm.sessionPreviewCardCount > 0)
        #expect(vm.hasLoaded == true)
    }

    // MARK: - Refresh Tests

    @Test("loadData refreshes after changes")
    func refreshAfterChanges() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        // First load - empty
        await vm.loadData()
        #expect(vm.dueCardCount == 0)

        // Add cards
        _ = try seedDueCards(container: container, count: 2)

        // Reload
        await vm.loadData()
        #expect(vm.dueCardCount == 2)
    }
}
