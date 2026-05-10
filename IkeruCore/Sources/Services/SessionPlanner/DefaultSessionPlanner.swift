import Foundation
import os

/// Concrete `SessionPlanner`. Structurally deterministic from inputs;
/// content selection within each segment is randomised (`randomElement()`)
/// from the available card pool, so the *shape* of the plan is stable
/// per-day but specific exercise content varies. No I/O.
///
/// Home composition follows a 40/30/20/10 segment skeleton:
///   - 40 % review wave (FSRS-due cards)
///   - 30 % skill-balance booster (lowest tracked skill in `LearnerSnapshot`)
///   - 20 % variety tile (rotating, drawn from level-tied variety pool,
///     excluding the booster's skill so the same skill isn't doubled up)
///   - 10 % new-content drip (one unseen card)
///
/// Étude/Study composition is round-robin across the user's selected
/// types, intersected with the unlocked set, ordered by pedagogical
/// receptive→productive.
public struct DefaultSessionPlanner: SessionPlanner {

    public static let homeReviewFraction: Double = 0.40
    public static let homeSkillBalanceBoosterFraction: Double = 0.30
    public static let homeVarietyTileFraction: Double = 0.20
    public static let homeNewContentFraction: Double = 0.10

    public init() {}

    public func compose(inputs: SessionPlannerInputs) async -> SessionPlan {
        let plan: SessionPlan
        switch inputs.source {
        case .homeRecommendation:
            plan = composeHome(inputs: inputs)
        case .studyCustom(let types, let levels):
            plan = composeStudy(inputs: inputs, types: types, levels: levels)
        }
        Logger.learningLoop.info(
            "session.composed source=\(String(describing: inputs.source), privacy: .public) duration=\(inputs.durationMinutes)"
        )
        return plan
    }

    // MARK: - Home

    private func composeHome(inputs: SessionPlannerInputs) -> SessionPlan {
        let totalSec = inputs.durationMinutes * 60
        var exercises: [ExerciseItem] = []

        // Segment 1: Review wave (40 %)
        let reviewBudget = Int(Double(totalSec) * Self.homeReviewFraction)
        exercises.append(contentsOf: pickReviews(
            from: inputs.availableCards,
            secondsBudget: reviewBudget
        ))

        // Segment 2: Skill-balance booster (30 %)
        let skillBoosterBudget = Int(Double(totalSec) * Self.homeSkillBalanceBoosterFraction)
        let lowestSkill = lowestSkill(in: inputs.profile.skillBalances)
        let boosterPool = VarietyPoolResolver.effectivePool(
            for: inputs.profile.jlptLevel,
            unlockedTypes: inputs.unlockedTypes
        )
        exercises.append(contentsOf: fillSegment(
            forSkill: lowestSkill,
            inPool: boosterPool,
            secondsBudget: skillBoosterBudget,
            availableCards: inputs.availableCards
        ))

        // Segment 3: Variety tile (20 %) — different skill from booster.
        let varietyBudget = Int(Double(totalSec) * Self.homeVarietyTileFraction)
        let varietyPool = boosterPool.filter { $0.skill != lowestSkill }
        exercises.append(contentsOf: fillRotating(
            inPool: varietyPool,
            secondsBudget: varietyBudget,
            day: dayOfYear(),
            availableCards: inputs.availableCards
        ))

        // Segment 4: New content drip (10 %)
        let newContentBudget = Int(Double(totalSec) * Self.homeNewContentFraction)
        if let item = pickNewContent(
            secondsBudget: newContentBudget,
            availableCards: inputs.availableCards
        ) {
            exercises.append(item)
        }

        return finalize(exercises: exercises)
    }

    // MARK: - Study custom

    private func composeStudy(
        inputs: SessionPlannerInputs,
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>
    ) -> SessionPlan {
        let candidate = types.intersection(inputs.unlockedTypes)
        let totalSec = inputs.durationMinutes * 60
        var exercises: [ExerciseItem] = []
        var spent = 0

        let ordered = candidate.sorted {
            $0.skill.pedagogicalOrder < $1.skill.pedagogicalOrder
        }
        guard !ordered.isEmpty else { return finalize(exercises: []) }
        var idx = 0
        var safety = 0
        while spent < totalSec, safety < 100 {
            let type = ordered[idx % ordered.count]
            let item = synthesise(type: type, availableCards: inputs.availableCards)
            if spent + item.estimatedDurationSeconds > totalSec, !exercises.isEmpty { break }
            exercises.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        // `levels` reserved for future content-pool filtering; not yet
        // wired because content packs aren't tagged by JLPT yet.
        // `levels` is reserved for future content-pool filtering; not yet
        // wired because content packs aren't tagged by JLPT yet. Surface
        // this loud-and-clear in logs so callers know their filter was a no-op.
        if !levels.isEmpty {
            let names = levels.map(\.rawValue).joined(separator: ",")
            Logger.learningLoop.info("studyCustom: jlptLevels filtering not yet implemented — ignoring \(names, privacy: .public)")
        }
        _ = levels
        return finalize(exercises: exercises)
    }

    // MARK: - Helpers

    /// Fills a budget by appending SRS reviews until the next would overflow.
    private func pickReviews(from cards: [CardDTO], secondsBudget: Int) -> [ExerciseItem] {
        var items: [ExerciseItem] = []
        var spent = 0
        for card in cards {
            let exercise = ExerciseItem.srsReview(card)
            if spent + exercise.estimatedDurationSeconds > secondsBudget { break }
            items.append(exercise)
            spent += exercise.estimatedDurationSeconds
        }
        return items
    }

    /// Fills a segment with exercises targeting `skill`, drawn from `pool`.
    /// Picks the shortest-fitting candidate first, then repeats it until
    /// the budget is exhausted (round-robin across all candidates that fit).
    private func fillSegment(
        forSkill skill: SkillType,
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        availableCards: [CardDTO]
    ) -> [ExerciseItem] {
        let candidates = pool
            .filter { $0.skill == skill }
            .sorted { $0.estimatedDurationSeconds < $1.estimatedDurationSeconds }
        guard !candidates.isEmpty else { return [] }

        var items: [ExerciseItem] = []
        var spent = 0
        var idx = 0
        var safety = 0
        while spent < secondsBudget, safety < 100 {
            let type = candidates[idx % candidates.count]
            let item = synthesise(type: type, availableCards: availableCards)
            if spent + item.estimatedDurationSeconds > secondsBudget { break }
            items.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        return items
    }

    /// Fills the variety segment by rotating through the pool. Day index
    /// chooses the starting point so the variety tile shifts day-by-day.
    private func fillRotating(
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        day: Int,
        availableCards: [CardDTO]
    ) -> [ExerciseItem] {
        guard !pool.isEmpty else { return [] }
        let sorted = pool.sorted { $0.rawValue < $1.rawValue }
        var items: [ExerciseItem] = []
        var spent = 0
        var idx = 0
        var safety = 0
        while spent < secondsBudget, safety < 100 {
            let type = sorted[(day + idx) % sorted.count]
            let item = synthesise(type: type, availableCards: availableCards)
            if spent + item.estimatedDurationSeconds > secondsBudget { break }
            items.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        return items
    }

    private func pickNewContent(secondsBudget: Int, availableCards: [CardDTO]) -> ExerciseItem? {
        if let card = availableCards.first(where: { $0.fsrsState.reps == 0 }) {
            let exercise = ExerciseItem.srsReview(card)
            return exercise.estimatedDurationSeconds <= secondsBudget ? exercise : nil
        }
        return nil
    }

    /// Maps an `ExerciseType` to a concrete `ExerciseItem` payload.
    /// Where content isn't available yet (e.g., reading passages), uses
    /// a placeholder UUID so the planner can return a structurally valid
    /// plan; downstream UI may show a "content coming soon" notice.
    private func synthesise(type: ExerciseType, availableCards: [CardDTO]) -> ExerciseItem {
        switch type {
        case .kanaStudy, .kanjiStudy:
            // KNOWN ISSUE: kanaStudy synthesises an .kanjiStudy ExerciseItem
            // payload because ExerciseItem has no .kanaStudy case yet. This
            // means a kana drill is reported as 60s (kanjiStudy duration)
            // instead of the 25s the type-level estimate uses, slightly
            // inflating the plan's reported duration. Tracked as a
            // model-level follow-up: add `case kanaStudy(String)` to
            // ExerciseItem and route here.
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            return .kanjiStudy(kanjiCards.randomElement()?.front ?? "\u{4E00}")
        case .vocabularyStudy:
            return .vocabularyStudy(UUID())
        case .listeningSubtitled, .listeningUnsubtitled:
            return .listeningExercise(UUID())
        case .fillInBlank:
            return .fillInBlank(UUID())
        case .grammarExercise:
            return .grammarExercise(UUID())
        case .sentenceConstruction:
            return .sentenceConstruction(UUID())
        case .readingPassage:
            return .readingPassage(UUID())
        case .writingPractice:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            return .writingPractice(kanjiCards.randomElement()?.front ?? "\u{4E00}")
        case .speakingPractice, .sakuraConversation:
            return .speakingExercise(UUID())
        }
    }

    private func lowestSkill(in balances: [SkillType: Double]) -> SkillType {
        let sorted = SkillType.allCases.sorted { (balances[$0] ?? 0) < (balances[$1] ?? 0) }
        return sorted.first ?? .reading
    }

    private func dayOfYear(now: Date = Date()) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: now) ?? 0
    }

    private func finalize(exercises: [ExerciseItem]) -> SessionPlan {
        let secs = exercises.map(\.estimatedDurationSeconds).reduce(0, +)
        var breakdown: [SkillType: Int] = [:]
        for ex in exercises { breakdown[ex.skill, default: 0] += 1 }
        return SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(0, secs / 60),
            exerciseBreakdown: breakdown
        )
    }
}
