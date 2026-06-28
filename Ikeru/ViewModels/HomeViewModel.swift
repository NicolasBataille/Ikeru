import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - HomeViewModel

@MainActor
@Observable
public final class HomeViewModel {

    // MARK: - Exposed State

    /// Display name from user profile.
    public private(set) var displayName: String = ""

    /// Current RPG level.
    public private(set) var level: Int = 1

    /// Current total XP.
    public private(set) var xp: Int = 0

    /// XP required to reach the next level.
    public private(set) var xpForNextLevel: Int = 100

    /// Number of cards currently due for review.
    public private(set) var dueCardCount: Int = 0

    /// Number of kanji cards the user has learned (reviewed at least once).
    public private(set) var kanjiLearnedCount: Int = 0

    /// Estimated card count for the next session preview.
    public private(set) var sessionPreviewCardCount: Int = 0

    /// Estimated time in minutes for the next session.
    public private(set) var sessionPreviewMinutes: Int = 0

    /// Recent achievement text (e.g., "Unlocked Listening!").
    public private(set) var recentAchievement: String?

    /// Number of unopened lootboxes.
    public private(set) var unopenedLootBoxCount: Int = 0

    /// Skill balance snapshot for the home radar card.
    public private(set) var skillBalance: SkillBalanceSnapshot = SkillBalanceSnapshot()

    /// Estimated number of new cards in the next session.
    public private(set) var sessionPreviewNewCount: Int = 0

    /// Estimated number of review cards in the next session.
    public private(set) var sessionPreviewReviewCount: Int = 0

    /// Kana mastery (familiar+), for the calm "X/92" progress line on Home.
    public private(set) var kanaProgress: KanaProgress =
        KanaProgress(hiraganaMastered: 0, katakanaMastered: 0)

    /// Whether Home should invite the learner to choose a kana study set before
    /// practising (the soft "choose your kana" gate). True only for a fresh
    /// learner who hasn't chosen a set and has no kana cards yet — so Practice
    /// always reflects what they actually picked, never auto-seeded katakana.
    public private(set) var needsStudySetChoice: Bool = false

    /// The single calm "do this next" suggestion (first unmet rung of the
    /// learning ladder). nil until the first load. Surfaced once the learner has
    /// started (not while the choose-your-kana gate is up).
    public private(set) var nextStep: NextStep?

    /// The honest mix of today's composed session — drives the hero label so it
    /// can't claim "À RÉVISER" while the breakdown is all-new (or vice versa).
    public enum TodayKind: Sendable { case empty, allNew, allReview, mixed }

    /// The number shown in the Home hero: the *actual* composed session size
    /// (`sessionPreviewCardCount`), so the headline always equals new + review.
    public var todayCount: Int { sessionPreviewCardCount }

    public var todayKind: TodayKind {
        if sessionPreviewCardCount == 0 { return .empty }
        if sessionPreviewReviewCount == 0 { return .allNew }
        if sessionPreviewNewCount == 0 { return .allReview }
        return .mixed
    }

    /// XP earned so far within the current level (0 ≤ value < xpForLevel(level)).
    public var xpInCurrentLevel: Int {
        RPGConstants.progressInLevel(totalXP: xp).current
    }

    /// XP required to complete the current level.
    public var xpRequiredForLevel: Int {
        RPGConstants.progressInLevel(totalXP: xp).required
    }

    /// XP remaining to reach the next rank.
    public var xpToNextLevel: Int {
        max(0, xpRequiredForLevel - xpInCurrentLevel)
    }

    /// Whether data has been loaded at least once.
    public private(set) var hasLoaded: Bool = false

    /// Re-entry guard. `loadData` is invoked from both `.task` and `.onAppear`
    /// on Home, which fire together on first appear — without this, two
    /// concurrent runs could race the study-set gate and the preview compose.
    private var isLoadingData = false

    /// Whether Home should show 「今日は休 / Rest day」 instead of the
    /// session CTA. Driven by `RestDayDetector.shouldShowRestDay(...)`.
    /// Refreshed by `refreshRestDay()` whenever the Home view appears.
    public private(set) var restDayActive: Bool = false

    // MARK: - Computed

    /// Whether there are cards ready to review.
    public var hasCardsDue: Bool {
        dueCardCount > 0
    }

    /// Greeting text based on current state.
    public var greetingText: String {
        if !displayName.isEmpty {
            return "Welcome, \(displayName)!"
        }
        return "Welcome!"
    }

    /// Summary text for the learning card.
    public var learningSummaryText: String {
        if dueCardCount == 0 && hasLoaded {
            return "All caught up!"
        }
        var parts: [String] = []
        if dueCardCount > 0 {
            parts.append("\(dueCardCount) cards ready")
        }
        if kanjiLearnedCount > 0 {
            parts.append("\(kanjiLearnedCount) kanji learned")
        }
        if parts.isEmpty {
            return "Start learning to see your progress"
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Session preview description text.
    public var sessionPreviewText: String {
        if sessionPreviewCardCount > 0 {
            return "~\(sessionPreviewMinutes) min \u{00B7} \(sessionPreviewCardCount) reviews"
        }
        return "Start a session to begin learning"
    }

    // MARK: - Dependencies

    private let modelContainer: ModelContainer
    private let cardRepository: CardRepository
    private let plannerService: PlannerService
    private let progressService: ProgressService
    /// Canonical planner — same instance type as `SessionViewModel` uses,
    /// so the preview counts always match what `startSession()` will serve.
    private let sessionPlanner: DefaultSessionPlanner

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let repo = CardRepository(modelContainer: modelContainer)
        self.cardRepository = repo
        self.plannerService = PlannerService(cardRepository: repo)
        self.progressService = ProgressService(cardRepository: repo)
        self.sessionPlanner = DefaultSessionPlanner()
    }

    /// Initializer for testing with injected dependencies.
    public init(
        modelContainer: ModelContainer,
        cardRepository: CardRepository,
        plannerService: PlannerService
    ) {
        self.modelContainer = modelContainer
        self.cardRepository = cardRepository
        self.plannerService = plannerService
        self.progressService = ProgressService(cardRepository: cardRepository)
        self.sessionPlanner = DefaultSessionPlanner()
    }

    // MARK: - Rest Day

    /// Re-evaluates whether Home should show the 「今日は休 / Rest day」
    /// state. Composes a `LearnerSnapshot` from current cards + active
    /// `RPGState.lastSessionDate`, and runs it through `RestDayDetector`.
    /// Call from `HomeView`'s `.task` modifier.
    public func refreshRestDay() async {
        let cards = await cardRepository.allCards()
        let context = modelContainer.mainContext
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: context)?.lastSessionDate
        let balances: [SkillType: Double] = [
            .reading:   skillBalance.reading,
            .listening: skillBalance.listening,
            .writing:   skillBalance.writing,
            .speaking:  skillBalance.speaking,
        ]
        let snapshot = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: balances,
            dueCardCount: cards.filter { $0.dueDate <= Date() }.count,
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession
        )
        restDayActive = RestDayDetector.shouldShowRestDay(profile: snapshot, now: Date())
        Logger.rpg.info("restDay.\(self.restDayActive ? "shown" : "hidden", privacy: .public)")
    }

    // MARK: - Data Loading

    /// Snapshot of the competence signals used by the
    /// `DisplayModeAdvancedThresholdMonitor` to decide whether the
    /// "you're ready for Tatami" suggestion card should appear.
    /// Streak is no longer included: eligibility is based on cumulative
    /// competence only (reviews volume + mastery depth), not daily-login pressure.
    public struct AdvancedThresholdSignals: Sendable {
        public let reviews: Int
        public let mastery: Int
    }

    /// Returns the current threshold signals for the active profile.
    /// Reads `RPGState` for total reviews and the card repository
    /// for the mastered-card count. Safe to call on the main actor.
    public func advancedThresholdSignals() async -> AdvancedThresholdSignals {
        let context = modelContainer.mainContext
        let rpg = ActiveProfileResolver.fetchActiveRPGState(in: context)
        let reviews = rpg?.totalReviewsCompleted ?? 0
        let allCards = await cardRepository.allCards()
        let masteryCount = allCards.filter { card in
            MasteryLevel.from(fsrsState: card.fsrsState).rawValue
                >= MasteryLevel.familiar.rawValue
        }.count
        return AdvancedThresholdSignals(
            reviews: reviews,
            mastery: masteryCount
        )
    }

    // MARK: - Post-Session Refresh

    /// Must be called by the presentation layer when the session sheet is
    /// dismissed (e.g. SessionSummaryView's "Done" button or the sheet's
    /// `onDismiss` closure). Forces a full data reload so the XP rail and
    /// due-card hero count reflect the just-persisted session results
    /// without waiting for the user to navigate away from and back to Home.
    public func refreshAfterSession() async {
        await loadData()
    }

    /// Loads all home screen data from local SwiftData.
    /// Called on .onAppear to refresh after session completion.
    public func loadData() async {
        // Serialize overlapping loads (see `isLoadingData`): the first call runs
        // the full load; a concurrent second one returns rather than racing the
        // seed. Sequential calls (e.g. refresh-on-return) are unaffected.
        if isLoadingData { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        await loadProfile()
        // Decide whether to invite the learner to choose their kana first. We
        // no longer auto-seed あいうえお on appear: Practice should reflect the
        // learner's explicit choice (issue E), so a fresh user is guided to the
        // chooser instead of silently receiving cards.
        await refreshStudySetGate()
        await loadRPGState()
        await loadDueCardCount()
        await loadKanjiLearnedCount()
        await loadKanaProgress()
        await loadNextStep()
        await composeSessionPreview()
        await loadSkillBalance()

        hasLoaded = true

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.ui.info("Home screen data loaded in \(elapsed, format: .fixed(precision: 1))ms")
    }

    // MARK: - Private Loading

    private func loadProfile() async {
        let context = modelContainer.mainContext
        displayName = ActiveProfileResolver.fetchActiveProfile(in: context)?.displayName ?? ""
    }

    /// Decides whether Home should show the soft "choose your kana" gate.
    /// True only for a fresh learner: one who has neither confirmed a study set
    /// nor accumulated any kana cards. Existing users (who already have cards)
    /// are grandfathered straight into Practice, so this change is invisible to
    /// them. Once the learner confirms a set in the chooser, `hasChosenStudySet`
    /// flips and this returns false.
    private func refreshStudySetGate() async {
        if StudySetStore.hasChosenStudySet {
            needsStudySetChoice = false
            return
        }
        let hasKanaCards = (await cardRepository.allCards()).contains { $0.isKana }
        needsStudySetChoice = !hasKanaCards
    }

    private func loadRPGState() async {
        let context = modelContainer.mainContext

        if let state = ActiveProfileResolver.fetchActiveRPGState(in: context) {
            xp = state.xp
            // Always derive level from the canonical XP value so that a profile
            // seeded (or otherwise written) with a stale RPGState.level field
            // still displays the correct rank everywhere. If the computed level
            // differs from the stored one we repair it in-place so future reads
            // are consistent without needing another derivation pass.
            let derivedLevel = RPGConstants.levelForXP(state.xp)
            if derivedLevel != state.level {
                let staleLevel = state.level
                state.level = derivedLevel
                try? context.save()
                Logger.ui.info(
                    "Home: repaired stale RPGState.level \(staleLevel) → \(derivedLevel) for xp=\(state.xp)"
                )
            }
            level = derivedLevel
            unopenedLootBoxCount = state.unopenedLootBoxes.count
            EquippedCosmeticsBridge.sync(state: state)

            // Compute recent achievement from last inventory item
            let inventory = state.lootInventory
            if let lastItem = inventory.last {
                recentAchievement = lastItem.name
            } else {
                // Check for recently unlocked attributes
                let attrs = state.attributes
                if let lastAttr = attrs.last {
                    recentAchievement = "Unlocked \(lastAttr.name)!"
                } else {
                    recentAchievement = nil
                }
            }
        } else {
            xp = 0
            level = 1
            recentAchievement = nil
            unopenedLootBoxCount = 0
        }

        xpForNextLevel = RPGConstants.xpForLevel(level)
        Logger.ui.debug("Home RPG state: level=\(self.level), xp=\(self.xp)")
    }

    private func loadDueCardCount() async {
        let dueCards = await cardRepository.dueCards(before: Date())
        dueCardCount = dueCards.count
    }

    private func loadKanjiLearnedCount() async {
        let allCards = await cardRepository.allCards()
        kanjiLearnedCount = allCards.filter { $0.fsrsState.reps > 0 }.count
    }

    private func loadKanaProgress() async {
        let allCards = await cardRepository.allCards()
        kanaProgress = KanaProgress.from(cards: allCards)
    }

    /// Computes the single "do this next" suggestion from a real snapshot of the
    /// learner's cards (kana per-character mastery + vocab/kanji familiar+).
    /// Grammar/listening signals aren't tracked yet, so they're passed as 0 —
    /// which is correct for a beginner whose realistic next step is always a
    /// kana or vocabulary rung.
    private func loadNextStep() async {
        let cards = await cardRepository.allCards()
        let snapshot = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: cards.contains { $0.fsrsState.reps == 0 },
            lastSessionAt: nil,
            now: Date()
        )
        let kana = KanaProgress.from(cards: cards)
        nextStep = NextStepRecommender.recommend(kana: kana, snapshot: snapshot)
    }

    /// Composes a session preview using the same `DefaultSessionPlanner`
    /// pipeline as `SessionViewModel.startSession()`.
    ///
    /// This guarantees that the hero count (SRS reviews) and the NEW/REVIEW
    /// breakdown displayed on Home are always consistent with what the user
    /// will actually see when they tap "Start". Previously the preview used
    /// the legacy `PlannerService.composeSession()` path (due cards + ≤5 new)
    /// while the real session used the 40/30/20/10 skeleton planner, which
    /// caused three different numbers to be displayed simultaneously.
    private func composeSessionPreview() async {
        let cards = await cardRepository.allCards()
        let durationMinutes = UserDefaults.standard.integer(forKey: "ikeru.session.defaultDurationMinutes")
        let effectiveDuration = durationMinutes > 0 ? durationMinutes : 15

        // Build a minimal snapshot so the planner can size the segments.
        // Skill-balance fields default to empty (equal split) — sufficient
        // for computing how many SRS reviews fit in the review-wave budget.
        let unlockedTypes = Set(ExerciseType.allCases)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: effectiveDuration,
            profile: LearnerSnapshot(
                jlptLevel: .n5,
                vocabularyMasteredFamiliarPlus: 0,
                kanjiMasteredFamiliarPlus: 0,
                hiraganaMastered: false,
                katakanaMastered: false,
                grammarPointsFamiliarPlus: 0,
                listeningAccuracyLast30: 0,
                listeningRecallLast30Days: 0,
                skillBalances: [:],
                dueCardCount: cards.filter { $0.dueDate <= Date() }.count,
                hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
                lastSessionAt: nil
            ),
            unlockedTypes: unlockedTypes,
            availableCards: cards
        )
        let plan = await sessionPlanner.compose(inputs: inputs)

        // sessionPreviewCardCount = SRS review items only (cards shown as
        // flashcards). Non-SRS exercises (kanji study tiles, variety tiles,
        // etc.) are not shown in the due-count hero so we don't inflate it.
        let srsItems = plan.exercises.filter {
            if case .srsReview = $0 { return true }
            return false
        }
        sessionPreviewCardCount = srsItems.count
        sessionPreviewMinutes = plan.estimatedDurationMinutes > 0 ? plan.estimatedDurationMinutes : 1

        // NEW vs REVIEW split within the SRS items only.
        // A card is "new" when reps == 0 (never answered); everything else
        // is a recurring review. This matches the breakdown in the session
        // summary and the SessionViewModel's `newItemsLearned` counter.
        var newCount = 0
        var reviewCount = 0
        for item in srsItems {
            if case .srsReview(let card) = item {
                if card.fsrsState.reps == 0 {
                    newCount += 1
                } else {
                    reviewCount += 1
                }
            }
        }
        sessionPreviewNewCount = newCount
        sessionPreviewReviewCount = reviewCount
        Logger.ui.debug(
            "Session preview (planner): \(srsItems.count) SRS (\(newCount) new / \(reviewCount) review), ~\(self.sessionPreviewMinutes) min"
        )
    }

    private func loadSkillBalance() async {
        let data = await progressService.loadDashboardData()
        skillBalance = data.skillBalance
    }
}
