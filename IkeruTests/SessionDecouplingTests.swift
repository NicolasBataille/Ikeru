import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Regression coverage for Phase 4.1 Step 2 — decoupling `SessionViewModel`'s
/// two parallel index-tracked arrays (`sessionQueue`/`currentIndex` and
/// `sessionExercises`/`currentExerciseIndex`).
///
/// These sessions deliberately contain NON-SRS `ExerciseItem`s interleaved with
/// `.srsReview` items. In production `DefaultSessionPlanner.finalize()` still
/// filters the exercise list down to `.srsReview` only, so this shape is not yet
/// reachable there — the tests inject it through the existing `MockSessionPlanner`
/// seam (which returns a fixed plan verbatim, and `startSession` builds
/// `sessionQueue` from the plan's `.srsReview` items exactly as production does).
/// No production access was loosened to make these run.
@Suite("Session Decoupling (4.1 Step 2)")
@MainActor
struct SessionDecouplingTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

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

    /// Marks the active profile's RPGState as "already had a session today" so
    /// the first-session-of-day bonus doesn't perturb XP. Harmless no-op if no
    /// RPGState exists yet (these tests assert on indices/counts, not raw XP).
    private func suppressFirstSessionBonus(container: ModelContainer) throws {
        let context = container.mainContext
        _ = try ensureProfile(container: container)
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        state.lastSessionDate = Date()
        try context.save()
    }

    /// Seeds one `.kanji` card per front string, all overdue (staggered so
    /// due-sort ordering is deterministic), attached to the active profile.
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

    private func makeVM(
        container: ModelContainer,
        planner: any SessionPlanner
    ) -> SessionViewModel {
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

    /// The correspondence invariant this whole PR protects: `sessionQueue` must
    /// always equal the `.srsReview` payloads of `sessionExercises`, in order.
    /// If it holds, the deck's `currentIndex`-addressed card always matches the
    /// `.srsReview` exercise the user is shown.
    private func queueMatchesExercises(_ vm: SessionViewModel) -> Bool {
        let derived = vm.sessionExercises.compactMap { item -> UUID? in
            if case .srsReview(let card) = item { return card.id }
            return nil
        }
        return vm.sessionQueue.map(\.id) == derived
    }

    private func dto(_ front: String, in dtos: [CardDTO]) throws -> CardDTO {
        try #require(dtos.first { $0.front == front })
    }

    // MARK: - Scenario A — kanjiStudy must not advance the SRS queue pointer

    @Test("Scenario A: completing .kanjiStudy grades its card, leaves currentIndex, and does not end the session")
    func kanjiStudyDoesNotAdvanceQueue() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A", "K"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let k = try dto("K", in: dtos)

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.kanjiStudy(k), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        // sessionQueue is the .srsReview compactMap → [A]; K is never in it.
        #expect(vm.sessionQueue.count == 1)
        #expect(vm.currentExercise == .kanjiStudy(k))
        #expect(vm.currentCard?.id == a.id)

        await vm.completeCurrentExercise(grade: .good)

        // The SRS queue pointer must NOT move — A is still the current card.
        #expect(vm.currentIndex == 0)
        #expect(vm.currentCard?.id == a.id)
        // The exercise pointer advanced to the trailing SRS review.
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .srsReview(a))
        // The session is NOT prematurely complete.
        #expect(vm.isSessionComplete == false)

        // 4.4 hook: K graded via FSRS, A left untouched (it hasn't been graded).
        let kLogs = await repo.reviewLogs(for: k.id)
        let aLogs = await repo.reviewLogs(for: a.id)
        #expect(kLogs.count == 1)
        #expect(aLogs.isEmpty)
        #expect(vm.reviewedCount == 1)
    }

    // MARK: - Scenario B — a trailing non-SRS exercise must not be dropped

    @Test("Scenario B: a non-SRS exercise scheduled after the last SRS card is still presented, not dropped")
    func trailingNonSRSNotDropped() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let sentenceID = UUID()

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.srsReview(a), .sentenceConstruction(sentenceID)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 1)

        // Grade the last (only) SRS card.
        await vm.gradeAndAdvance(grade: .good)

        // Old gating (currentIndex >= sessionQueue.count) would report complete
        // here and drop the sentence. It must stay open and present it.
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .sentenceConstruction(sentenceID))

        // Completing the trailing exercise ends the session cleanly.
        await vm.completeCurrentExercise(grade: .good)
        #expect(vm.isSessionComplete == true)
        #expect(vm.currentExerciseIndex == 2)
        #expect(vm.reviewedCount == 2)
    }

    // MARK: - Scenario C — every interleaved exercise runs

    @Test("Scenario C: session runs all four interleaved exercises, not ending at 2/4")
    func runsAllInterleavedExercises() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A", "B"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let b = try dto("B", in: dtos)
        let s1 = UUID()
        let s2 = UUID()

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([
            .srsReview(a), .srsReview(b),
            .sentenceConstruction(s1), .sentenceConstruction(s2)
        ])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 2)
        #expect(vm.sessionExercises.count == 4)

        // Grade the two SRS cards.
        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.isSessionComplete == false)
        await vm.gradeAndAdvance(grade: .good)
        // Old behavior would end here (currentIndex 2 >= queue 2). It must not.
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentExerciseIndex == 2)

        // Complete the two trailing sentence exercises.
        await vm.completeCurrentExercise(grade: .good)
        #expect(vm.isSessionComplete == false)
        #expect(vm.currentExerciseIndex == 3)
        await vm.completeCurrentExercise(grade: .good)

        #expect(vm.isSessionComplete == true)
        #expect(vm.currentExerciseIndex == 4)
        #expect(vm.reviewedCount == 4)
    }

    // MARK: - Scenario D — requeue keeps card↔exercise correspondence

    @Test("Scenario D: an .again requeue with an interleaved non-SRS item keeps sessionQueue in correspondence with the exercise list")
    func requeueKeepsCorrespondenceWithInterleavedNonSRS() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        // A .kanjiStudy sits between the graded card and where the requeue lands.
        // With enough trailing SRS cards, the non-SRS item is inside the 3-5
        // offset window for EVERY random offset, so the old independent-offset
        // insertion desyncs the two arrays regardless of the RNG; the coordinated
        // insertion keeps them equal.
        try seedCards(container: container, fronts: ["A", "B", "C", "D", "E", "F", "G", "K"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let k = try dto("K", in: dtos)

        var exercises: [ExerciseItem] = [.srsReview(a), .kanjiStudy(k)]
        for f in ["B", "C", "D", "E", "F", "G"] {
            exercises.append(.srsReview(try dto(f, in: dtos)))
        }
        // exercises = [srs(A), kanji(K), srs(B…G)] ; queue = [A, B, C, D, E, F, G]

        let planner = MockSessionPlanner()
        planner.plan = buildPlan(exercises)
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 7)
        #expect(vm.currentCard?.id == a.id)

        // Fail A → same-day requeue inserts a copy some slots later.
        await vm.gradeAndAdvance(grade: .again)

        // The correspondence invariant must hold after the requeue. (The old
        // independent-offset insertion breaks this whenever a non-SRS item sits
        // in the offset window.)
        #expect(vm.sessionQueue.count == 8)
        #expect(queueMatchesExercises(vm))

        // Walk the rest: every SRS review the deck shows must be the card
        // `currentCard` resolves — never a shifted one. Bounded to avoid an
        // accidental infinite loop.
        var guardCount = 0
        while !vm.isSessionComplete && guardCount < 64 {
            guardCount += 1
            if case .srsReview(let shownCard)? = vm.currentExercise {
                #expect(vm.currentCard?.id == shownCard.id)
                await vm.gradeAndAdvance(grade: .good)
            } else {
                await vm.completeCurrentExercise(grade: .good)
            }
            // The invariant holds at every step of the walk too.
            #expect(queueMatchesExercises(vm))
        }
        #expect(vm.isSessionComplete == true)
    }

    // MARK: - Pure-SRS regression — behavior identical to before the decoupling

    @Test("Pure-SRS regression: end detection and counts unchanged; the two pointers stay in lockstep")
    func pureSRSSessionUnchanged() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A", "B", "C"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let planner = MockSessionPlanner()
        planner.plan = buildPlan(dtos.map { ExerciseItem.srsReview($0) })
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.sessionQueue.count == 3)
        #expect(vm.sessionExercises.count == 3)

        for step in 1...3 {
            #expect(vm.isSessionComplete == false)
            // In a pure-SRS session the two pointers move together, so the new
            // exercise-list gating stays equivalent to the old queue gating.
            #expect(vm.currentIndex == vm.currentExerciseIndex)
            await vm.gradeAndAdvance(grade: .good)
            #expect(vm.currentIndex == step)
            #expect(vm.currentExerciseIndex == step)
        }

        #expect(vm.isSessionComplete == true)
        #expect(vm.reviewedCount == 3)
        #expect(vm.currentIndex == vm.sessionQueue.count)
        #expect(vm.currentExerciseIndex == vm.sessionExercises.count)
    }

    @Test("Pure-SRS regression: an .again requeue still coordinates both arrays (correspondence invariant)")
    func pureSRSRequeueInvariant() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A", "B", "C", "D", "E", "F"])
        let dtos = await repo.allCards()
        let planner = MockSessionPlanner()
        planner.plan = buildPlan(dtos.map { ExerciseItem.srsReview($0) })
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        let before = vm.sessionQueue.count

        await vm.gradeAndAdvance(grade: .again)

        #expect(vm.sessionQueue.count == before + 1)
        #expect(vm.sessionExercises.count == before + 1)
        #expect(queueMatchesExercises(vm))
        // Session stays open so the requeued card is reachable.
        #expect(vm.isSessionComplete == false)
    }
}
