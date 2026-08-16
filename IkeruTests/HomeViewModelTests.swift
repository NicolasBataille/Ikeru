import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// GAP-10: cross-suite SwiftData isolation — see SwiftDataTestIsolation.swift.
@Suite("HomeViewModel", .swiftDataIsolated)
@MainActor
struct HomeViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        // Clear any active-profile id leaked from a prior test run; the
        // resolver persists it in UserDefaults which crosses test boundaries.
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeViewModel(container: ModelContainer) -> HomeViewModel {
        HomeViewModel(modelContainer: container)
    }

    @discardableResult
    private func seedProfile(container: ModelContainer, name: String) throws -> UserProfile {
        let context = container.mainContext
        let profile = UserProfile(displayName: name)
        context.insert(profile)
        try context.save()
        // Mark this profile active so the resolver finds it deterministically.
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return profile
    }

    /// Seeds the active profile's RPG state (creating the profile if the test
    /// forgot to). The resolver's `fetchActiveRPGState` requires a
    /// profile→state attachment, so a standalone insert is invisible to the
    /// view model.
    ///
    /// Mutates the state the profile ALREADY owns rather than minting a rival
    /// one. `UserProfile.init` always creates its own `RPGState` (see that
    /// initializer), so "seed an RPG state" never means "attach a new one" —
    /// it means "set the values on the one that is already there". Doing it
    /// the other way round is what crashed the whole test runner for months;
    /// `swiftDataOwningSideDisplacementTraps()` below holds the measurement.
    private func seedRPGState(container: ModelContainer, xp: Int, level: Int) throws {
        let context = container.mainContext
        let profile: UserProfile = try {
            if let existing = ActiveProfileResolver.fetchActiveProfile(in: context) {
                return existing
            }
            return try seedProfile(container: container, name: "Test")
        }()
        let state: RPGState = try {
            if let existing = profile.rpgState { return existing }
            // Only reachable for a profile built without `UserProfile.init`
            // (none today). Assigning the INVERSE side is safe here precisely
            // because there is nothing to displace.
            let fresh = RPGState()
            profile.rpgState = fresh
            context.insert(fresh)
            try context.save()
            return fresh
        }()
        state.xp = xp
        state.level = level
        state.totalReviewsCompleted = 10
        try context.save()
    }

    /// Resolves the currently-active profile for tests, creating one if
    /// missing. Cards must attach to an active profile because
    /// `CardRepository` queries are scoped to `profile.cards`.
    private func ensureProfile(container: ModelContainer) throws -> UserProfile {
        let context = container.mainContext
        if let existing = ActiveProfileResolver.fetchActiveProfile(in: context) {
            return existing
        }
        return try seedProfile(container: container, name: "Test")
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
                dueDate: Date().addingTimeInterval(-3600) // Due 1 hour ago
            )
            card.profile = profile
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    private func seedReviewedCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
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
            card.profile = profile
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

    // MARK: - GAP-10 regression

    /// Pins the rule that cost this repo its whole app-target test suite.
    ///
    /// **Measured, 2026-08-16** (bisected statement by statement inside a
    /// single `-only-testing:` run, so nothing else was in the process):
    /// assigning the **owning side** of a to-one SwiftData relationship —
    /// `newState.profile = profile` — when `profile` already owns a *saved*
    /// `RPGState` traps the process:
    ///
    ///   SwiftData/BackingData.swift:940: Fatal error: Never access a full
    ///   future backing data - PersistentIdentifier(... /RPGState/p1 ...)
    ///
    /// Assigning the **inverse side** on the same data — `profile.rpgState =
    /// newState` — does not trap. Neither `context.insert(newState)` before
    /// the assignment nor reading `profile.rpgState` first (to materialize
    /// the object being displaced) avoids it; both were tried and both still
    /// crashed. The trigger is the displacement itself, through the owning
    /// side, of a child that has already been saved. When the profile was
    /// never saved, the displaced child holds a temporary identifier and
    /// nothing traps — which is the only reason `DataExportManagerTests`
    /// stayed green in CI while carrying the same shape.
    ///
    /// Two consequences the codebase depends on:
    /// 1. `UserProfile.init` mints its own `RPGState`, so a profile ALWAYS
    ///    owns one. "Seeding" an RPG state therefore means mutating that
    ///    one, never attaching a second.
    /// 2. Production is safe by construction, not by luck:
    ///    `ActiveProfileResolver.fetchActiveRPGState` returns early when
    ///    `profile.rpgState` is non-nil, and `SyncPullActor`'s RPG upsert
    ///    routes the "profile already has a state" case through its
    ///    orphan-adoption branch. Both reach `state.profile = …` only when
    ///    there is nothing to displace. Keep it that way.
    ///
    /// This test asserts the SAFE path stays safe. It deliberately does not
    /// assert the crash — that would take the runner down with it.
    @Test("GAP-10: seeding RPG state mutates the profile's own, never a rival")
    func swiftDataOwningSideDisplacementTraps() async throws {
        let container = try makeContainer()
        let profile = try seedProfile(container: container, name: "Test")
        let originalStateID = profile.rpgState?.persistentModelID
        #expect(originalStateID != nil, "UserProfile.init must still mint an RPGState")

        try seedRPGState(container: container, xp: 250, level: 3)

        // Same object, new values — no second RPGState was ever created.
        #expect(profile.rpgState?.persistentModelID == originalStateID)
        #expect(profile.rpgState?.xp == 250)

        let all = try container.mainContext.fetch(FetchDescriptor<RPGState>())
        #expect(all.count == 1, "a rival RPGState would orphan the profile's own")
    }
}
