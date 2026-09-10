import Testing
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// The Compose sheet's state (Étude → « Composer une séance ») — the opt-in
/// door `DefaultSessionPlanner.untaughtContentTypes` justified itself with
/// for seven weeks while it did not exist.
@Suite("ComposeSessionViewModel")
@MainActor
struct ComposeSessionViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        // Live types by name, not a `versionedSchema:` — this suite must not
        // bind an entity to a frozen nested snapshot whichever version is
        // current when it runs (see IkeruSchema.swift's V3 doc comment).
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self, ExerciseOutcomeLog.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @discardableResult
    private func seedProfile(_ container: ModelContainer) throws -> UserProfile {
        let profile = UserProfile(displayName: "Compose")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return profile
    }

    private func makeViewModel(_ container: ModelContainer) -> ComposeSessionViewModel {
        ComposeSessionViewModel(
            cardRepository: CardRepository(modelContainer: container),
            modelContainer: container
        )
    }

    @Test("The offer lists exactly the composable types, in order, and a fresh learner sees the locks")
    func offersFollowTheComposableListWithLocks() async throws {
        let container = try makeContainer()
        try seedProfile(container)
        let viewModel = makeViewModel(container)

        await viewModel.load()

        #expect(viewModel.hasLoaded)
        #expect(viewModel.offers.map(\.type) == ExerciseType.composableInStudySession)
        // Day one: kanji, vocabulary and listening are open; the gated ones
        // are shown, locked, with their reason — never hidden.
        let states = Dictionary(uniqueKeysWithValues: viewModel.offers.map { ($0.type, $0.unlockState) })
        #expect(states[.kanjiStudy] == .unlocked)
        #expect(states[.vocabularyStudy] == .unlocked)
        #expect(states[.listeningSubtitled] == .unlocked)
        #expect(states[.grammarExercise] == .locked(reason: .kanaMastered(syllabary: .hiragana)))
        #expect(states[.sentenceConstruction]
                == .locked(reason: .grammarPointsMastered(required: 5, current: 0)))
        #expect(states[.writingPractice] == .locked(reason: .kanaMastered(syllabary: .hiragana)))
        #expect(states[.speakingPractice]
                == .locked(reason: .listeningRecallOver(required: 0.6, current: 0, days: 30)))
        #expect(!viewModel.offers.contains { $0.type.isRetired })
    }

    @Test("A locked type cannot be selected; an unlocked one toggles; canStart follows the selection")
    func selectionRespectsLocks() async throws {
        let container = try makeContainer()
        try seedProfile(container)
        let viewModel = makeViewModel(container)
        await viewModel.load()

        #expect(!viewModel.canStart)
        viewModel.toggle(.grammarExercise)
        #expect(!viewModel.isSelected(.grammarExercise), "a locked type was selected")
        #expect(!viewModel.canStart)

        viewModel.toggle(.vocabularyStudy)
        #expect(viewModel.isSelected(.vocabularyStudy))
        #expect(viewModel.canStart)
        viewModel.toggle(.vocabularyStudy)
        #expect(!viewModel.isSelected(.vocabularyStudy))
        #expect(!viewModel.canStart)
    }

    /// The honesty rule: a selection that composes nothing never opens a
    /// session. Kanji study needs a kanji card to back it; with none, the
    /// planner synthesises nothing and `start` says so.
    @Test("start returns false when the selection composes nothing, and never starts a session")
    func startIsHonestOnEmptyComposition() async throws {
        let container = try makeContainer()
        try seedProfile(container)
        let viewModel = makeViewModel(container)
        await viewModel.load()
        viewModel.toggle(.kanjiStudy)
        #expect(viewModel.canStart)

        let repo = CardRepository(modelContainer: container)
        let session = SessionViewModel(
            plannerService: PlannerService(cardRepository: repo),
            cardRepository: repo,
            modelContainer: container
        )
        let started = await viewModel.start(on: session)
        #expect(!started)
        #expect(!session.isActive)
        #expect(session.sessionExercises.isEmpty)
    }

    /// The positive half: vocabulary recall is open from day one and needs
    /// no card behind it — the plan is what is asserted here; the words
    /// themselves come from the bundle at render time.
    @Test("start opens a session when the selection composes something")
    func startOpensASessionWhenSomethingComposes() async throws {
        let container = try makeContainer()
        try seedProfile(container)
        let repo = CardRepository(modelContainer: container)
        let viewModel = makeViewModel(container)
        await viewModel.load()
        viewModel.toggle(.vocabularyStudy)
        viewModel.durationMinutes = 5
        #expect(viewModel.canStart)

        let session = SessionViewModel(
            plannerService: PlannerService(cardRepository: repo),
            cardRepository: repo,
            modelContainer: container
        )
        let started = await viewModel.start(on: session)
        #expect(started)
        #expect(session.isActive)
        #expect(!session.sessionExercises.isEmpty)
        #expect(session.sessionExercises.allSatisfy {
            if case .vocabularyStudy = $0 { return true }
            return false
        })
    }
}
