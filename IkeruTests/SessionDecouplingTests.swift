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
        // Full current (V4) schema so pool-drill outcomes (ExerciseOutcomeLog)
        // can persist. Must be V4, not V3: `IkeruSchemaV3` is now frozen
        // (nested snapshot types, cloud-sync lot 0, 2026-08-13) — a
        // container opened with `versionedSchema: IkeruSchemaV3.self` would
        // bind this suite's live-type fetches (via `ActiveProfileResolver` /
        // `SessionViewModel`) to the WRONG entity identity and crash with
        // "Failed to cast model ... to X". See IkeruSchema.swift's
        // `IkeruSchemaV3` doc comment.
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
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

    @Test("Scenario A2: completing .writingPractice grades its card via FSRS, leaves currentIndex, does not end the session (remediation 4.4)")
    func writingPracticeGradesCardWithoutAdvancingQueue() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A", "W"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let w = try dto("W", in: dtos)

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.writingPractice(w), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        // sessionQueue is the .srsReview compactMap → [A]; W is never in it.
        #expect(vm.sessionQueue.count == 1)
        #expect(vm.currentExercise == .writingPractice(w))
        #expect(vm.currentCard?.id == a.id)

        await vm.completeCurrentExercise(grade: .good)

        // The SRS queue pointer must NOT move — W's card is not in sessionQueue.
        #expect(vm.currentIndex == 0)
        #expect(vm.currentCard?.id == a.id)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .srsReview(a))
        #expect(vm.isSessionComplete == false)

        // 4.4: W graded via FSRS (a ReviewLog written), A untouched.
        let wLogs = await repo.reviewLogs(for: w.id)
        let aLogs = await repo.reviewLogs(for: a.id)
        #expect(wLogs.count == 1)
        #expect(aLogs.isEmpty)
        #expect(vm.reviewedCount == 1)
    }

    @Test("Scenario A3: kanjiStudy + writingPractice on the SAME card grade FSRS once, not twice (dedup guard)")
    func sameCardKanjiAndWritingGradesOnce() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        // A trailing .srsReview card (A) is required so the session is non-empty
        // (`startSession` bails when no SRS cards are composable). The dedup is
        // exercised by K appearing as BOTH kanjiStudy and writingPractice.
        try seedCards(container: container, fronts: ["A", "K"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let k = try dto("K", in: dtos)

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.kanjiStudy(k), .writingPractice(k), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        await vm.completeCurrentExercise(grade: .good) // kanjiStudy(K) → grades K
        await vm.completeCurrentExercise(grade: .good) // writingPractice(K) → dedup: XP only

        // K is FSRS-graded exactly once despite two card-backed completions.
        let kLogs = await repo.reviewLogs(for: k.id)
        #expect(kLogs.count == 1)
        // Both K exercises still counted as completed (XP awarded for both).
        #expect(vm.reviewedCount == 2)
        // A hasn't been graded yet (still the current SRS card).
        let aLogs = await repo.reviewLogs(for: a.id)
        #expect(aLogs.isEmpty)
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

    @Test("Completing a .listeningExercise records an outcome that feeds listeningAccuracyLast30 (remediation 4.4)")
    func listeningExerciseRecordsOutcome() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        // Trailing SRS card so the session starts; the listening drill has no card.
        try seedCards(container: container, fronts: ["A"])
        try suppressFirstSessionBonus(container: container)
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let listeningID = UUID()

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.listeningExercise(listeningID), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.currentExercise == .listeningExercise(listeningID))

        // No outcome recorded yet.
        #expect(await repo.listeningAccuracyLast30() == 0)

        // A correct listening answer → grade .good → accuracy 1.0 persisted.
        await vm.completeCurrentExercise(grade: .good)

        #expect(await repo.listeningAccuracyLast30() == 1.0)
        // Listening completion writes NO FSRS ReviewLog (it has no backing card).
        #expect(await repo.reviewLogs(for: a.id).isEmpty)
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

// MARK: - New-Card Presentation (2026-08 pedagogy P2, chantier #21)
//
// A never-reviewed KANA card must get an ungraded presentation pass before
// its first graded touch-and-reveal test, and that graded test must be
// delayed a few real recall events later — see `NewCardPresentationScheduler`
// in `SessionComposer.swift` and `SessionViewModel.isPresentingNewCard` /
// `completeNewCardPresentation`.
@Suite("New-Card Presentation (chantier #21)")
@MainActor
struct NewCardPresentationTests {

    // MARK: - Fixtures

    private func kanaCard(front: String, romaji: String, reps: Int = 0) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: romaji,
            type: .vocabulary,
            fsrsState: FSRSState(reps: reps),
            easeFactor: 2.5,
            interval: 0,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false
        )
    }

    private func kanjiCard(front: String, reps: Int = 0) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "back-\(front)",
            type: .kanji,
            fsrsState: FSRSState(reps: reps),
            easeFactor: 2.5,
            interval: 0,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false
        )
    }

    private func srsReviewPositions(of cardID: UUID, in exercises: [ExerciseItem]) -> [Int] {
        exercises.enumerated().compactMap { index, item -> Int? in
            if case .srsReview(let card) = item, card.id == cardID { return index }
            return nil
        }
    }

    // MARK: - Pure scheduler tests (NewCardPresentationScheduler)

    @Test("A never-reviewed kana card is duplicated: an intro slot plus a delayed graded-test slot")
    func newKanaCardGetsIntroAndDelayedTest() {
        let newKana = kanaCard(front: "あ", romaji: "a")
        // Two already-started filler reviews: the tail must be able to supply
        // the requested gap, otherwise the scheduler deliberately declines to
        // defer (see `shortTailDeclinesToDefer` below).
        let due1 = kanjiCard(front: "\u{751F}", reps: 3)
        let due2 = kanjiCard(front: "\u{5B66}", reps: 4)
        let exercises: [ExerciseItem] = [.srsReview(newKana), .srsReview(due1), .srsReview(due2)]

        let result = NewCardPresentationScheduler.schedulingPresentations(
            for: exercises,
            offsetRange: 2...2
        )

        #expect(result.cardsNeedingPresentation == [newKana.id])
        let positions = srsReviewPositions(of: newKana.id, in: result.exercises)
        #expect(positions.count == 2)
        #expect(positions.first == 0)
        // The delayed test lands after 2 MORE `.srsReview` occurrences, so the
        // two occurrences of `a` are 3 apart — outside the deck's 3-deep peek
        // window, and far enough for the recall to measure something.
        #expect(positions.last == 3)
        #expect(result.addedDurationSeconds == ExerciseItem.srsReview(newKana).estimatedDurationSeconds)
    }

    @Test("A tail too short to give the delayed test any interference declines to defer at all")
    func shortTailDeclinesToDefer() {
        let newKana = kanaCard(front: "あ", romaji: "a")
        let due = kanjiCard(front: "\u{751F}", reps: 3)
        // Only ONE other review follows the new card. Appending the test at the
        // end would put it immediately after its own presentation: it would
        // measure nothing, and both occurrences would sit inside the deck's
        // 3-deep peek window with the same card id (duplicate
        // matchedGeometryEffect). The scheduler declines instead — the card
        // stays a plain graded review, exactly as before the feature existed.
        let exercises: [ExerciseItem] = [.srsReview(newKana), .srsReview(due)]

        let result = NewCardPresentationScheduler.schedulingPresentations(
            for: exercises,
            offsetRange: 2...2
        )

        #expect(result.cardsNeedingPresentation.isEmpty)
        #expect(result.exercises.count == exercises.count)
        #expect(result.addedDurationSeconds == 0)
        #expect(srsReviewPositions(of: newKana.id, in: result.exercises).count == 1)
    }

    @Test("The delayed test lands after exactly `target` MORE .srsReview occurrences, non-.srsReview items don't count")
    func delayedTestCountsOnlySRSReviewOccurrences() {
        let newKana = kanaCard(front: "い", romaji: "i")
        let b = kanjiCard(front: "\u{5B66}", reps: 5)
        let kanjiC = kanjiCard(front: "\u{6821}", reps: 5)
        // 1 non-.srsReview item, then 2 more .srsReview items — target=2 must
        // land right after `c`, ignoring the listening exercise entirely.
        let exercises: [ExerciseItem] = [
            .srsReview(newKana), .listeningExercise(UUID()), .srsReview(b), .srsReview(kanjiC),
        ]

        let result = NewCardPresentationScheduler.schedulingPresentations(
            for: exercises,
            offsetRange: 2...2
        )

        let positions = srsReviewPositions(of: newKana.id, in: result.exercises)
        #expect(positions.count == 2)
        // Original array: [a, listening, b, c] (indices 0..3). After
        // inserting the delayed test right after `c` (index 3), it lands at
        // index 4 — the new end of the array.
        #expect(positions.last == 4)
        #expect(result.exercises.count == exercises.count + 1)
    }

    @Test("A non-kana never-reviewed card is left untouched (kana-only scoping)")
    func nonKanaNewCardIsNotDuplicated() {
        let kanjiNew = kanjiCard(front: "\u{65E5}", reps: 0)
        let exercises: [ExerciseItem] = [.srsReview(kanjiNew)]

        let result = NewCardPresentationScheduler.schedulingPresentations(for: exercises)

        #expect(result.cardsNeedingPresentation.isEmpty)
        #expect(result.exercises == exercises)
        #expect(result.addedDurationSeconds == 0)
    }

    @Test("An already-started kana card (reps > 0) is left untouched")
    func alreadyStartedKanaCardIsNotDuplicated() {
        let newKana = kanaCard(front: "う", romaji: "u", reps: 1)
        let exercises: [ExerciseItem] = [.srsReview(newKana)]

        let result = NewCardPresentationScheduler.schedulingPresentations(for: exercises)

        #expect(result.cardsNeedingPresentation.isEmpty)
        #expect(result.exercises == exercises)
    }

    // MARK: - Integration (SessionViewModel)

    private func makeContainer() throws -> ModelContainer {
        // V4, not V3: `IkeruSchemaV3` is now frozen (nested snapshot types,
        // cloud-sync lot 0, 2026-08-13) — see the other `makeContainer()`
        // above in this file for the full "Failed to cast model" story.
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func ensureProfile(container: ModelContainer) throws {
        let context = container.mainContext
        if ActiveProfileResolver.fetchActiveProfile(in: context) != nil { return }
        let profile = UserProfile(displayName: "Test")
        context.insert(profile)
        try context.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
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

    @Test("completeNewCardPresentation writes no FSRS grade and doesn't touch correctness counters; the delayed test does")
    func presentationIsUngradedAndDelayedTestIsTheRealFirstGrade() async throws {
        let container = try makeContainer()
        try ensureProfile(container: container)
        let repo = CardRepository(modelContainer: container)

        let newKana = await repo.createCard(front: "え", back: "e", type: .vocabulary)
        // Two filler reviews so the delayed test has something to be placed
        // after. They are ALSO `reps == 0` (freshly created), so grading them
        // during the walk contributes its own "new item learned" / graded
        // attempt signal — the assertions below are deliberately DELTA-based
        // (captured right before the delayed grade) so they isolate `a`'s
        // own contribution regardless of what the fillers add.
        let filler1 = await repo.createCard(front: "\u{751F}", back: "life", type: .kanji)
        let filler2 = await repo.createCard(front: "\u{5B66}", back: "study", type: .kanji)

        let planner = MockSessionPlanner()
        planner.plan = SessionPlan(
            exercises: [.srsReview(newKana), .srsReview(filler1), .srsReview(filler2)],
            estimatedDurationMinutes: 1,
            exerciseBreakdown: [.reading: 3]
        )
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()

        // The FIRST occurrence of `a` is the ungraded intro.
        guard case .srsReview(let shown) = vm.currentExercise, shown.front == "え" else {
            Issue.record("Expected the intro slot for 'え' first")
            return
        }
        #expect(vm.isPresentingNewCard == true)

        await vm.completeNewCardPresentation()

        // No FSRS write, no correctness/graded-attempt/new-item bookkeeping —
        // but the step still counted toward reviewedCount/pacing.
        let cards = await repo.allCards()
        let aAfterIntro = try #require(cards.first { $0.front == "え" })
        #expect(aAfterIntro.fsrsState.reps == 0)
        #expect(vm.correctCount == 0)
        #expect(vm.gradedAttemptCount == 0)
        #expect(vm.newItemsLearned == 0)
        #expect(vm.reviewedCount == 1)
        #expect(vm.currentIndex == 1)

        // Walk forward to the delayed, graded occurrence of the SAME card.
        var guardCount = 0
        while vm.isPresentingNewCard == false, !vm.isSessionComplete, guardCount < 10 {
            if case .srsReview(let shown) = vm.currentExercise, shown.front == "え" {
                break
            }
            await vm.gradeAndAdvance(grade: .good)
            guardCount += 1
        }

        guard case .srsReview(let delayed) = vm.currentExercise, delayed.front == "え" else {
            Issue.record("Expected to reach the delayed test slot for 'え'")
            return
        }
        // By construction this occurrence is no longer the intro.
        #expect(vm.isPresentingNewCard == false)

        // Delta-based: the fillers walked past above are ALSO `reps == 0`
        // cards, so they contribute their own correctness/new-item signal.
        // Capturing the baseline right here isolates `a`'s own contribution.
        let correctBefore = vm.correctCount
        let gradedBefore = vm.gradedAttemptCount
        let newItemsBefore = vm.newItemsLearned

        await vm.gradeAndAdvance(grade: .good)

        // THIS is the card's real first FSRS grade.
        let aLogs = await repo.reviewLogs(for: delayed.id)
        #expect(aLogs.count == 1)
        #expect(vm.correctCount == correctBefore + 1)
        #expect(vm.gradedAttemptCount == gradedBefore + 1)
        #expect(vm.newItemsLearned == newItemsBefore + 1)
    }
}
