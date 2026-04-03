import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("SessionConfigViewModel — Time and Context Adaptation")
@MainActor
struct SessionConfigIntegrationTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeConfigViewModel(
        container: ModelContainer,
        volume: Float = 0.5
    ) -> SessionConfigViewModel {
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        let detector = MockVolumeDetector(volume: volume)
        return SessionConfigViewModel(
            volumeDetector: detector,
            plannerService: planner
        )
    }

    private func seedDueCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        for i in 0..<count {
            let card = Card(
                front: "Due \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 1),
                dueDate: Date().addingTimeInterval(-3600)
            )
            context.insert(card)
        }
        try context.save()
    }

    private func seedMixedCards(container: ModelContainer, count: Int = 20) throws {
        let context = container.mainContext
        let types: [CardType] = [.kanji, .vocabulary, .grammar, .listening]
        for i in 0..<count {
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

    // MARK: - Micro Session (5 min) — SRS Only

    @Test("Micro session (5 min) produces only SRS reviews")
    func microSessionSRSOnly() async throws {
        let container = try makeContainer()
        try seedDueCards(container: container, count: 8)
        let vm = makeConfigViewModel(container: container)

        await vm.selectTime(5)

        let preview = vm.preview
        #expect(preview.cardCount > 0)

        // Micro sessions should only have reading (SRS reviews map to reading skill)
        // No listening or speaking exercises
        let hasListening = (preview.exerciseBreakdown[.listening] ?? 0) > 0
        let hasSpeaking = (preview.exerciseBreakdown[.speaking] ?? 0) > 0
        #expect(hasListening == false, "Micro session should not include listening")
        #expect(hasSpeaking == false, "Micro session should not include speaking")
    }

    // MARK: - Focused Session (30 min) — Mixed Exercises

    @Test("Focused session (30 min) produces mixed exercises across skills")
    func focusedSessionMixedExercises() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let vm = makeConfigViewModel(container: container)

        await vm.selectTime(30)

        let preview = vm.preview
        #expect(preview.cardCount > 0)
        #expect(preview.estimatedMinutes > 0)

        // Focused sessions should have more than just reading
        let skillCount = preview.exerciseBreakdown.count
        #expect(skillCount >= 2, "Focused session should cover multiple skills")
    }

    // MARK: - Muted Mode — Audio Excluded

    @Test("Muted mode excludes audio exercises")
    func mutedModeExcludesAudio() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let vm = makeConfigViewModel(container: container, volume: 0)

        await vm.selectTime(30)

        #expect(vm.isMuted == true)

        let preview = vm.preview
        let hasListening = (preview.exerciseBreakdown[.listening] ?? 0) > 0
        let hasSpeaking = (preview.exerciseBreakdown[.speaking] ?? 0) > 0
        #expect(hasListening == false, "Muted mode should exclude listening")
        #expect(hasSpeaking == false, "Muted mode should exclude speaking")
    }

    // MARK: - Preview Updates

    @Test("Preview updates when time selection changes")
    func previewUpdatesOnTimeChange() async throws {
        let container = try makeContainer()
        try seedMixedCards(container: container)
        let vm = makeConfigViewModel(container: container)

        await vm.selectTime(5)
        let microPreview = vm.preview

        await vm.selectTime(30)
        let focusedPreview = vm.preview

        // Focused should have more exercises than micro
        #expect(
            focusedPreview.cardCount >= microPreview.cardCount,
            "Focused session should have at least as many exercises as micro"
        )
    }

    // MARK: - Config Building

    @Test("buildConfig reflects current selections")
    func buildConfigReflectsSelections() async throws {
        let container = try makeContainer()
        let vm = makeConfigViewModel(container: container, volume: 0)

        await vm.selectTime(10)

        let config = vm.buildConfig()
        #expect(config.availableTimeMinutes == 10)
        #expect(config.isSilentMode == true)
    }

    @Test("buildConfig with normal volume is not silent")
    func buildConfigNormalVolumeNotSilent() async throws {
        let container = try makeContainer()
        let vm = makeConfigViewModel(container: container, volume: 0.7)

        await vm.onAppear()

        let config = vm.buildConfig()
        #expect(config.isSilentMode == false)
    }

    // MARK: - Time Presets

    @Test("Time presets contain expected values")
    func timePresetsContainExpectedValues() async throws {
        let container = try makeContainer()
        let vm = makeConfigViewModel(container: container)

        let minutes = vm.timePresets.map(\.minutes)
        #expect(minutes.contains(5))
        #expect(minutes.contains(10))
        #expect(minutes.contains(20))
        #expect(minutes.contains(30))
        #expect(minutes.contains(45))
    }

    // MARK: - Default State

    @Test("Default selected minutes is 20")
    func defaultSelectedMinutes() async throws {
        let container = try makeContainer()
        let vm = makeConfigViewModel(container: container)
        #expect(vm.selectedMinutes == 20)
    }

    @Test("Initial preview is empty before onAppear")
    func initialPreviewEmpty() async throws {
        let container = try makeContainer()
        let vm = makeConfigViewModel(container: container)
        #expect(vm.preview == .empty)
    }
}
