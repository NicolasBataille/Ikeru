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

    // MARK: - FSRS-5 Forgetting Curve (golden values)

    @Test("FSRS-5 retrievability golden value at t=5, S=10")
    func fsrs5RetrievabilityGoldenValue() {
        // R(t) = (1 + FACTOR*t/S)^DECAY, FACTOR = 19/81, DECAY = -0.5.
        // R(5,10) = (1 + (19/81)*5/10)^-0.5
        //         = (1 + 0.11728395...)^-0.5
        //         = (1.11728395...)^-0.5
        //         ≈ 0.946058996209746   (computed with Python: (1+19/81*0.5)**-0.5)
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-5 * 86400)
        )
        let r = FSRSService.retrievability(for: state, now: now)
        #expect(abs(r - 0.946058996209746) < 0.0001)
    }

    @Test("FSRS-5 retrievability at t=S is exactly 0.9 for any stability")
    func fsrs5RetrievabilityAtStabilityIsExactlyNinety() {
        // By construction FACTOR = 19/81 makes R(S) = (1+FACTOR)^-0.5
        // = (100/81)^-0.5 = (81/100)^0.5 = 0.9 for ANY stability S — this is
        // what makes "S = the 90%-retention interval" hold under FSRS-5.
        let now = Date()
        for stability in [1.0, 5.0, 10.0, 50.0, 200.0] {
            let state = FSRSState(
                difficulty: 5.0,
                stability: stability,
                reps: 3,
                lapses: 0,
                lastReview: now.addingTimeInterval(-stability * 86400)
            )
            let r = FSRSService.retrievability(for: state, now: now)
            #expect(abs(r - 0.9) < 0.0001)
        }
    }

    // MARK: - Continuity at desiredRetention = 0.9

    @Test("Interval at desiredRetention 0.9 is continuous with the old FSRS-4 form across a stability sweep")
    func continuityAtNinetyPercentRetention() {
        // Both the old FSRS-4 form (t = 9*S*(1/R - 1)) and the new FSRS-5
        // form (t = (S/FACTOR)*(R^-2 - 1)) are defined so that S is exactly
        // the 90%-retention interval — so at R=0.9 they must agree (up to
        // floating-point noise) for any stability. This guards against a
        // curve swap silently shifting every existing card's due date.
        let now = Date()
        let factor = 19.0 / 81.0
        for stability in [0.5, 1.0, 5.0, 10.0, 50.0, 100.0, 500.0, 5000.0] {
            let state = FSRSState(
                difficulty: 5.0,
                stability: stability,
                reps: 3,
                lapses: 0,
                lastReview: now
            )
            let newDue = FSRSService.dueDate(for: state, desiredRetention: 0.9, now: now)
            let newInterval = newDue.timeIntervalSince(now) / 86400

            // Old FSRS-4 form, recomputed independently here (not calling
            // into FSRSService, which no longer exposes it). Both curves
            // are compared post-clamp: `nextInterval` floors at 1 day in
            // production, and at very low stability (e.g. 0.5) the
            // *unclamped* old/new values legitimately diverge from each
            // other while both floor to the same 1-day result — so the
            // clamp must be mirrored here for a fair comparison.
            let oldInterval = max(1, 9 * stability * (1 / 0.9 - 1))

            _ = factor // documents which constant defines the new curve
            #expect(abs(newInterval - oldInterval) < 0.001)
        }
    }

    // MARK: - Retention Monotonicity

    @Test("Higher desiredRetention yields a shorter interval for the same stability")
    func retentionMonotonicity() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 20.0,
            reps: 3,
            lapses: 0,
            lastReview: now
        )
        let low = FSRSService.dueDate(for: state, desiredRetention: 0.8, now: now)
        let mid = FSRSService.dueDate(for: state, desiredRetention: 0.9, now: now)
        let high = FSRSService.dueDate(for: state, desiredRetention: 0.95, now: now)
        #expect(low > mid)
        #expect(mid > high)
    }

    // MARK: - w[6]/w[7] Difficulty Update (golden values)

    @Test("Difficulty update golden values for D=5 across all grades")
    func difficultyUpdateGoldenValues() {
        // nextDifficulty(D=5, G):
        //   deltaD = -w[6]*(G-3)
        //   damped = D + deltaD*(10-D)/9
        //   D' = w[7]*D0(Easy) + (1-w[7])*damped, D0(Easy) = w[4]-exp(w[5]*3)+1 ≈ 3.282856
        // Computed with Python using defaultWeights:
        //   again(1): ≈ 6.012600   hard(2): ≈ 5.455730
        //   good(3):  ≈ 4.898860   easy(4): ≈ 4.341990
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-10 * 86400)
        )
        let again = FSRSService.schedule(state: state, grade: .again, now: now)
        let hard = FSRSService.schedule(state: state, grade: .hard, now: now)
        let good = FSRSService.schedule(state: state, grade: .good, now: now)
        let easy = FSRSService.schedule(state: state, grade: .easy, now: now)

        #expect(abs(again.difficulty - 6.012600) < 0.001)
        #expect(abs(hard.difficulty - 5.455730) < 0.001)
        #expect(abs(good.difficulty - 4.898860) < 0.001)
        #expect(abs(easy.difficulty - 4.341990) < 0.001)
    }

    // MARK: - Short-Term (Same-Day) Stability

    @Test("Same-day re-grade uses the short-term stability formula (golden values)")
    func shortTermStabilityGoldenValues() {
        // S' = S * e^(w[17]*(G-3+w[18])), S=10, w[17]=0.2939, w[18]=0.4535:
        //   again(1): 10*e^(0.2939*(1-3+0.4535)) = 10*e^(-0.454919) ≈ 6.347549
        //   hard(2):  10*e^(0.2939*(2-3+0.4535)) = 10*e^(-0.160616) ≈ 8.516187
        //   good(3):  10*e^(0.2939*(3-3+0.4535)) = 10*e^(0.133304)  ≈ 11.425740
        //   easy(4):  10*e^(0.2939*(4-3+0.4535)) = 10*e^(0.427224)  ≈ 15.329342
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-3600) // 1 hour ago — same day
        )
        let again = FSRSService.schedule(state: state, grade: .again, now: now)
        let hard = FSRSService.schedule(state: state, grade: .hard, now: now)
        let good = FSRSService.schedule(state: state, grade: .good, now: now)
        let easy = FSRSService.schedule(state: state, grade: .easy, now: now)

        #expect(abs(again.stability - 6.347549) < 0.001)
        #expect(abs(hard.stability - 8.516187) < 0.001)
        #expect(abs(good.stability - 11.425740) < 0.001)
        #expect(abs(easy.stability - 15.329342) < 0.001)
    }

    @Test("Same-day re-grade stability is monotonic: easy > good > hard > again")
    func shortTermStabilityMonotonicity() {
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-60) // 1 minute ago — same day
        )
        let again = FSRSService.schedule(state: state, grade: .again, now: now)
        let hard = FSRSService.schedule(state: state, grade: .hard, now: now)
        let good = FSRSService.schedule(state: state, grade: .good, now: now)
        let easy = FSRSService.schedule(state: state, grade: .easy, now: now)

        #expect(easy.stability > good.stability)
        #expect(good.stability > hard.stability)
        #expect(hard.stability > again.stability)
    }

    @Test("A review at 1.5 days elapsed uses the regular DSR update, not short-term")
    func regularUpdateBeyondOneDay() {
        // At elapsedDays >= 1 the short-term branch must NOT fire — sanity
        // check that the regular Again failure formula (which can shrink
        // stability well below the short-term result) is what runs here.
        // Using 1.5 days (not exactly 1.0) avoids floating-point flakiness
        // right at the branch boundary.
        let now = Date()
        let state = FSRSState(
            difficulty: 5.0,
            stability: 10.0,
            reps: 3,
            lapses: 0,
            lastReview: now.addingTimeInterval(-1.5 * 86400)
        )
        let result = FSRSService.schedule(state: state, grade: .again, now: now)
        // Short-term formula would give 10*e^(w17*(1-3+w18)) ≈ 6.347549;
        // the regular failure formula at r=R(1.5,10) gives a markedly
        // different (lower) value — assert they diverge from the
        // short-term golden value to prove the correct branch ran.
        #expect(abs(result.stability - 6.347549) > 0.5)
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
