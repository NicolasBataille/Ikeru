import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - SessionComposer
//
// Owns the `SessionPlanner`-pipeline composition work `SessionViewModel` does
// at the start of a basic / study-custom / review-mistakes session: building
// the `LearnerSnapshot`, resolving unlocked exercise types, asking the
// planner for a plan, extracting the SRS-backed `CardDTO`s for the swipeable
// queue, and loading the session-scoped vocabulary pool for the audio drills.
// Extracted from `SessionViewModel` (remediation 8.4) — every computation
// here is a verbatim move of the corresponding private method/inline block;
// `SessionViewModel` applies the returned plan onto its own `@Observable`
// state and still owns the timer-start / RPG-load / Live-Activity-start /
// logging side effects (those differ per session-start path in ways not
// worth abstracting further).
@MainActor
final class SessionComposer {

    private let plannerService: PlannerService
    private let sessionPlanner: any SessionPlanner
    private let unlockService: any ExerciseUnlockService
    private let cardRepository: CardRepository
    private let contentRepository: ContentRepository?
    private let modelContainer: ModelContainer

    init(
        plannerService: PlannerService,
        sessionPlanner: any SessionPlanner,
        unlockService: any ExerciseUnlockService,
        cardRepository: CardRepository,
        contentRepository: ContentRepository?,
        modelContainer: ModelContainer
    ) {
        self.plannerService = plannerService
        self.sessionPlanner = sessionPlanner
        self.unlockService = unlockService
        self.cardRepository = cardRepository
        self.contentRepository = contentRepository
        self.modelContainer = modelContainer
    }

    /// Extracts `CardDTO`s from SRS review exercises for the swipeable queue.
    /// Non-SRS exercises (variety / new content tiles) are still tracked in
    /// `sessionExercises` so immersive mode can render them.
    static func srsCards(from exercises: [ExerciseItem]) -> [CardDTO] {
        exercises.compactMap { exercise -> CardDTO? in
            if case .srsReview(let card) = exercise { return card }
            return nil
        }
    }

    // MARK: - Home Recommendation (startSession)

    struct HomeRecommendationPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        let endPolicy: SessionEndPolicy
        let jlptLevel: JLPTLevel
        let vocabularyPool: [VocabularyItem]
        let srsCardCount: Int
        let estimatedDurationMinutes: Int
    }

    /// Composes a session queue via the `SessionPlanner` pipeline for the
    /// home-recommendation source. Returns nil when the composed plan has no
    /// SRS cards — never start an empty session, matching the original guard
    /// in `startSession()`.
    func composeHomeRecommendation(durationMinutes: Int) async -> HomeRecommendationPlan? {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let unlockedTypes = effectiveUnlockedTypes(profile: snapshot)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: durationMinutes,
            profile: snapshot,
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)
        let srsCards = Self.srsCards(from: plan.exercises)
        guard !srsCards.isEmpty else { return nil }

        let pool = await vocabularyPool(level: snapshot.jlptLevel)

        return HomeRecommendationPlan(
            sessionQueue: srsCards,
            sessionExercises: plan.exercises,
            endPolicy: SessionEndPolicy(
                durationBudgetMinutes: durationMinutes,
                queueLength: plan.exercises.count
            ),
            jlptLevel: snapshot.jlptLevel,
            vocabularyPool: pool,
            srsCardCount: srsCards.count,
            estimatedDurationMinutes: plan.estimatedDurationMinutes
        )
    }

    // MARK: - Study Custom (startStudyCustomSession)

    struct StudyCustomPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        let endPolicy: SessionEndPolicy
        let jlptLevel: JLPTLevel
        let vocabularyPool: [VocabularyItem]
        let srsCardCount: Int
        let estimatedDurationMinutes: Int
    }

    /// Composes a custom session from the Étude → Compose sheet. Same
    /// pipeline as `composeHomeRecommendation` but with `.studyCustom` as the
    /// planner source so the planner respects the user's chosen exercise
    /// types and JLPT levels. Unlike the home-recommendation path, this never
    /// returns nil — `startStudyCustomSession()` has no empty-queue guard.
    func composeStudyCustom(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) async -> StudyCustomPlan {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let unlockedTypes = effectiveUnlockedTypes(profile: snapshot)
        let inputs = SessionPlannerInputs(
            source: .studyCustom(types: types, jlptLevels: levels),
            durationMinutes: duration,
            profile: snapshot,
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)
        let srsCards = Self.srsCards(from: plan.exercises)

        // Custom sessions: use the highest selected JLPT level so the XP
        // multiplier matches the user's chosen difficulty rather than their
        // estimated level. Falls back to snapshot estimate if no levels were
        // selected (defensive — UI requires a selection).
        let jlptLevel = levels.max() ?? snapshot.jlptLevel
        let pool = await vocabularyPool(level: jlptLevel)

        return StudyCustomPlan(
            sessionQueue: srsCards,
            sessionExercises: plan.exercises,
            endPolicy: SessionEndPolicy(
                durationBudgetMinutes: duration,
                queueLength: plan.exercises.count
            ),
            jlptLevel: jlptLevel,
            vocabularyPool: pool,
            srsCardCount: srsCards.count,
            estimatedDurationMinutes: plan.estimatedDurationMinutes
        )
    }

    // MARK: - Review Mistakes (startReviewMistakes)

    struct ReviewMistakesPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
    }

    /// Restarts the session with only the cards graded `.again` in the
    /// previous session. Returns nil if the missed-set (or the resolved card
    /// list) is empty, matching the original's early-return guards.
    func composeReviewMistakes(missedCardIDs: Set<UUID>) async -> ReviewMistakesPlan? {
        guard !missedCardIDs.isEmpty else { return nil }
        let allCards = await cardRepository.allCards()
        let mistakes = allCards.filter { missedCardIDs.contains($0.id) }
        guard !mistakes.isEmpty else { return nil }
        return ReviewMistakesPlan(
            sessionQueue: mistakes,
            sessionExercises: mistakes.map { ExerciseItem.srsReview($0) }
        )
    }

    // MARK: - Adaptive Preview (loadSessionPreview)

    struct AdaptivePreview {
        let preview: SessionPreview
        let totalExercises: Int
        let totalSeconds: Int
    }

    /// Computes a session preview without starting the session, using
    /// adaptive composition (`PlannerService`) to provide a detailed
    /// exercise breakdown.
    func composePreview(config: SessionConfig) async -> AdaptivePreview {
        let plan = await plannerService.composeAdaptiveSession(config: config)
        let totalExercises = plan.exercises.count
        let totalSeconds = plan.exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }

        var skillSplit: [SkillType: Double] = [:]
        if totalExercises > 0 {
            for (skill, count) in plan.exerciseBreakdown {
                skillSplit[skill] = Double(count) / Double(totalExercises)
            }
        }

        let preview = SessionPreview(
            estimatedMinutes: plan.estimatedDurationMinutes,
            cardCount: totalExercises,
            exerciseBreakdown: plan.exerciseBreakdown,
            skillSplit: skillSplit
        )

        return AdaptivePreview(preview: preview, totalExercises: totalExercises, totalSeconds: totalSeconds)
    }

    // MARK: - Adaptive Session (startAdaptiveSession)

    struct AdaptiveSessionPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        let srsCardCount: Int
        let supplementaryExerciseCount: Int
    }

    /// Composes an adaptive session using the provided config. Returns nil
    /// when the adaptive plan produced no exercises — the caller falls back
    /// to `startSession()`, matching the original's guard.
    func composeAdaptive(config: SessionConfig) async -> AdaptiveSessionPlan? {
        let plan = await plannerService.composeAdaptiveSession(config: config)
        guard !plan.exercises.isEmpty else { return nil }
        let srsCards = Self.srsCards(from: plan.exercises)
        return AdaptiveSessionPlan(
            sessionQueue: srsCards,
            sessionExercises: plan.exercises,
            srsCardCount: srsCards.count,
            supplementaryExerciseCount: plan.supplementaryExerciseCount
        )
    }

    // MARK: - Vocabulary Pool

    /// Loads and maps the session vocabulary pool for the audio drills
    /// (Shadowing / Listening). Returns an empty pool when no
    /// `ContentRepository` was injected (previews / tests) — never throws,
    /// never blocks the session start on a failed content read.
    func vocabularyPool(level: JLPTLevel) async -> [VocabularyItem] {
        guard let contentRepository else { return [] }
        let rows = await contentRepository.vocabularyByLevel(level)
        let pool = VocabularyItemMapper.map(rows)
        Logger.ui.info(
            "session.vocabPool level=\(level.rawValue, privacy: .public) count=\(pool.count, privacy: .public)"
        )
        return pool
    }

    // MARK: - Learner Snapshot

    /// Builds a `LearnerSnapshot` from the current card pool + active
    /// profile state. Pure delegation to `LearnerSnapshotBuilder.build(...)`
    /// — no side effects beyond reading the active RPG state for the
    /// `lastSessionAt` timestamp.
    ///
    /// Feeds real skill balances (from `ProgressService`), grammar mastery
    /// (derived by the builder from `.grammar` cards) and listening accuracy /
    /// recall (from persisted `ExerciseOutcomeLog`s) into the snapshot — the last
    /// two unlock `.listeningUnsubtitled` / `.speakingPractice` (remediation 4.4).
    func buildSnapshot(cards: [CardDTO]) async -> LearnerSnapshot {
        let now = Date()
        let progressService = ProgressService(cardRepository: cardRepository)
        let progress = await progressService.loadDashboardData(now: now)
        let jlptLevel = JLPTLevel(rawValue: progress.jlptEstimate.level.lowercased()) ?? .n5
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?
            .lastSessionDate
        let listeningAccuracy = await cardRepository.listeningAccuracyLast30()
        let listeningRecall = await cardRepository.listeningRecallLast30Days(now: now)
        return LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: jlptLevel,
            listeningAccuracyLast30: listeningAccuracy,
            listeningRecallLast30Days: listeningRecall,
            skillBalances: progress.skillBalance.asSkillBalances,
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession,
            now: now
        )
    }

    // MARK: - Effective Unlocks

    /// Effective unlocked set for session planning: the live threshold
    /// evaluation UNION the profile's already-acknowledged unlocks. Unlocks are
    /// one-way — once granted (recorded in `RPGState.acknowledgedUnlocks`), a
    /// stricter later mastery definition must never silently re-lock them.
    func effectiveUnlockedTypes(profile snapshot: LearnerSnapshot) -> Set<ExerciseType> {
        let live = unlockService.unlockedTypes(profile: snapshot)
        let acknowledged = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?
            .acknowledgedUnlocks ?? []
        return live.union(acknowledged)
    }
}
