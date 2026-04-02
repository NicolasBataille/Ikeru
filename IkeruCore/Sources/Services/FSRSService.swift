import Foundation

/// Pure-function FSRS-5 scheduling service.
/// Computes next review state based on the DSR (Difficulty, Stability, Retrievability) model.
///
/// All functions are static and pure — no side effects, no database access.
/// Takes FSRSState + Grade, returns a new FSRSState.
///
/// Reference: https://github.com/open-spaced-repetition/fsrs-rs
public enum FSRSService {

    // MARK: - Default FSRS-5 Weights

    /// Default FSRS-5 optimized weights (w[0]..w[18]).
    /// These are the pretrained defaults from the FSRS-5 paper.
    public static let defaultWeights: [Double] = [
        0.4072,  // w[0]:  initial stability for Again
        1.1829,  // w[1]:  initial stability for Hard
        3.1262,  // w[2]:  initial stability for Good
        15.4722, // w[3]:  initial stability for Easy
        7.2102,  // w[4]:  initial difficulty for Good
        0.5316,  // w[5]:  difficulty grade multiplier
        1.0651,  // w[6]:  difficulty reversion weight (unused in simplified)
        0.0589,  // w[7]:  difficulty mean reversion rate
        1.5747,  // w[8]:  stability success factor
        0.1070,  // w[9]:  stability power decay
        1.0070,  // w[10]: stability retrievability factor
        2.0966,  // w[11]: stability failure factor
        0.0340,  // w[12]: failure difficulty power
        0.3642,  // w[13]: failure stability power
        1.5489,  // w[14]: failure retrievability factor
        0.2060,  // w[15]: hard penalty
        2.9466,  // w[16]: easy bonus
        0.2939,  // w[17]: short-term stability factor
        0.4535,  // w[18]: short-term stability power
    ]

    /// Maximum interval in days (100 years)
    public static let maximumInterval: Double = 36500

    // MARK: - Core Scheduling

    /// Schedule a card review, returning an updated FSRSState.
    ///
    /// This is a pure function — no side effects, no database access.
    /// - Parameters:
    ///   - state: The current FSRS state of the card
    ///   - grade: The grade given by the learner
    ///   - now: The current timestamp (defaults to now, injectable for testing)
    ///   - weights: FSRS weights to use (defaults to FSRS-5 pretrained)
    /// - Returns: A new FSRSState with updated scheduling parameters
    public static func schedule(
        state: FSRSState,
        grade: Grade,
        now: Date = Date(),
        weights: [Double] = defaultWeights
    ) -> FSRSState {
        if state.reps == 0 {
            return scheduleNewCard(grade: grade, now: now, weights: weights)
        } else {
            return scheduleReviewCard(
                state: state,
                grade: grade,
                now: now,
                weights: weights
            )
        }
    }

    /// Compute the due date for a given FSRSState, based on desired retention.
    ///
    /// - Parameters:
    ///   - state: The FSRS state of the card
    ///   - desiredRetention: Target retention rate (0.0–1.0), default 0.9
    ///   - now: Current timestamp
    ///   - maxInterval: Maximum interval in days
    /// - Returns: The next due date
    public static func dueDate(
        for state: FSRSState,
        desiredRetention: Double = 0.9,
        now: Date = Date(),
        maxInterval: Double = maximumInterval
    ) -> Date {
        let interval = nextInterval(stability: state.stability, desiredRetention: desiredRetention)
        let clampedInterval = min(interval, maxInterval)
        let intervalSeconds = clampedInterval * 86400
        return now.addingTimeInterval(intervalSeconds)
    }

    /// Compute the current retrievability of a card.
    ///
    /// R(t) = (1 + t / (9 * S)) ^ (-1)
    ///
    /// - Parameters:
    ///   - state: The FSRS state of the card
    ///   - now: Current timestamp
    /// - Returns: Retrievability value between 0.0 and 1.0
    public static func retrievability(
        for state: FSRSState,
        now: Date = Date()
    ) -> Double {
        guard let lastReview = state.lastReview, state.stability > 0 else {
            return 0
        }
        let elapsedDays = now.timeIntervalSince(lastReview) / 86400
        if elapsedDays <= 0 {
            return 1.0
        }
        return powerForgetCurve(elapsedDays: elapsedDays, stability: state.stability)
    }

    // MARK: - Private Helpers

    /// Schedule a brand new card (first review, reps == 0).
    private static func scheduleNewCard(
        grade: Grade,
        now: Date,
        weights: [Double]
    ) -> FSRSState {
        let initialStability = initialStability(grade: grade, weights: weights)
        let initialDifficulty = initialDifficulty(grade: grade, weights: weights)
        let isLapse = grade == .again

        return FSRSState(
            difficulty: clampDifficulty(initialDifficulty),
            stability: initialStability,
            reps: 1,
            lapses: isLapse ? 1 : 0,
            lastReview: now
        )
    }

    /// Schedule a review for an existing card (reps > 0).
    private static func scheduleReviewCard(
        state: FSRSState,
        grade: Grade,
        now: Date,
        weights: [Double]
    ) -> FSRSState {
        let elapsedDays: Double
        if let lastReview = state.lastReview {
            elapsedDays = max(0, now.timeIntervalSince(lastReview) / 86400)
        } else {
            elapsedDays = 0
        }

        let r = powerForgetCurve(elapsedDays: elapsedDays, stability: state.stability)
        let newDifficulty = nextDifficulty(
            currentDifficulty: state.difficulty,
            grade: grade,
            weights: weights
        )

        let newStability: Double
        let isLapse = grade == .again

        if isLapse {
            newStability = stabilityAfterFailure(
                difficulty: newDifficulty,
                stability: state.stability,
                retrievability: r,
                weights: weights
            )
        } else {
            newStability = stabilityAfterSuccess(
                difficulty: newDifficulty,
                stability: state.stability,
                retrievability: r,
                grade: grade,
                weights: weights
            )
        }

        return FSRSState(
            difficulty: clampDifficulty(newDifficulty),
            stability: max(0.01, newStability),
            reps: state.reps + 1,
            lapses: state.lapses + (isLapse ? 1 : 0),
            lastReview: now
        )
    }

    /// Power forgetting curve: R(t) = (1 + t / (9 * S)) ^ (-1)
    private static func powerForgetCurve(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + elapsedDays / (9 * stability), -1)
    }

    /// Initial stability for a new card based on grade.
    /// S_0(G) = w[G-1]
    private static func initialStability(grade: Grade, weights: [Double]) -> Double {
        weights[grade.rawValue - 1]
    }

    /// Initial difficulty for a new card based on grade.
    /// D_0(G) = w[4] - exp(w[5] * (G - 1)) + 1
    private static func initialDifficulty(grade: Grade, weights: [Double]) -> Double {
        let g = Double(grade.rawValue)
        return weights[4] - exp(weights[5] * (g - 1)) + 1
    }

    /// Next difficulty after a review.
    /// D' = w[7] * D_0(G) + (1 - w[7]) * D_prev
    private static func nextDifficulty(
        currentDifficulty: Double,
        grade: Grade,
        weights: [Double]
    ) -> Double {
        let d0 = initialDifficulty(grade: grade, weights: weights)
        return weights[7] * d0 + (1 - weights[7]) * currentDifficulty
    }

    /// Stability after a successful review (grade >= Hard).
    /// S' = S * (e^(w[8]) * (11-D) * S^(-w[9]) * (e^(w[10]*(1-R))-1) * hardPenalty/easyBonus + 1)
    private static func stabilityAfterSuccess(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        grade: Grade,
        weights: [Double]
    ) -> Double {
        let innerExp = exp(weights[8])
        let difficultyFactor = 11 - difficulty
        let stabilityDecay = pow(stability, -weights[9])
        let retrievabilityFactor = exp(weights[10] * (1 - retrievability)) - 1

        let gradeModifier: Double
        switch grade {
        case .hard:
            gradeModifier = weights[15]
        case .easy:
            gradeModifier = weights[16]
        case .good, .again:
            gradeModifier = 1.0
        }

        let growth = innerExp * difficultyFactor * stabilityDecay * retrievabilityFactor * gradeModifier

        return stability * (growth + 1)
    }

    /// Stability after a failed review (grade == Again).
    /// S' = w[11] * D^(-w[12]) * ((S+1)^w[13] - 1) * e^(w[14]*(1-R))
    private static func stabilityAfterFailure(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        weights: [Double]
    ) -> Double {
        let difficultyFactor = pow(difficulty, -weights[12])
        let stabilityFactor = pow(stability + 1, weights[13]) - 1
        let retrievabilityFactor = exp(weights[14] * (1 - retrievability))

        return weights[11] * difficultyFactor * stabilityFactor * retrievabilityFactor
    }

    /// Compute the next interval in days from stability and desired retention.
    /// interval = S / factor * ((1/R) - 1)
    /// Since R(t) = (1 + t/(9*S))^(-1), solving for t when R = desiredRetention:
    /// t = 9 * S * (R^(-1) - 1) ... but actually we solve: R = (1 + t/(9S))^(-1)
    /// => 1/R = 1 + t/(9S) => t = 9S * (1/R - 1)
    private static func nextInterval(stability: Double, desiredRetention: Double) -> Double {
        guard desiredRetention > 0, desiredRetention < 1, stability > 0 else {
            return 1
        }
        let interval = 9 * stability * (1 / desiredRetention - 1)
        return max(1, interval)
    }

    /// Clamp difficulty to [1, 10] range.
    private static func clampDifficulty(_ difficulty: Double) -> Double {
        min(10, max(1, difficulty))
    }
}
