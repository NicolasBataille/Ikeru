import Testing
@testable import IkeruCore

@Suite("SessionEndPolicy.evaluate")
struct SessionEndPolicyTests {

    private let policy = SessionEndPolicy(durationBudgetMinutes: 15, queueLength: 10, graceWindowSeconds: 60)

    @Test("Continues when budget and queue both have headroom")
    func continueWithHeadroom() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 2, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .continueSession)
    }

    @Test("Completes after current when queue exhausts mid-exercise")
    func queueExhaustedMidExercise() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 10, activeItemInFlight: true)
        #expect(policy.evaluate(state: s) == .completeAfterCurrent)
    }

    @Test("Completes now when queue exhausts and no item in flight")
    func queueExhaustedIdle() {
        let s = SessionEndState(elapsedSeconds: 60, completedCount: 10, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }

    @Test("Completes after current when budget fires mid-exercise")
    func budgetFiresMidExercise() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 4, activeItemInFlight: true)
        #expect(policy.evaluate(state: s) == .completeAfterCurrent)
    }

    @Test("Completes now when budget fires and no item in flight")
    func budgetFiresIdle() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 4, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }

    @Test("Queue exhaustion beats budget when both fire simultaneously")
    func queueWinsTie() {
        let s = SessionEndState(elapsedSeconds: 15 * 60, completedCount: 10, activeItemInFlight: false)
        #expect(policy.evaluate(state: s) == .completeNow)
    }
}
