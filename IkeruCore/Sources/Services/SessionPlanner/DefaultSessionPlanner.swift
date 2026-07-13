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
            guard let item = synthesise(type: type, availableCards: inputs.availableCards) else {
                idx += 1
                safety += 1
                continue
            }
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
    /// Only cards whose `dueDate <= now` AND that the learner has actually
    /// begun (`reps > 0`) enter the review wave. The `reps > 0` gate is what
    /// keeps never-started characters — e.g. the full katakana set that gets
    /// materialised as immediately-due cards the moment the kana grid is
    /// opened — out of "Practice", which is meant to *review* what you've
    /// started. Brand-new characters reach the session only through the
    /// curriculum-ordered new-content drip (`pickNewContent`), never as reviews.
    /// (`dueDate <= now` alone previously re-served a just-graded card; the
    /// reps gate additionally stops the unlearned-katakana leak.)
    private func pickReviews(from cards: [CardDTO], secondsBudget: Int, now: Date = Date()) -> [ExerciseItem] {
        // Most-overdue first: sort the eligible cards by dueDate ascending
        // (stable tiebreak on input order) so budget truncation always keeps
        // the most urgent reviews when not everything fits.
        let ordered = cards
            .filter { $0.dueDate <= now && $0.fsrsState.reps > 0 }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.dueDate != rhs.element.dueDate
                    ? lhs.element.dueDate < rhs.element.dueDate
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        var items: [ExerciseItem] = []
        var spent = 0
        for card in ordered {
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
            guard let item = synthesise(type: type, availableCards: availableCards) else {
                idx += 1
                safety += 1
                continue
            }
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
            guard let item = synthesise(type: type, availableCards: availableCards) else {
                idx += 1
                safety += 1
                continue
            }
            if spent + item.estimatedDurationSeconds > secondsBudget { break }
            items.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        return items
    }

    /// Curriculum index for every base kana (hiragana あいうえお… first, then
    /// katakana), built once from the canonical group order. Used to introduce
    /// new characters in pedagogical order rather than whatever order
    /// `allCards()` happens to return — so day one always teaches あ, and
    /// hiragana is always offered before katakana.
    private static let kanaCurriculumIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, kana) in KanaGroup.allBaseCharacters.enumerated() {
            map[kana.character] = index
        }
        return map
    }()

    /// Picks the single "new" (never-reviewed) card to drip into the session.
    /// Candidates are ordered by the kana curriculum so the introduction order
    /// is stable and pedagogical (hiragana before katakana); non-kana new
    /// content sorts after all kana. Without this ordering the drip grabbed an
    /// arbitrary unseen card from `allCards()` ordering — which could be a
    /// katakana the learner never chose.
    private func pickNewContent(secondsBudget: Int, availableCards: [CardDTO]) -> ExerciseItem? {
        let unseen = availableCards.filter { $0.fsrsState.reps == 0 }
        guard !unseen.isEmpty else { return nil }
        let ordered = unseen.sorted { lhs, rhs in
            let li = Self.kanaCurriculumIndex[lhs.front] ?? Int.max
            let ri = Self.kanaCurriculumIndex[rhs.front] ?? Int.max
            if li != ri { return li < ri }
            return lhs.front < rhs.front
        }
        guard let card = ordered.first else { return nil }
        let exercise = ExerciseItem.srsReview(card)
        return exercise.estimatedDurationSeconds <= secondsBudget ? exercise : nil
    }

    /// Maps an `ExerciseType` to a concrete `ExerciseItem` payload.
    ///
    /// Returns `nil` when the type requires a real backing card that isn't
    /// available (kanji study / writing practice with no kanji card in the
    /// pool): we never fabricate a card, because a synthetic card can't be
    /// honestly FSRS-graded. Callers skip `nil` results. Content-backed kinds
    /// that don't have a real content source yet (reading passages, listening,
    /// etc.) still use a placeholder UUID so the planner can return a
    /// structurally valid plan; those are filtered by `finalize` until wired.
    private func synthesise(type: ExerciseType, availableCards: [CardDTO]) -> ExerciseItem? {
        switch type {
        case .kanjiStudy:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            guard let card = kanjiCards.randomElement() else { return nil }
            return .kanjiStudy(card)
        case .kanaStudy:
            // Kana is NOT an SRS `Card`: it lives in the separate KanaCharacter /
            // KanaData model, drilled by the standalone KanaDrillViewModel. There
            // is therefore no `CardDTO` to back a kana study exercise, no
            // `.kanaStudy` case on `ExerciseItem`, and no single-kana in-session
            // drill unit. Synthesise nothing rather than fabricating a wrong-type
            // kanji drill from a kanji card (the prior bug: `.kanaStudy` shared
            // this branch with `.kanjiStudy` and returned `.kanjiStudy(card)`,
            // showing a kanji handwriting drill for a kana request). A real
            // kana-in-mixed-session unit — a dedicated `ExerciseItem` case + view
            // sourcing KanaCharacters — is future work for the Compose/Étude sheet.
            return nil
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
            guard let card = kanjiCards.randomElement() else { return nil }
            return .writingPractice(card)
        case .speakingPractice, .sakuraConversation:
            return .speakingExercise(UUID())
        }
    }

    /// Whether an exercise kind is "live" — i.e. backed by a real, wired
    /// in-session drill view that can present and honestly grade it. Used by
    /// `finalize` as an allowlist so the planner never schedules a placeholder.
    ///
    /// Exhaustive on `ExerciseItem` on purpose: adding a new kind forces an
    /// explicit live/filtered decision here rather than silently defaulting.
    ///
    ///   LIVE (wired drill views):
    ///     Tier 1:
    ///       .srsReview            — SRS flashcard deck
    ///       .kanjiStudy           — HandwritingExerciseView, writes a real FSRS grade
    ///       .writingPractice      — HandwritingExerciseView, writes a real FSRS grade
    ///       .sentenceConstruction — SentenceConstructionView, XP-only
    ///     Tier 2 (XP-only drills):
    ///       .listeningExercise    — ListeningExerciseView (word/meaning subtypes)
    ///       .speakingExercise     — ShadowingExerciseView
    ///       .vocabularyStudy      — VocabularyRecallView (multiple-choice recall)
    ///
    ///   STILL FILTERED (no wired view / no real content source yet):
    ///     Tier 3 (deferred):  .fillInBlank, .readingPassage, .grammarExercise
    ///     (listening PASSAGE comprehension also stays out — no passages table.)
    ///
    /// NOTE (`.vocabularyStudy` XP-only): vocabulary has NO backing SwiftData
    /// `Card` (it lives only in the read-only content DB), so its completion is
    /// XP-only — it never writes an FSRS grade or `ReviewLog`. See
    /// `SessionViewModel.completeCurrentExercise`, where only `.kanjiStudy`
    /// reaches `gradeCard`. FSRS scheduling for vocabulary is deferred until the
    /// vocab-dictionary feature makes vocab cards gradeable.
    static func isLive(_ item: ExerciseItem) -> Bool {
        switch item {
        case .srsReview, .kanjiStudy, .writingPractice, .sentenceConstruction,
             .listeningExercise, .speakingExercise, .vocabularyStudy:
            return true
        case .fillInBlank, .readingPassage, .grammarExercise:
            return false
        }
    }

    private func lowestSkill(in balances: [SkillType: Double]) -> SkillType {
        let sorted = SkillType.allCases.sorted { (balances[$0] ?? 0) < (balances[$1] ?? 0) }
        return sorted.first ?? .reading
    }

    private func dayOfYear(now: Date = Date()) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: now) ?? 0
    }

    private func finalize(exercises rawExercises: [ExerciseItem]) -> SessionPlan {
        // Allowlist of exercise kinds that have a real, fully-wired in-session
        // drill view TODAY. Everything else still renders a placeholder, so the
        // planner filters it out rather than scheduling something the UI cannot
        // honestly present or grade. This replaces the previous SRS-only filter.
        let exercises = rawExercises.filter { Self.isLive($0) }
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
