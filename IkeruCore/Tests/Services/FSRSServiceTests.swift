import Testing
import Foundation
@testable import IkeruCore

@Suite("FSRSService")
struct FSRSServiceTests {

    // MARK: - Default Weights

    @Test("Default weights array has 19 elements")
    func defaultWeightsCount() {
        #expect(FSRSService.defaultWeights.count == 19)
    }

    // MARK: - New Card Scheduling (reps == 0)

    @Test("New card with grade Again gets short initial stability")
    func newCardAgain() {
        let state = FSRSState()
        let result = FSRSService.schedule(state: state, grade: .again)
        #expect(result.stability > 0)
        #expect(result.difficulty > 0)
        #expect(result.reps == 1)
        #expect(result.lapses == 1)
        #expect(result.lastReview != nil)
    }

    @Test("New card with grade Hard gets moderate initial stability")
    func newCardHard() {
        let state = FSRSState()
        let result = FSRSService.schedule(state: state, grade: .hard)
        #expect(result.stability > 0)
        #expect(result.difficulty > 0)
        #expect(result.reps == 1)
        #expect(result.lapses == 0)
        #expect(result.lastReview != nil)
    }

    @Test("New card with grade Good gets standard initial stability")
    func newCardGood() {
        let state = FSRSState()
        let result = FSRSService.schedule(state: state, grade: .good)
        #expect(result.stability > 0)
        #expect(result.difficulty > 0)
        #expect(result.reps == 1)
        #expect(result.lapses == 0)
        #expect(result.lastReview != nil)
    }

    @Test("New card with grade Easy gets longest initial stability")
    func newCardEasy() {
        let state = FSRSState()
        let result = FSRSService.schedule(state: state, grade: .easy)
        #expect(result.stability > 0)
        #expect(result.difficulty > 0)
        #expect(result.reps == 1)
        #expect(result.lapses == 0)
        #expect(result.lastReview != nil)
    }

    @Test("New card: Easy stability > Good stability > Hard stability > Again stability")
    func newCardStabilityOrdering() {
        let state = FSRSState()
        let again = FSRSService.schedule(state: state, grade: .again)
        let hard = FSRSService.schedule(state: state, grade: .hard)
        let good = FSRSService.schedule(state: state, grade: .good)
        let easy = FSRSService.schedule(state: state, grade: .easy)
        #expect(easy.stability > good.stability)
        #expect(good.stability > hard.stability)
        #expect(hard.stability > again.stability)
    }

    @Test("New card: Easy difficulty < Good difficulty < Hard difficulty < Again difficulty")
    func newCardDifficultyOrdering() {
        let state = FSRSState()
        let again = FSRSService.schedule(state: state, grade: .again)
        let hard = FSRSService.schedule(state: state, grade: .hard)
        let good = FSRSService.schedule(state: state, grade: .good)
        let easy = FSRSService.schedule(state: state, grade: .easy)
        #expect(easy.difficulty < good.difficulty)
        #expect(good.difficulty < hard.difficulty)
        #expect(hard.difficulty < again.difficulty)
    }

    // MARK: - Review Card Scheduling (reps > 0)

    @Test("Review card with grade Good increases stability")
    func reviewGoodIncreasesStability() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400) // 10 days ago
        )
        let result = FSRSService.schedule(state: state, grade: .good, now: now)
        #expect(result.stability > state.stability)
        #expect(result.reps == 4)
        #expect(result.lapses == 0)
    }

    @Test("Review card with grade Again decreases stability and increments lapses")
    func reviewAgainDecreasesStability() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let result = FSRSService.schedule(state: state, grade: .again, now: now)
        #expect(result.stability < state.stability)
        #expect(result.reps == 4)
        #expect(result.lapses == 1)
    }

    @Test("Review card with grade Easy has highest stability increase")
    func reviewEasyHighestStability() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let good = FSRSService.schedule(state: state, grade: .good, now: now)
        let easy = FSRSService.schedule(state: state, grade: .easy, now: now)
        #expect(easy.stability > good.stability)
    }

    // MARK: - Difficulty Bounds

    @Test("Difficulty stays within 1-10 range")
    func difficultyBounds() {
        // After many "again" grades, difficulty should not exceed 10
        var state = FSRSState()
        for _ in 0..<20 {
            state = FSRSService.schedule(state: state, grade: .again)
        }
        #expect(state.difficulty <= 10.0)
        #expect(state.difficulty >= 1.0)

        // After many "easy" grades, difficulty should not go below 1
        state = FSRSState()
        for _ in 0..<20 {
            state = FSRSService.schedule(state: state, grade: .easy)
        }
        #expect(state.difficulty >= 1.0)
        #expect(state.difficulty <= 10.0)
    }

    // MARK: - Due Date Calculation

    @Test("Due date is computed from stability for new card")
    func newCardDueDate() {
        let now = Date()
        let state = FSRSState()
        let result = FSRSService.schedule(state: state, grade: .good, now: now)
        let dueDate = FSRSService.dueDate(for: result, desiredRetention: 0.9, now: now)
        #expect(dueDate > now)
    }

    @Test("Due date for easy review is further than good review")
    func dueDateOrdering() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let good = FSRSService.schedule(state: state, grade: .good, now: now)
        let easy = FSRSService.schedule(state: state, grade: .easy, now: now)
        let goodDue = FSRSService.dueDate(for: good, desiredRetention: 0.9, now: now)
        let easyDue = FSRSService.dueDate(for: easy, desiredRetention: 0.9, now: now)
        #expect(easyDue > goodDue)
    }

    @Test("Due date respects maximum interval of 36500 days")
    func maxInterval() {
        let now = Date()
        let state = FSRSState(
            difficulty: 1.0,
            stability: 100_000,
            reps: 100,
            lapses: 0,
            lastReview: now
        )
        let dueDate = FSRSService.dueDate(for: state, desiredRetention: 0.9, now: now)
        let maxDate = now.addingTimeInterval(36500 * 86400)
        #expect(dueDate <= maxDate)
    }

    // MARK: - Retrievability

    @Test("Retrievability is 1.0 at review time")
    func retrievabilityAtReview() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now
        )
        let r = FSRSService.retrievability(for: state, now: now)
        #expect(r > 0.99)
    }

    @Test("Retrievability decreases over time")
    func retrievabilityDecay() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-5 * 86400)
        )
        let r = FSRSService.retrievability(for: state, now: now)
        #expect(r < 1.0)
        #expect(r > 0.0)
    }

    @Test("Retrievability is approximately 0.9 after stability days")
    func retrievabilityAtStability() {
        let now = Date()
        let stability = 10.0
        let state = FSRSState(
            difficulty: 5.0,
            stability: stability,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-stability * 86400)
        )
        let r = FSRSService.retrievability(for: state, now: now)
        // Should be approximately 0.9 at t = S
        #expect(r > 0.85)
        #expect(r < 0.95)
    }

    // MARK: - Pure Function Guarantee

    @Test("Schedule is a pure function - same inputs produce same outputs")
    func pureFunction() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let result1 = FSRSService.schedule(state: state, grade: .good, now: now)
        let result2 = FSRSService.schedule(state: state, grade: .good, now: now)
        #expect(result1 == result2)
    }

    @Test("Schedule does not mutate input state")
    func noMutation() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let stateCopy = state
        _ = FSRSService.schedule(state: state, grade: .good, now: now)
        #expect(state == stateCopy)
    }

    // MARK: - Performance

    @Test("Schedule 1000 cards in under 1 second")
    func performanceBenchmark() {
        let now = Date()
        var states: [FSRSState] = []
        states.reserveCapacity(1000)
        for i in 0..<1000 {
            let difficulty = Double(i % 10) + 1
            let stability = Double(i % 100) + 1
            let reps = i % 20
            let lapses = i % 5
            let lastReview = now.addingTimeInterval(-Double(i % 30) * 86400)
            let state = FSRSState(
                difficulty: difficulty,
                stability: stability,
                reps: reps,
                lapses: lapses,
                lastReview: lastReview
            )
            states.append(state)
        }
        let grades: [Grade] = [.again, .hard, .good, .easy]
        let start = ContinuousClock.now
        for (index, state) in states.enumerated() {
            _ = FSRSService.schedule(state: state, grade: grades[index % 4], now: now)
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(1))
    }
}
