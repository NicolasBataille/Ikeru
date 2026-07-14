import Foundation

/// Pure-function spaced-repetition scheduler: FSRS-5, with one deliberate
/// product-level deviation from the reference algorithm.
///
/// All functions are static and pure — no side effects, no database access.
/// Takes FSRSState + Grade, returns a new FSRSState.
///
/// **Implemented (true FSRS-5):**
/// - **Forgetting curve** is the FSRS-5 form,
///   R(t) = (1 + FACTOR·t/S)^DECAY with DECAY = -0.5, FACTOR = 19/81
///   (`powerForgetCurve`), inverted for scheduling in `nextInterval`.
/// - **Difficulty update** applies the linearly-damped w[6] delta,
///   ΔD = -w[6]·(G-3), then mean-reverts toward D₀(Easy) with w[7]
///   (`nextDifficulty`), matching the fsrs-rs reference.
/// - **Short-term (same-day) stability**: when the elapsed time since the
///   last review is under 1 day, stability updates via
///   S' = S·e^(w[17]·(G-3+w[18])) instead of the regular DSR update
///   (difficulty still updates via the normal path either way).
/// - **desiredRetention is plumbed end-to-end**: `dueDate` takes it as a
///   parameter, and both production callers (`CardModelActor.gradeCard` and
///   `VocabularyModelActor.gradeEntry`) read it from the active profile's
///   `ProfileSettings.desiredRetention`, clamped to [0.8, 0.95].
///
/// **Deliberate product choice — NOT a gap:**
/// - **Intervals still clamp to >= 1 day** (`nextInterval` returns
///   `max(1, …)`), so the *due-date* scheduler never produces same-day
///   steps. This is intentional: same-day relearning of `.again` cards is
///   handled by the session layer (intra-session re-queue in
///   `SessionViewModel`), which now benefits from the FSRS-5-correct
///   short-term stability update above even though the due date itself
///   still lands on a future calendar day.
///
/// **Remaining roadmap item:**
/// - **ReviewLogs are recorded** on every grade (see `CardRepository.gradeCard`)
///   **but not yet used for per-user weight fitting** — everyone runs on the
///   pretrained defaults. Fitting per-user weights from accumulated
///   ReviewLogs (optimizer) is explicitly deferred.
///
/// Reference: https://github.com/open-spaced-repetition/fsrs-rs
public enum FSRSService {

    // MARK: - Default FSRS-5 Weights

    /// Default FSRS-5 pretrained weights (w[0]..w[18]).
    /// These are the pretrained defaults from the FSRS-5 paper. Every weight
    /// is consumed by this engine (w[6], w[17], w[18] included).
    public static let defaultWeights: [Double] = [
        0.4072,  // w[0]:  initial stability for Again
        1.1829,  // w[1]:  initial stability for Hard
        3.1262,  // w[2]:  initial stability for Good
        15.4722, // w[3]:  initial stability for Easy
        7.2102,  // w[4]:  initial difficulty for Good
        0.5316,  // w[5]:  difficulty grade multiplier
        1.0651,  // w[6]:  difficulty delta per grade (linearly-damped ΔD)
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
        0.2939,  // w[17]: short-term (same-day) stability factor
        0.4535,  // w[18]: short-term (same-day) stability offset
    ]

    /// Maximum interval in days (100 years)
    public static let maximumInterval: Double = 36500

    /// FSRS-5 forgetting-curve decay exponent.
    private static let decay: Double = -0.5

    /// FSRS-5 forgetting-curve factor, chosen so that R(S) = 0.9 for any
    /// stability S: FACTOR = 19/81.
    private static let factor: Double = 19.0 / 81.0

    /// Below this elapsed-time threshold (in days) since the last review,
    /// stability updates use the short-term formula instead of the regular
    /// DSR update.
    private static let sameDayThresholdDays: Double = 1.0

    /// Clamp band for `desiredRetention` at read sites (e.g.
    /// `CardModelActor.gradeCard`). Matches the Settings UI's stepped
    /// control (0.80/0.85/0.90/0.95).
    public static let desiredRetentionRange: ClosedRange<Double> = 0.8...0.95

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
    /// The resulting interval is always at least 1 day (see `nextInterval`) —
    /// this scheduler never emits same-day due dates; that's the session
    /// layer's job (see the type-level doc comment).
    ///
    /// - Parameters:
    ///   - state: The FSRS state of the card
    ///   - desiredRetention: Target retention rate (0.0–1.0), default 0.9.
    ///     Production callers should pass the active profile's
    ///     `ProfileSettings.desiredRetention` (see `CardModelActor.gradeCard`).
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
    /// R(t) = (1 + FACTOR * t / S) ^ DECAY, the FSRS-5 forgetting curve
    /// (DECAY = -0.5, FACTOR = 19/81).
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

        if elapsedDays < sameDayThresholdDays {
            // Same-day re-grade (e.g. intra-session requeue): FSRS-5's
            // short-term stability update, not the regular DSR formula.
            newStability = shortTermStability(
                stability: state.stability,
                grade: grade,
                weights: weights
            )
        } else if isLapse {
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

    /// FSRS-5 power forgetting curve: R(t) = (1 + FACTOR * t / S) ^ DECAY
    /// with DECAY = -0.5, FACTOR = 19/81.
    ///
    /// Chosen so that R(S) = 0.9 for any stability S (same "S is the
    /// 90%-retention interval" definition as FSRS-4's curve).
    private static func powerForgetCurve(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * elapsedDays / stability, decay)
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

    /// Next difficulty after a review — full FSRS-5 form.
    ///
    /// 1. ΔD = -w[6] * (G - 3)
    /// 2. Linear damping toward the difficulty ceiling:
    ///    D' = D + ΔD * (10 - D) / 9
    /// 3. Mean-revert toward D₀(Easy) with w[7]:
    ///    D'' = w[7] * D₀(Easy) + (1 - w[7]) * D'
    ///
    /// Clamping to [1, 10] happens at the call site (`clampDifficulty`),
    /// same as the rest of this engine.
    private static func nextDifficulty(
        currentDifficulty: Double,
        grade: Grade,
        weights: [Double]
    ) -> Double {
        let g = Double(grade.rawValue)
        let deltaD = -weights[6] * (g - 3)
        let damped = currentDifficulty + deltaD * (10 - currentDifficulty) / 9
        let easyD0 = initialDifficulty(grade: .easy, weights: weights)
        return weights[7] * easyD0 + (1 - weights[7]) * damped
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

    /// Short-term (same-day) stability update — FSRS-5 form.
    /// S' = S * e^(w[17] * (G - 3 + w[18]))
    ///
    /// Used instead of `stabilityAfterSuccess`/`stabilityAfterFailure` when
    /// the elapsed time since the last review is under 1 day (e.g. an
    /// intra-session requeue of a card just graded `.again`).
    private static func shortTermStability(
        stability: Double,
        grade: Grade,
        weights: [Double]
    ) -> Double {
        let g = Double(grade.rawValue)
        return stability * exp(weights[17] * (g - 3 + weights[18]))
    }

    /// Compute the next interval in days from stability and desired retention.
    ///
    /// Inverts the FSRS-5 forgetting curve R(t) = (1 + FACTOR*t/S)^DECAY at
    /// R = desiredRetention:
    ///   R = (1 + FACTOR*t/S)^DECAY
    ///   R^(1/DECAY) = 1 + FACTOR*t/S
    ///   t = (S/FACTOR) * (R^(1/DECAY) - 1)
    ///
    /// The result is clamped to >= 1 day, so the scheduler never produces
    /// same-day due dates; same-day relearning is the session layer's job.
    private static func nextInterval(stability: Double, desiredRetention: Double) -> Double {
        guard desiredRetention > 0, desiredRetention < 1, stability > 0 else {
            return 1
        }
        let interval = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        return max(1, interval)
    }

    /// Clamp difficulty to [1, 10] range.
    private static func clampDifficulty(_ difficulty: Double) -> Double {
        min(10, max(1, difficulty))
    }
}
