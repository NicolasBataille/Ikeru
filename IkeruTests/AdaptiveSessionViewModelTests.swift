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

    private func seedMixedCards(container: ModelContainer) throws {
        let context = container.mainContext
        let types: [CardType] = [.kanji, .vocabulary, .grammar, .listening]
        for i in 0..<20 {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: types[i % types.count],
                fsrsState: FSRSState(reps: 1),
                dueDate: Date().addingTimeInterval(-3600)
            )
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

        #expect(vm.sessionPreview.cardCount == 0)
        #expect(vm.sessionPreview == SessionPreview.empty)
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
        #expect(vm.isSessionComplete == true) // No cards
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
