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
        let grammarClozes: [GrammarCloze]
        let srsCardCount: Int
        let estimatedDurationMinutes: Int
        /// Card ids awaiting their ungraded new-card presentation pass — see
        /// `NewCardPresentationScheduler`. `SessionViewModel` seeds its own
        /// `cardsNeedingPresentation` from this at session start.
        let cardsNeedingPresentation: Set<UUID>
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
        let scheduled = NewCardPresentationScheduler.schedulingPresentations(for: plan.exercises)
        let exercises = scheduled.exercises
        let srsCards = Self.srsCards(from: exercises)
        guard !srsCards.isEmpty else { return nil }

        let pool = await vocabularyPool(level: snapshot.jlptLevel)
        let clozes = await grammarClozePool(level: snapshot.jlptLevel)

        return HomeRecommendationPlan(
            sessionQueue: srsCards,
            sessionExercises: exercises,
            endPolicy: SessionEndPolicy(
                durationBudgetMinutes: durationMinutes,
                queueLength: exercises.count
            ),
            jlptLevel: snapshot.jlptLevel,
            vocabularyPool: pool,
            grammarClozes: clozes,
            srsCardCount: srsCards.count,
            estimatedDurationMinutes: plan.estimatedDurationMinutes
                + Self.minutes(fromSeconds: scheduled.addedDurationSeconds),
            cardsNeedingPresentation: scheduled.cardsNeedingPresentation
        )
    }

    // MARK: - Caught up (startCaughtUpSession)

    /// Composes the session a learner explicitly asked for when nothing was
    /// due — "approfondir" or "découvrir".
    ///
    /// Deliberately reuses `HomeRecommendationPlan` and the same nil-on-empty
    /// guard: a caught-up session is an ordinary session in every respect the
    /// rest of `SessionViewModel` cares about. Only its *source* differs, and
    /// that difference lives in the planner where the pool is chosen.
    ///
    /// Returning nil here is not an error path to hide. It means the learner
    /// tapped an offer whose pool has since emptied, and the caller must keep
    /// showing the proposal rather than opening a blank session — the whole
    /// point of this change is that nothing happens silently.
    func composeCaughtUp(
        offer: SessionPlannerInputs.CaughtUpOffer,
        durationMinutes: Int
    ) async -> HomeRecommendationPlan? {
        let cards = await cardRepository.allCards()
        let snapshot = await buildSnapshot(cards: cards)
        let inputs = SessionPlannerInputs(
            source: .caughtUp(offer),
            durationMinutes: durationMinutes,
            profile: snapshot,
            unlockedTypes: effectiveUnlockedTypes(profile: snapshot),
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)
        let scheduled = NewCardPresentationScheduler.schedulingPresentations(for: plan.exercises)
        let exercises = scheduled.exercises
        let srsCards = Self.srsCards(from: exercises)
        guard !srsCards.isEmpty else {
            Logger.ui.info(
                "session.caughtUp offer=\(offer.rawValue, privacy: .public) produced no cards"
            )
            return nil
        }

        let pool = await vocabularyPool(level: snapshot.jlptLevel)
        let clozes = await grammarClozePool(level: snapshot.jlptLevel)

        return HomeRecommendationPlan(
            sessionQueue: srsCards,
            sessionExercises: exercises,
            endPolicy: SessionEndPolicy(
                durationBudgetMinutes: durationMinutes,
                queueLength: exercises.count
            ),
            jlptLevel: snapshot.jlptLevel,
            vocabularyPool: pool,
            grammarClozes: clozes,
            srsCardCount: srsCards.count,
            estimatedDurationMinutes: plan.estimatedDurationMinutes
                + Self.minutes(fromSeconds: scheduled.addedDurationSeconds),
            cardsNeedingPresentation: scheduled.cardsNeedingPresentation
        )
    }

    // MARK: - Study Custom (startStudyCustomSession)

    struct StudyCustomPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        let endPolicy: SessionEndPolicy
        let jlptLevel: JLPTLevel
        let vocabularyPool: [VocabularyItem]
        let grammarClozes: [GrammarCloze]
        let srsCardCount: Int
        let estimatedDurationMinutes: Int
        /// See `HomeRecommendationPlan.cardsNeedingPresentation`.
        let cardsNeedingPresentation: Set<UUID>
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
        let scheduled = NewCardPresentationScheduler.schedulingPresentations(for: plan.exercises)
        let exercises = scheduled.exercises
        let srsCards = Self.srsCards(from: exercises)

        // Custom sessions: use the highest selected JLPT level so the XP
        // multiplier matches the user's chosen difficulty rather than their
        // estimated level. Falls back to snapshot estimate if no levels were
        // selected (defensive — UI requires a selection).
        let jlptLevel = levels.max() ?? snapshot.jlptLevel
        let pool = await vocabularyPool(level: jlptLevel)
        let clozes = await grammarClozePool(level: jlptLevel)

        return StudyCustomPlan(
            sessionQueue: srsCards,
            sessionExercises: exercises,
            endPolicy: SessionEndPolicy(
                durationBudgetMinutes: duration,
                queueLength: exercises.count
            ),
            jlptLevel: jlptLevel,
            vocabularyPool: pool,
            grammarClozes: clozes,
            srsCardCount: srsCards.count,
            estimatedDurationMinutes: plan.estimatedDurationMinutes
                + Self.minutes(fromSeconds: scheduled.addedDurationSeconds),
            cardsNeedingPresentation: scheduled.cardsNeedingPresentation
        )
    }

    // MARK: - Review Mistakes (startReviewMistakes)

    struct ReviewMistakesPlan {
        let sessionQueue: [CardDTO]
        let sessionExercises: [ExerciseItem]
        /// Flat (non-maturity-modulated) estimate — review-mistakes never
        /// went through the planner's maturity budgeting, so this preserves
        /// the pre-existing behavior rather than introducing a new model.
        let estimatedDurationMinutes: Int
    }

    /// Restarts the session with only the cards graded `.again` in the
    /// previous session. Returns nil if the missed-set (or the resolved card
    /// list) is empty, matching the original's early-return guards.
    ///
    /// No new-card presentation pass here by construction: every card in
    /// `missedCardIDs` was already graded `.again` in a prior session, so
    /// `fsrsState.reps` is always > 0 — `NewCardPresentationScheduler`'s
    /// `reps == 0` gate would never fire on this set anyway.
    func composeReviewMistakes(missedCardIDs: Set<UUID>) async -> ReviewMistakesPlan? {
        guard !missedCardIDs.isEmpty else { return nil }
        let allCards = await cardRepository.allCards()
        let mistakes = allCards.filter { missedCardIDs.contains($0.id) }
        guard !mistakes.isEmpty else { return nil }
        let exercises = mistakes.map { ExerciseItem.srsReview($0) }
        let totalSeconds = exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }
        return ReviewMistakesPlan(
            sessionQueue: mistakes,
            sessionExercises: exercises,
            estimatedDurationMinutes: Self.minutes(fromSeconds: totalSeconds)
        )
    }

    // MARK: - Vocabulary Pool

    /// Loads and maps the session vocabulary pool for the audio drills
    /// (Shadowing / Listening). Returns an empty pool when no
    /// `ContentRepository` was injected (previews / tests) — never throws,
    /// never blocks the session start on a failed content read.
    /// Les exercices de grammaire a trou du niveau. Meme forme que
    /// `vocabularyPool` : charge une fois a la composition, lu au rendu.
    func grammarClozePool(level: JLPTLevel) async -> [GrammarCloze] {
        guard let contentRepository else { return [] }
        let clozes = await contentRepository.grammarClozes(for: level)
        Logger.ui.info(
            "session.grammarClozes level=\(level.rawValue, privacy: .public) count=\(clozes.count, privacy: .public)"
        )
        return clozes
    }

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

    // MARK: - Duration Helper

    /// Whole minutes from a seconds total, floored (matches
    /// `DefaultSessionPlanner.finalize`'s `max(0, secs / 60)` so the
    /// app-layer estimate stays consistent with the planner's own rounding).
    fileprivate static func minutes(fromSeconds seconds: Int) -> Int {
        max(0, seconds / 60)
    }
}

// MARK: - NewCardPresentationScheduler
//
// Ensures every never-reviewed KANA card in a composed exercise list gets an
// ungraded "presentation" encounter before its first graded touch-and-reveal
// test, and that the graded test is delayed a few real recall events later
// rather than sitting immediately behind the intro. This is the fix for the
// pedagogy review's "erreur de conception #1": touching a card to reveal a
// character nobody has ever taught, and grading that guess, produces a first
// FSRS note that is noise, not signal — the guard-rail `reps >= 2` on
// `MasteryLevel` exists precisely because a first grade can't be trusted.
//
// Deliberately reuses the EXISTING `.srsReview` case for both the intro and
// the delayed test — no new `ExerciseItem` case. `DefaultSessionPlanner`'s
// `isLive(_:)` switch is an intentionally exhaustive checklist over every
// `ExerciseItem` case (see that switch's own doc comment) that this pass is
// forbidden from touching; adding a case here would break that file's build.
// `SessionViewModel.cardsNeedingPresentation` (a `Set<UUID>`, not the
// `ExerciseItem` payload) is what actually distinguishes the intro
// occurrence of a card from its later, graded occurrence.
//
// Scoped to kana specifically (`card.isKana`), matching the review's
// concrete scenario ("un lot de nouveaux kana") and the existing
// `ikeru.audio.autoplay` autoplay pattern this reuses (already kana-gated in
// `SRSCardView`). Extending the same treatment to first-ever kanji /
// vocabulary / grammar cards is a plausible follow-up but a distinct design
// decision (those already get their own dedicated study surfaces, e.g.
// `.kanjiStudy`) — left out of this pass rather than guessed at.
enum NewCardPresentationScheduler {

    struct Result {
        let exercises: [ExerciseItem]
        /// Ids of cards whose FIRST occurrence in `exercises` is the
        /// ungraded presentation pass. `SessionViewModel` seeds its
        /// `cardsNeedingPresentation` from this at session start.
        let cardsNeedingPresentation: Set<UUID>
        /// Extra `estimatedDurationSeconds` contributed by the duplicated
        /// `.srsReview` occurrences (the delayed tests) — additive on top
        /// of `SessionPlan.estimatedDurationMinutes`, which was computed
        /// from the ORIGINAL (pre-duplication) exercise list.
        let addedDurationSeconds: Int
    }

    /// How many exercises the task's pedagogy review asks for ("2 a 4
    /// cartes plus loin") — but counted in `.srsReview` OCCURRENCES passed,
    /// not raw array positions. See the collision note below.
    private static let defaultOffsetRange: ClosedRange<Int> = 2...4

    /// Smallest number of `.srsReview` occurrences that must follow a
    /// presentation for its delayed test to be worth scheduling. Below this the
    /// card is not deferred at all — see the guard in `schedulingPresentations`.
    ///
    /// It matches `defaultOffsetRange.lowerBound` on purpose: the test lands
    /// just after `target` occurrences have passed, so the resulting gap is
    /// `target + 1`. Requiring 2 available therefore guarantees a gap of at
    /// least 3 — exactly what keeps the two occurrences of the same card id
    /// outside the deck's 3-deep peek window.
    private static let minimumSRSGap = defaultOffsetRange.lowerBound

    static func schedulingPresentations(
        for exercises: [ExerciseItem],
        offsetRange: ClosedRange<Int> = defaultOffsetRange
    ) -> Result {
        var seen = Set<UUID>()
        var deferred: [(sourceIndex: Int, card: CardDTO)] = []

        for (index, item) in exercises.enumerated() {
            guard case .srsReview(let card) = item,
                  card.fsrsState.reps == 0,
                  card.isKana,
                  !seen.contains(card.id) else { continue }
            seen.insert(card.id)
            deferred.append((index, card))
        }

        guard !deferred.isEmpty else {
            return Result(exercises: exercises, cardsNeedingPresentation: [], addedDurationSeconds: 0)
        }

        var working = exercises
        var addedSeconds = 0
        var presenting = seen

        // Reverse source-index order: inserting a later item first never
        // shifts an earlier, not-yet-processed item's recorded sourceIndex.
        for (sourceIndex, card) in deferred.sorted(by: { $0.sourceIndex > $1.sourceIndex }) {
            // The whole point of deferring is interference: the delayed test
            // only measures retention if other recalls happened in between.
            // Near the end of a session the tail may be too short to provide
            // that gap — and appending at the end would then place the test
            // immediately after its own presentation, which measures nothing
            // AND puts two occurrences of the same card id inside the deck's
            // 3-deep peek window (duplicate matchedGeometryEffect id).
            //
            // Quand l'écart n'est pas atteignable, on renonce au TEST DIFFÉRÉ —
            // jamais à la présentation (OBS2-001, BLOQUANT n° 1).
            //
            // Ce bloc retirait auparavant la carte de `presenting`, ce qui
            // faisait retomber son unique occurrence sur « une révision notée
            // normale ». En clair : l'apprenant était INTERROGÉ sur un
            // caractère que personne ne lui avait montré, et sa réponse — un
            // pur hasard — devenait sa première note FSRS.
            //
            // C'est mesuré : sur une première séance de 5 kana choisis et rien
            // d'autre, les cartes de queue n'ont pas 2 occurrences après elles,
            // donc 2 des 5 n'étaient jamais présentées. Le « 56 % de rappel »
            // affiché en fin de séance mesurait alors de la non-présentation,
            // pas de l'oubli.
            //
            // La dégradation acceptable est l'inverse : la carte est
            // PRÉSENTÉE, et son test attendra la séance suivante. On perd une
            // note ; on ne fabrique pas une note fausse sur un caractère
            // jamais enseigné. Le test différé n'est pas la fonctionnalité —
            // la rencontre l'est.
            //
            // Reste la contrainte qui motivait le renoncement : appender le
            // test en fin de liste placerait deux occurrences du même id dans
            // la fenêtre de 3 cartes du deck (`matchedGeometryEffect`
            // dupliqué). On ne l'insère donc toujours pas — on garde
            // simplement la présentation.
            let available = srsReviewCount(after: sourceIndex, in: working)
            guard available >= minimumSRSGap else { continue }

            let target = min(Int.random(in: offsetRange), available)
            let insertAt = insertionIndex(
                after: sourceIndex,
                skippingSRSReviews: target,
                in: working
            )
            let testItem = ExerciseItem.srsReview(card)
            working.insert(testItem, at: insertAt)
            addedSeconds += testItem.estimatedDurationSeconds
        }

        return Result(
            exercises: working,
            cardsNeedingPresentation: presenting,
            addedDurationSeconds: addedSeconds
        )
    }

    /// Finds the array index right after `target` MORE `.srsReview`
    /// occurrences have appeared past `sourceIndex` (i.e. the intro's own
    /// slot doesn't count). Counting `.srsReview` occurrences instead of raw
    /// array positions guarantees a minimum QUEUE-position gap of
    /// `target + 1` between the intro and its delayed test — for `target >=
    /// 2` that gap (>= 3) is provably outside `SessionViewModel`'s 3-deep
    /// peek window (`upcomingCards`): the set of `currentIndex` values that
    /// can show the intro in-peek and the set that can show the test in-peek
    /// are disjoint whenever the gap is >= 3, so the two occurrences of the
    /// SAME `card.id` can never render simultaneously in `SRSCardView`'s
    /// peek `ForEach`/`matchedGeometryEffect`. Counting raw array positions
    /// instead (offsets of 2-4 INCLUDING non-`.srsReview` drills) would not
    /// guarantee this — a session with sparse review density between the
    /// intro and its test could land the delayed test within that window.
    /// Falls back to appending at the end if fewer than `target`
    /// `.srsReview` items remain in the tail.
    /// How many `.srsReview` occurrences follow `sourceIndex`. Used to decide
    /// whether a meaningful gap is achievable before committing to defer.
    private static func srsReviewCount(after sourceIndex: Int, in exercises: [ExerciseItem]) -> Int {
        var count = 0
        var i = sourceIndex + 1
        while i < exercises.count {
            if case .srsReview = exercises[i] { count += 1 }
            i += 1
        }
        return count
    }

    private static func insertionIndex(
        after sourceIndex: Int,
        skippingSRSReviews target: Int,
        in exercises: [ExerciseItem]
    ) -> Int {
        var passed = 0
        var i = sourceIndex + 1
        while i < exercises.count {
            if case .srsReview = exercises[i] {
                passed += 1
                if passed == target { return i + 1 }
            }
            i += 1
        }
        return exercises.count
    }
}
