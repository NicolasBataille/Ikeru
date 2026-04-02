import Foundation
import Observation
import os

/// Composes study sessions by selecting and ordering cards.
/// Supports both basic (Story 1.5) and adaptive (Story 5.1) composition.
///
/// Basic `composeSession()` is preserved as a backward-compatible fallback.
/// Adaptive `composeAdaptiveSession(config:)` uses skill balancing, time adaptation,
/// silent mode, and pedagogical sequencing.
///
/// All composition logic is pure — no side effects, no database writes.
@Observable
public final class PlannerService {

    /// Maximum number of new (unseen) cards to include per session.
    public static let maxNewCardsPerSession = 5

    /// Minimum floor percentage for any skill in a session.
    private static let minimumSkillFloor = 0.10

    private let cardRepository: CardRepository

    public init(cardRepository: CardRepository) {
        self.cardRepository = cardRepository
    }

    // MARK: - Basic Composition (Story 1.5 — Backward Compatible)

    /// Composes a session queue from available cards.
    /// - Returns: An ordered array of cards for the session (due cards first, then new cards).
    public func composeSession() async -> [CardDTO] {
        let startTime = CFAbsoluteTimeGetCurrent()

        let now = Date()
        let dueCards = await cardRepository.dueCards(before: now)
        let allCards = await cardRepository.allCards()

        let dueCardIds = Set(dueCards.map(\.id))
        let newCards = allCards
            .filter { $0.fsrsState.reps == 0 && !dueCardIds.contains($0.id) }
            .prefix(Self.maxNewCardsPerSession)

        let queue = dueCards + Array(newCards)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.planner.info(
            "Session composed: \(dueCards.count) due + \(newCards.count) new = \(queue.count) total (\(elapsed, format: .fixed(precision: 1))ms)"
        )

        return queue
    }

    // MARK: - Adaptive Composition (Story 5.1)

    /// Composes an adaptive session plan considering skill balance, time, and context.
    ///
    /// This is a pure function — takes inputs, returns a SessionPlan, no side effects.
    /// - Parameter config: Session configuration including time, mode, and balance data.
    /// - Returns: A SessionPlan with ordered exercises, timing estimates, and skill breakdown.
    public func composeAdaptiveSession(config: SessionConfig) async -> SessionPlan {
        let startTime = CFAbsoluteTimeGetCurrent()

        let now = Date()
        let dueCards = await cardRepository.dueCards(before: now)
        let allCards = await cardRepository.allCards()

        let duration = SessionDuration.from(minutes: config.availableTimeMinutes)
        let timeBudgetSeconds = config.availableTimeMinutes * 60

        // Step 1: Select SRS review cards (always take priority)
        let srsCards = selectSRSCards(dueCards: dueCards, allCards: allCards, duration: duration)

        // Step 2: Build SRS exercises
        var exercises: [ExerciseItem] = srsCards.map { .srsReview($0) }
        var usedTimeSeconds = exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }

        // Step 3: Add supplementary exercises if time allows and tier supports it
        if duration.includesSupplementary && usedTimeSeconds < timeBudgetSeconds {
            let remainingSeconds = timeBudgetSeconds - usedTimeSeconds
            let supplementary = composeSupplementaryExercises(
                config: config,
                duration: duration,
                remainingSeconds: remainingSeconds,
                allCards: allCards
            )
            exercises.append(contentsOf: supplementary)
            usedTimeSeconds = exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }
        }

        // Step 4: Build the plan
        let estimatedMinutes = max(0, usedTimeSeconds / 60)
        let breakdown = computeBreakdown(exercises: exercises)

        let plan = SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: estimatedMinutes,
            exerciseBreakdown: breakdown
        )

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.planner.info(
            "Adaptive session composed: \(exercises.count) exercises, ~\(estimatedMinutes)min (\(elapsed, format: .fixed(precision: 1))ms)"
        )

        return plan
    }

    // MARK: - Skill Balance Computation

    /// Computes current skill balance ratios from the card repository.
    /// Maps CardType to SkillType and computes ratios based on card counts.
    /// - Returns: Dictionary of SkillType to ratio (0.0-1.0, summing to 1.0).
    public func computeSkillBalances() async -> [SkillType: Double] {
        let allCards = await cardRepository.allCards()
        let reviewedCards = allCards.filter { $0.fsrsState.reps > 0 }

        guard !reviewedCards.isEmpty else {
            // No reviewed cards — return equal distribution
            let equal = 1.0 / Double(SkillType.allCases.count)
            return Dictionary(uniqueKeysWithValues: SkillType.allCases.map { ($0, equal) })
        }

        var counts: [SkillType: Int] = [:]
        for card in reviewedCards {
            let skill = skillType(for: card.type)
            counts[skill, default: 0] += 1
        }

        let total = Double(reviewedCards.count)
        var ratios: [SkillType: Double] = [:]
        for skill in SkillType.allCases {
            ratios[skill] = Double(counts[skill] ?? 0) / total
        }

        return ratios
    }

    // MARK: - Private Helpers

    /// Maps CardType to SkillType.
    private func skillType(for cardType: CardType) -> SkillType {
        switch cardType {
        case .kanji, .vocabulary, .grammar:
            .reading
        case .listening:
            .listening
        }
    }

    /// Selects SRS cards for the session based on duration tier.
    private func selectSRSCards(
        dueCards: [CardDTO],
        allCards: [CardDTO],
        duration: SessionDuration
    ) -> [CardDTO] {
        var selected = Array(dueCards.prefix(duration.maxSRSCards))

        // Add new cards if there's room (up to maxNewCardsPerSession)
        let dueCardIds = Set(dueCards.map(\.id))
        let newCards = allCards
            .filter { $0.fsrsState.reps == 0 && !dueCardIds.contains($0.id) }
            .prefix(Self.maxNewCardsPerSession)

        let remainingSlots = duration.maxSRSCards - selected.count
        if remainingSlots > 0 {
            selected.append(contentsOf: newCards.prefix(remainingSlots))
        }

        return selected
    }

    /// Composes supplementary (non-SRS) exercises respecting time budget and config.
    private func composeSupplementaryExercises(
        config: SessionConfig,
        duration: SessionDuration,
        remainingSeconds: Int,
        allCards: [CardDTO]
    ) -> [ExerciseItem] {
        // Determine which skills are available given context
        let availableSkills = availableSkills(for: config)

        // Compute deficit-based weights for skill selection
        let currentBalances = config.currentSkillBalances.isEmpty
            ? defaultBalances()
            : config.currentSkillBalances
        let balance = SkillBalance.defaultTargets
        let weights = balance.deficitWeights(current: currentBalances)

        // Filter weights to only available skills and re-normalize
        let filteredWeights = normalizeWeights(weights, to: availableSkills)

        // Generate exercises, filling remaining time
        var exercises: [ExerciseItem] = []
        var usedSeconds = 0

        // For focused sessions, ensure all available skills are represented
        if duration.requiresAllSkills {
            for skill in availableSkills.sorted(by: { $0.pedagogicalOrder < $1.pedagogicalOrder }) {
                guard usedSeconds < remainingSeconds else { break }
                let exercise = generateExercise(for: skill, allCards: allCards)
                if usedSeconds + exercise.estimatedDurationSeconds <= remainingSeconds {
                    exercises.append(exercise)
                    usedSeconds += exercise.estimatedDurationSeconds
                }
            }
        }

        // Fill remaining time with weighted exercises
        let supplementarySkills = availableSkills.sorted(by: { $0.pedagogicalOrder < $1.pedagogicalOrder })
        var iterationCount = 0
        let maxIterations = 50 // Safety cap for O(n) guarantee

        while usedSeconds < remainingSeconds && iterationCount < maxIterations {
            let skill = selectSkillByWeight(weights: filteredWeights)
            let exercise = generateExercise(for: skill, allCards: allCards)

            if usedSeconds + exercise.estimatedDurationSeconds > remainingSeconds {
                // Try a shorter exercise from a different skill
                var foundShorter = false
                for fallbackSkill in supplementarySkills {
                    let fallback = generateExercise(for: fallbackSkill, allCards: allCards)
                    if usedSeconds + fallback.estimatedDurationSeconds <= remainingSeconds {
                        exercises.append(fallback)
                        usedSeconds += fallback.estimatedDurationSeconds
                        foundShorter = true
                        break
                    }
                }
                if !foundShorter { break }
            } else {
                exercises.append(exercise)
                usedSeconds += exercise.estimatedDurationSeconds
            }

            iterationCount += 1
        }

        // Sort supplementary by pedagogical order: receptive before productive
        return exercises.sorted { $0.skill.pedagogicalOrder < $1.skill.pedagogicalOrder }
    }

    /// Returns the set of skills available given the session config.
    /// Excludes audio-requiring skills in silent mode.
    private func availableSkills(for config: SessionConfig) -> [SkillType] {
        if config.isSilentMode {
            Logger.planner.info("Silent mode: excluding listening and speaking exercises")
            return SkillType.allCases.filter { !$0.requiresAudio }
        }
        return SkillType.allCases.map { $0 }
    }

    /// Normalizes weights to only include the given skills, re-summing to 1.0.
    private func normalizeWeights(
        _ weights: [SkillType: Double],
        to skills: [SkillType]
    ) -> [SkillType: Double] {
        let skillSet = Set(skills)
        let filtered = weights.filter { skillSet.contains($0.key) }
        let total = filtered.values.reduce(0, +)
        guard total > 0 else {
            let equal = 1.0 / Double(skills.count)
            return Dictionary(uniqueKeysWithValues: skills.map { ($0, equal) })
        }
        return filtered.mapValues { $0 / total }
    }

    /// Selects a skill based on weighted random selection using deficit weights.
    /// Uses a deterministic approach for testability — selects highest weight.
    private func selectSkillByWeight(weights: [SkillType: Double]) -> SkillType {
        // Deterministic: pick the skill with the highest weight
        // (breaks ties by pedagogical order for consistency)
        let sorted = weights.sorted { lhs, rhs in
            if abs(lhs.value - rhs.value) < 0.001 {
                return lhs.key.pedagogicalOrder < rhs.key.pedagogicalOrder
            }
            return lhs.value > rhs.value
        }
        return sorted.first?.key ?? .reading
    }

    /// Generates an exercise for a given skill.
    private func generateExercise(for skill: SkillType, allCards: [CardDTO]) -> ExerciseItem {
        switch skill {
        case .reading:
            // Try kanji study from available kanji cards
            let kanjiCards = allCards.filter { $0.type == .kanji }
            let character = kanjiCards.randomElement()?.front ?? "\u{4e00}" // default: 一
            return .kanjiStudy(character)
        case .writing:
            let kanjiCards = allCards.filter { $0.type == .kanji }
            let character = kanjiCards.randomElement()?.front ?? "\u{4e00}"
            return .writingPractice(character)
        case .listening:
            return .listeningExercise(UUID())
        case .speaking:
            return .speakingExercise(UUID())
        }
    }

    /// Default equal balance when no history is available.
    private func defaultBalances() -> [SkillType: Double] {
        let equal = 1.0 / Double(SkillType.allCases.count)
        return Dictionary(uniqueKeysWithValues: SkillType.allCases.map { ($0, equal) })
    }

    /// Computes the exercise count per skill type.
    private func computeBreakdown(exercises: [ExerciseItem]) -> [SkillType: Int] {
        var breakdown: [SkillType: Int] = [:]
        for exercise in exercises {
            breakdown[exercise.skill, default: 0] += 1
        }
        return breakdown
    }
}
