import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

/// Phase 4.1 Steps 3+4 coverage for the LIVE Tier-1 drill path.
///
/// Focus: the `.kanjiStudy` completion path in `SessionViewModel`
/// (`completeCurrentExercise`) must now run the SAME card-grade bookkeeping the
/// SRS deck runs (`applyCardGradeSideEffects`) — a real FSRS write, first-review
/// counting, and leech detection — while `.writingPractice` stays XP-only.
/// The mocked-planner injection mirrors `SessionDecouplingTests`.
@Suite("Tier-1 kanjiStudy bookkeeping (4.1)")
@MainActor
struct Tier1KanjiStudyBookkeepingTests {

    // MARK: - Helpers (mirrors SessionDecouplingTests' seam)

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

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

    /// Seeds one `.kanji` card per front string (all overdue, brand-new so
    /// `reps == 0`), attached to the active profile.
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

    private func buildPlan(_ exercises: [ExerciseItem]) -> SessionPlan {
        SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(1, exercises.count / 3),
            exerciseBreakdown: [.reading: exercises.count]
        )
    }

    private func dto(_ front: String, in dtos: [CardDTO]) throws -> CardDTO {
        try #require(dtos.first { $0.front == front })
    }

    /// A kanji `CardDTO` that becomes a leech on the next `.again`
    /// (`lapseCount + 1 == leechThreshold`). Built directly (not seeded) since
    /// leech detection reads the DTO, not the DB.
    private func leechEligibleKanji(front: String) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "leech",
            type: .kanji,
            fsrsState: FSRSState(difficulty: 7, stability: 2, reps: 4, lapses: 2, lastReview: nil),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(),
            lapseCount: CardRepository.leechThreshold - 1,
            leechFlag: false
        )
    }

    // MARK: - Tests

    @Test("kanjiStudy completion writes a real FSRS grade AND counts the first review")
    func kanjiStudyWritesGradeAndCountsNewItem() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        // K is the studied kanji; A is a trailing SRS card so the session starts
        // (startSession refuses an all-non-SRS plan).
        try seedCards(container: container, fronts: ["K", "A"])
        let dtos = await repo.allCards()
        let k = try dto("K", in: dtos)
        let a = try dto("A", in: dtos)
        // Precondition the bookkeeping depends on: K is brand-new.
        #expect(k.fsrsState.reps == 0)

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.kanjiStudy(k), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.currentExercise == .kanjiStudy(k))

        await vm.completeCurrentExercise(grade: .good)

        // 4.4 hook: a real ReviewLog was written for K.
        let kLogs = await repo.reviewLogs(for: k.id)
        #expect(kLogs.count == 1)
        // Card bookkeeping ran: first review counted.
        #expect(vm.newItemsLearned == 1)
        #expect(vm.reviewedCount == 1)
        // SRS queue pointer untouched; exercise pointer advanced.
        #expect(vm.currentIndex == 0)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.currentExercise == .srsReview(a))
    }

    @Test("kanjiStudy graded .again flags a leech-eligible card (bookkeeping parity)")
    func kanjiStudyDetectsLeech() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["A"])
        let dtos = await repo.allCards()
        let a = try dto("A", in: dtos)
        let leechKanji = leechEligibleKanji(front: "難")

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.kanjiStudy(leechKanji), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.currentExercise == .kanjiStudy(leechKanji))
        #expect(vm.lastLeechEvent == nil)

        await vm.completeCurrentExercise(grade: .again)

        // Leech detection ran on the kanjiStudy path exactly as it would on the deck.
        let leech = try #require(vm.lastLeechEvent)
        #expect(leech.lapseCount == CardRepository.leechThreshold)
        #expect(leech.isNewLeech == true)
        // A failed kanjiStudy must NOT move the SRS queue pointer.
        #expect(vm.currentIndex == 0)
        #expect(vm.currentExerciseIndex == 1)
    }

    @Test("writingPractice completion awards XP but writes NO FSRS grade")
    func writingPracticeIsXPOnly() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        try seedCards(container: container, fronts: ["W", "A"])
        let dtos = await repo.allCards()
        let w = try dto("W", in: dtos)
        let a = try dto("A", in: dtos)

        let planner = MockSessionPlanner()
        planner.plan = buildPlan([.writingPractice(w), .srsReview(a)])
        let vm = makeVM(container: container, planner: planner)

        await vm.startSession()
        #expect(vm.currentExercise == .writingPractice(w))

        await vm.completeCurrentExercise(grade: .good)

        // XP-only: no ReviewLog written for the practiced card…
        let wLogs = await repo.reviewLogs(for: w.id)
        #expect(wLogs.isEmpty)
        // …but XP was still awarded for the completion.
        #expect(vm.xpEarned > 0)
        // writingPractice is not a first-review of a graded card → not counted.
        #expect(vm.newItemsLearned == 0)
        #expect(vm.currentIndex == 0)
        #expect(vm.currentExerciseIndex == 1)
        #expect(vm.reviewedCount == 1)
    }
}

/// Unit tests for the pure drill result → `Grade` mapping (blueprint §3).
@Suite("DrillGradeMapping")
struct DrillGradeMappingTests {

    @Test("Handwriting: correct with very high confidence → .easy")
    func handwritingCorrectHighConfidence() {
        #expect(DrillGradeMapping.handwriting(feedback: .correct, topConfidence: 0.99) == .easy)
        #expect(DrillGradeMapping.handwriting(feedback: .correct, topConfidence: 0.95) == .easy)
    }

    @Test("Handwriting: correct with ordinary/unknown confidence → .good")
    func handwritingCorrectOrdinaryConfidence() {
        #expect(DrillGradeMapping.handwriting(feedback: .correct, topConfidence: 0.80) == .good)
        #expect(DrillGradeMapping.handwriting(feedback: .correct, topConfidence: nil) == .good)
    }

    @Test("Handwriting: partial → .hard, incorrect/idle → .again")
    func handwritingLowerTiers() {
        #expect(DrillGradeMapping.handwriting(feedback: .partial, topConfidence: 0.99) == .hard)
        #expect(DrillGradeMapping.handwriting(feedback: .incorrect, topConfidence: nil) == .again)
        #expect(DrillGradeMapping.handwriting(feedback: .idle, topConfidence: nil) == .again)
    }

    @Test("SentenceConstruction: correct → .good, incorrect → .again")
    func sentenceConstructionMapping() {
        #expect(DrillGradeMapping.sentenceConstruction(isCorrect: true) == .good)
        #expect(DrillGradeMapping.sentenceConstruction(isCorrect: false) == .again)
    }
}
