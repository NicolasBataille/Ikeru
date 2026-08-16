import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("Immersive Session Mode")
@MainActor
struct ImmersiveSessionViewTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Drop any active-profile id left in UserDefaults by an earlier test;
        // the resolver persists it there, and it crosses test boundaries.
        ActiveProfileResolver.setActiveProfileID(nil)
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

    /// Resolves (creating if needed) the active profile, and marks it active.
    ///
    /// Cards MUST be attached to it: `CardRepository` scopes every query to
    /// `profile.cards` (see `CardModelActor.activeProfileCards`), so a card
    /// inserted with `profile == nil` is invisible to the planner and the
    /// session composes to nothing. These suites predate per-profile scoping
    /// and were never updated, because a crashing runner meant they never ran
    /// — every "session never starts" failure here traced back to this.
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

    private func seedDueCards(container: ModelContainer, count: Int) throws -> [UUID] {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        var ids: [UUID] = []
        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                // `reps: 1` is what makes these REVIEWS. The planner's
                // `pickReviews` filters on `dueDate <= now && reps > 0`; a
                // never-reviewed card is NEW content, which is deliberately
                // dripped roughly one per session. Seeded with the default
                // `reps == 0`, this helper produced new cards while its name
                // and every assertion said "due reviews", so a 3-card seed
                // composed a 1-item session. The product was right; the
                // fixture was lying.
                fsrsState: FSRSState(difficulty: 5.0, stability: 5.0, reps: 1, lapses: 0,
                                     lastReview: Date().addingTimeInterval(-86_400)),
                dueDate: Date().addingTimeInterval(-3600)
            )
            card.profile = profile
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    // MARK: - Timer Tests

    @Test("Timer starts when session starts")
    func timerStartsWithSession() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.isTimerRunning == true)
        #expect(vm.elapsedTime == 0)
    }

    @Test("Timer pauses when session is paused")
    func timerPausesWithSession() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.pauseSession()

        #expect(vm.isTimerRunning == false)
        #expect(vm.isPaused == true)
    }

    @Test("Timer resumes when session resumes")
    func timerResumesWithSession() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.pauseSession()
        vm.resumeSession()

        #expect(vm.isTimerRunning == true)
        #expect(vm.isPaused == false)
    }

    @Test("Timer stops when session ends")
    func timerStopsOnEnd() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.endSession()

        #expect(vm.isTimerRunning == false)
    }

    @Test("Timer stops when session is dismissed")
    func timerStopsOnDismiss() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.dismissSession()

        #expect(vm.isTimerRunning == false)
    }

    @Test("Elapsed time formatted correctly")
    func elapsedTimeFormatted() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 1)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        // elapsedTime is 0 at start
        #expect(vm.elapsedTimeFormatted == "0:00")
    }

    // MARK: - Exercise Navigation Tests

    @Test("Session exercises populated on start")
    func sessionExercisesPopulated() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.sessionExercises.count == 3)
        #expect(vm.currentExerciseIndex == 0)
        #expect(vm.currentExercise != nil)
    }

    @Test("Exercise index advances after grading")
    func exerciseIndexAdvancesAfterGrade() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        #expect(vm.currentExerciseIndex == 0)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.currentExerciseIndex == 1)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.currentExerciseIndex == 2)
    }

    @Test("Current exercise is nil when all completed")
    func currentExerciseNilWhenComplete() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 2)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        #expect(vm.currentExercise == nil)
        #expect(vm.isSessionComplete == true)
    }

    @Test("Empty session shows no exercises")
    func emptySessionHasNoExercises() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.sessionExercises.isEmpty)
        #expect(vm.currentExercise == nil)
    }

    // MARK: - Estimated Time Tests

    @Test("Estimated total time computed from exercises")
    func estimatedTotalTimeComputed() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

        await vm.startSession()

        // Each SRS review is 15 seconds
        #expect(vm.estimatedTotalTime == 60)
    }

    @Test("Estimated remaining time decreases with elapsed time")
    func estimatedRemainingTimeDecreases() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

        await vm.startSession()

        // At start, remaining == total
        #expect(vm.estimatedRemainingTime == vm.estimatedTotalTime)
    }

    @Test("Estimated remaining time formatted with dash prefix")
    func estimatedRemainingTimeFormatted() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 4)
        let vm = makeViewModel(container: container)

        await vm.startSession()

        #expect(vm.estimatedRemainingTimeFormatted == "-1:00")
    }

    // MARK: - Pause State Tests

    @Test("Swipe-down pause toggles pause state")
    func swipeDownPauseToggle() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        #expect(vm.isPaused == false)

        vm.pauseSession()
        #expect(vm.isPaused == true)
        #expect(vm.isTimerRunning == false)

        vm.resumeSession()
        #expect(vm.isPaused == false)
        #expect(vm.isTimerRunning == true)
    }

    @Test("Pause preserves exercise index and reviewed count")
    func pausePreservesState() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .easy)

        let indexBefore = vm.currentExerciseIndex
        let reviewedBefore = vm.reviewedCount
        let xpBefore = vm.xpEarned

        vm.pauseSession()
        vm.resumeSession()

        #expect(vm.currentExerciseIndex == indexBefore)
        #expect(vm.reviewedCount == reviewedBefore)
        #expect(vm.xpEarned == xpBefore)
    }

    // MARK: - Abandon Confirmation Tests

    @Test("Request abandon shows confirmation")
    func requestAbandonShowsConfirmation() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.requestAbandon()

        #expect(vm.showAbandonConfirmation == true)
    }

    @Test("Cancel abandon dismisses confirmation")
    func cancelAbandonDismissesConfirmation() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        vm.requestAbandon()
        vm.cancelAbandon()

        #expect(vm.showAbandonConfirmation == false)
    }

    @Test("Abandon preserves completed exercise progress")
    func abandonPreservesProgress() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)  // +10 XP
        await vm.gradeAndAdvance(grade: .good)  // +10 XP
        await vm.gradeAndAdvance(grade: .hard)  // +5 XP

        let xpBeforeAbandon = vm.xpEarned
        let reviewedBeforeAbandon = vm.reviewedCount

        await vm.endSession()

        #expect(vm.xpEarned == xpBeforeAbandon)
        #expect(vm.reviewedCount == reviewedBeforeAbandon)
        #expect(vm.isSessionComplete == true)
    }

    @Test("Abandon progress description is accurate")
    func abandonProgressDescription() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 8)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)
        await vm.gradeAndAdvance(grade: .good)

        // Locale-independent: this string is localized, and the test host
        // runs in whatever language the simulator is set to (French here, so
        // the hardcoded English sentence failed). Assert the two numbers the
        // description exists to convey, not the sentence around them.
        #expect(vm.abandonProgressDescription.contains("3"))
        #expect(vm.abandonProgressDescription.contains("8"))
    }

    // MARK: - Skill Type Icon Tests

    @Test("All four skill types have correct icons")
    func skillTypeIcons() {
        #expect(sfSymbol(for: .reading) == "book.fill")
        #expect(sfSymbol(for: .writing) == "pencil.line")
        #expect(sfSymbol(for: .listening) == "ear.fill")
        #expect(sfSymbol(for: .speaking) == "mouth.fill")
    }

    @Test("Exercise items report correct skill types")
    func exerciseItemSkillTypes() {
        let card = CardDTO(
            id: UUID(),
            front: "test",
            back: "test",
            type: .kanji,
            fsrsState: FSRSState(),
            easeFactor: 2.5,
            interval: 0,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false
        )

        #expect(ExerciseItem.srsReview(card).skill == .reading)
        #expect(ExerciseItem.kanjiStudy(card).skill == .reading)
        #expect(ExerciseItem.grammarExercise(UUID()).skill == .reading)
        #expect(ExerciseItem.writingPractice(card).skill == .writing)
        #expect(ExerciseItem.listeningExercise(UUID()).skill == .listening)
        #expect(ExerciseItem.speakingExercise(UUID()).skill == .speaking)
    }

    // MARK: - Integration Test: Full Session Flow

    @Test("Full session flow from start through all exercises to summary")
    func fullSessionFlow() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        // Start session
        await vm.startSession()
        #expect(vm.isActive == true)
        #expect(vm.sessionExercises.count == 3)
        #expect(vm.currentExerciseIndex == 0)
        #expect(vm.isTimerRunning == true)

        // Grade first exercise
        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.reviewedCount == 1)
        // Not a magic 10. XP per grade was deliberately flattened (see
        // `RPGConstants.xpForGrade`'s doc comment: reward showing up, not
        // self-rated accuracy), so the old hardcoded 10 predates the current
        // economy. Assert the property that matters here — grading an
        // exercise earns XP — and leave the exact per-grade number to
        // `RPGConstants`' own tests, where changing the economy should
        // require changing exactly one expectation.
        #expect(vm.xpEarned > 0)

        // Pause mid-session
        vm.pauseSession()
        #expect(vm.isPaused == true)
        #expect(vm.isTimerRunning == false)

        // Resume
        vm.resumeSession()
        #expect(vm.isPaused == false)
        #expect(vm.isTimerRunning == true)

        // Grade remaining exercises
        await vm.gradeAndAdvance(grade: .easy)
        #expect(vm.currentExerciseIndex == 2)

        await vm.gradeAndAdvance(grade: .hard)
        #expect(vm.isSessionComplete == true)
        #expect(vm.currentExercise == nil)
        #expect(vm.reviewedCount == 3)
        #expect(vm.isTimerRunning == false)

        // Dismiss
        vm.dismissSession()
        #expect(vm.isActive == false)
        #expect(vm.sessionExercises.isEmpty)
    }

    @Test("Abandon mid-session preserves XP from completed exercises")
    func abandonMidSessionPreservesXP() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 5)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        await vm.gradeAndAdvance(grade: .good)   // +10
        await vm.gradeAndAdvance(grade: .easy)    // +10

        // Abandon after 2 of 5 exercises
        vm.pauseSession()
        await vm.endSession()

        #expect(vm.reviewedCount == 2)
        let xpAfterTwo = vm.xpEarned
        #expect(xpAfterTwo > 0)
        #expect(vm.isSessionComplete == true)

        // Verify RPG state was persisted
        let descriptor = FetchDescriptor<RPGState>()
        let states = try container.mainContext.fetch(descriptor)
        // The point of this assertion is that the session's XP reached
        // SwiftData intact — not what the economy pays per grade.
        #expect(states.first?.xp == xpAfterTwo)
    }

    @Test("Exercise transition trigger increments on advance")
    func exerciseTransitionTriggerIncrements() async throws {
        let container = try makeContainer()
        _ = try seedDueCards(container: container, count: 3)
        let vm = makeViewModel(container: container)

        await vm.startSession()
        let initialTrigger = vm.exerciseTransitionTrigger

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.exerciseTransitionTrigger == initialTrigger + 1)

        await vm.gradeAndAdvance(grade: .good)
        #expect(vm.exerciseTransitionTrigger == initialTrigger + 2)
    }
}
