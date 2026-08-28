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
    ///
    /// Deliberately NOT surfaced anywhere in `HomeView`, including the new
    /// competency-booklet mirror (`masteryBook`) — decision taken in the
    /// 2026-08-10 review's "RPG orphelin" item (#25). Still computed because
    /// the widget target reads `RPGState` independently (App Group, outside
    /// this work item's file perimeter) and because retiring the underlying
    /// XP/loot pipeline is a bigger call than one review pass. Reasons kept
    /// out of the UI:
    /// 1. The XP economy still pays hidden streak bonuses
    ///    (`RPGConstants.fiveDayStreakBonus`, `.thirtyDayStreakBonus`,
    ///    `.firstSessionOfDayBonus`) — exactly the pressure the product
    ///    deliberately removed ("zero streak, zero ligue"). Showing "Lv. 4"
    ///    would re-import that pressure wearing a different label, and an
    ///    "effort" framing doesn't fix that the effort curve is secretly
    ///    streak-shaped.
    /// 2. It's redundant with what the booklet already shows: `masteryBook`
    ///    tells the learner exactly what became familiar/mastered, which is
    ///    legible and auditable. A level number the learner can't decompose
    ///    ("why am I level 4 and not 5?") adds opacity, not signal.
    /// 3. It wouldn't actually fix the orphan problem — the widget already
    ///    shows "Lv. N" with zero context; duplicating that number on Home
    ///    just adds a second unexplained instance of the same defect.
    public private(set) var level: Int = 1

    /// Current total XP. See `level`'s doc comment for why this stays out of
    /// the new competency-booklet UI.
    public private(set) var xp: Int = 0

    /// XP required to reach the next level.
    public private(set) var xpForNextLevel: Int = 100

    /// Number of cards currently due for review.
    public private(set) var dueCardCount: Int = 0

    /// Number of kanji cards the user has learned (reviewed at least once).
    public private(set) var kanjiLearnedCount: Int = 0

    /// **Not** the lifetime review count shown anywhere to the learner —
    /// despite the name, this mirrors `RPGState.totalReviewsCompleted`
    /// verbatim (see that field's doc comment for why it's non-authoritative
    /// as of GAP-13, and for the full list of what writes it), kept exactly
    /// as-is on purpose: Home only reads it (before vs. after a session) to
    /// detect a "has this profile's session/Watch counter moved past 0" 0 →
    /// >0 transition, which drives the one-time daily-term prompt. This is
    /// an approximation, not a precise "first session" signal even today —
    /// e.g. a Watch quiz result can also move it — but re-deriving it from
    /// `ReviewLog` (like `advancedThresholdSignals()` now does for the
    /// Tatami gate) would make it strictly worse for the common case: any
    /// learner who did a kana drill before their first session (a very
    /// likely order) would walk into that first session with the derived
    /// count already >0, so the prompt would never fire for them at all.
    /// Any DISPLAY of a lifetime review count must go through
    /// `CardRepository.activeProfileReviewCount()`.
    public private(set) var totalReviewsCompleted: Int = 0

    /// The lifetime review count derived from `ReviewLog` — the honest one.
    ///
    /// Exists alongside `totalReviewsCompleted` above because the two answer
    /// genuinely different questions, and collapsing them would break one of
    /// the two callers:
    ///
    /// - a **transition** (`0` → `>0` across one session) wants the RPG
    ///   counter, for the reason spelled out above: a learner who drilled
    ///   kana before their first session would already be `>0` here, so the
    ///   one-time prompt keyed on it would never fire for them;
    /// - a **threshold** (`> 0`, "has this learner ever reviewed anything")
    ///   wants this one. On the RPG counter the answer is wrong for exactly
    ///   the learner GAP-13 was about — kana-drill-only work journals
    ///   `ReviewLog` rows without ever touching `RPGState`, so they sit at
    ///   `0` forever.
    ///
    /// Concretely, the bug this closes: someone working only through
    /// Explore → Kana finishes their whole set, nothing is due, and the
    /// "all caught up" explainer written precisely for them never appears.
    public private(set) var derivedReviewCount: Int = 0

    /// Estimated card count for the next session preview.
    public private(set) var sessionPreviewCardCount: Int = 0

    /// Estimated time in minutes for the next session.
    public private(set) var sessionPreviewMinutes: Int = 0

    /// Which caught-up offers can actually produce a session right now.
    ///
    /// Drives the proposal shown when `todayKind == .empty`. Empty set means
    /// there is genuinely nothing left — every card mastered and no new
    /// content — which is the only case where "all caught up" should stay a
    /// full stop rather than an invitation.
    ///
    /// This is computed rather than assumed so the UI never renders a button
    /// that does nothing on tap. A silently inert control is the exact defect
    /// this proposal exists to remove.
    public private(set) var caughtUpOffers: Set<SessionPlannerInputs.CaughtUpOffer> = []

    /// Recent achievement text (e.g., "Unlocked Listening!").
    public private(set) var recentAchievement: String?

    /// Skill balance snapshot for the home radar card.
    public private(set) var skillBalance: SkillBalanceSnapshot = SkillBalanceSnapshot()

    /// Estimated number of new cards in the next session.
    public private(set) var sessionPreviewNewCount: Int = 0

    /// Estimated number of review cards in the next session.
    public private(set) var sessionPreviewReviewCount: Int = 0

    /// Kana mastery (familiar+), for the calm "X/92" progress line on Home.
    public private(set) var kanaProgress: KanaProgress =
        KanaProgress(hiraganaMastered: 0, katakanaMastered: 0)

    /// Aggregate mastery-level counts across kana cards + the personal
    /// vocabulary dictionary — the "livret de compétence" (competency
    /// booklet) mirror. See `MasteryBookCounts`'s doc comment and the
    /// 2026-08-10 review (erreur de conception #4 — "tu as enlevé le fouet
    /// sans installer le miroir").
    public private(set) var masteryBook: MasteryBookCounts = MasteryBookCounts()

    /// Net change in `masteryBook.knownCount` (familiar-or-better) since the
    /// current weekly baseline, or nil when no baseline exists yet at all
    /// (this profile's first-ever Home load). The baseline itself rolls
    /// forward only once a full week has passed — see
    /// `MasteryBookSnapshotStore`'s doc comment — so this delta stays
    /// visible for the whole week, not just a single load. Persisted in
    /// UserDefaults, no SwiftData schema involved.
    public private(set) var masteryBookWeeklyDelta: Int?

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
    /// Feeds the vocabulary half of `masteryBook` — the personal dictionary
    /// is a separate SwiftData model from `Card`, so it needs its own
    /// repository (mirrors how `VocabularyDictionaryViewModel` reads it).
    private let vocabularyRepository: VocabularyRepository
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
        self.vocabularyRepository = VocabularyRepository(modelContainer: modelContainer)
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
        self.vocabularyRepository = VocabularyRepository(modelContainer: modelContainer)
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
        let snapshot = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: skillBalance.asSkillBalances,
            dueCardCount: cards.filter { $0.dueDate <= Date() }.count,
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession
        )
        restDayActive = RestDayDetector.shouldShowRestDay(profile: snapshot, now: Date())
        Logger.rpg.info("restDay.\(self.restDayActive ? "shown" : "hidden", privacy: .public)")
    }

    // MARK: - Data Loading

    /// Snapshot of the signals used by the
    /// `DisplayModeAdvancedThresholdMonitor` to decide whether the
    /// "you're ready for Tatami" suggestion should appear. Eligibility is
    /// `(reviews AND mastery) OR (activeDays)` — no daily-streak gate.
    public struct AdvancedThresholdSignals: Sendable {
        public let reviews: Int
        public let mastery: Int
        public let activeDays: Int

        public init(reviews: Int, mastery: Int, activeDays: Int) {
            self.reviews = reviews
            self.mastery = mastery
            self.activeDays = activeDays
        }

        /// Runs the signals through `DisplayModeAdvancedThresholdMonitor`.
        public var eligibility: DisplayModeThresholdResult {
            DisplayModeAdvancedThresholdMonitor.evaluate(
                totalReviewsCompleted: reviews,
                cardsAtFamiliarOrAbove: mastery,
                activeDaysCount: activeDays
            )
        }
    }

    /// Returns the current threshold signals for the active profile.
    /// Reviews come from `CardRepository.activeProfileReviewCount()` — the
    /// `ReviewLog`-derived, cross-surface count (GAP-13) — not from
    /// `RPGState.totalReviewsCompleted`, which only ever credited the main
    /// SRS session and undercounted kana-drill reviews. Active days still
    /// reads `RPGState` (that counter has no equivalent divergence — see its
    /// own doc comment). Safe to call on the main actor.
    ///
    /// **No production call site as of GAP-13 (2026-08).** This method is
    /// NOT the live Tatami-mode eligibility gate — `TatamiEligibilityRow`
    /// computes its own `reviews`/`mastery`/`activeDays` independently
    /// (see that file) rather than calling this one. It is kept (and its
    /// review source fixed alongside the rest of GAP-13) because it is
    /// public API on `HomeViewModel` and `IkeruCore/Tests` exercises the
    /// `DisplayModeAdvancedThresholdMonitor` logic it wraps directly — but
    /// wiring it into Home, or deleting it in favor of always going through
    /// `TatamiEligibilityRow`, is unresolved follow-up, not something this
    /// fix should be read as having shipped.
    public func advancedThresholdSignals() async -> AdvancedThresholdSignals {
        let context = modelContainer.mainContext
        let rpg = ActiveProfileResolver.fetchActiveRPGState(in: context)
        let reviews = await cardRepository.activeProfileReviewCount()
        let activeDays = rpg?.activeDaysCount ?? 0
        let allCards = await cardRepository.allCards()
        let masteryCount = allCards.filter { card in
            MasteryLevel.from(fsrsState: card.fsrsState).rawValue
                >= MasteryLevel.familiar.rawValue
        }.count
        return AdvancedThresholdSignals(
            reviews: reviews,
            mastery: masteryCount,
            activeDays: activeDays
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
        await loadDerivedReviewCount()
        await loadDueCardCount()
        await loadKanjiLearnedCount()
        await loadKanaProgress()
        await loadMasteryBook()
        // Skill balance must load BEFORE the snapshot consumers below
        // (`loadNextStep` / `composeSessionPreview` feed `skillBalance` into the
        // planner), otherwise they read the previous cycle's stale value.
        await loadSkillBalance()
        await loadNextStep()
        await composeSessionPreview()

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
    /// nor actually STUDIED any kana. The card check demands review evidence
    /// (`lastReview`/`reps`), not mere existence — merely opening the chooser
    /// used to seed the default selection's cards, and those phantom, never-
    /// reviewed cards silently dismissed this gate. Existing users are still
    /// grandfathered straight into Practice: their kana cards carry real
    /// review history. Once the learner confirms a set in the chooser,
    /// `hasChosenStudySet` flips and this returns false.
    private func refreshStudySetGate() async {
        if StudySetStore.hasChosenStudySet {
            needsStudySetChoice = false
            return
        }
        let hasStudiedKana = (await cardRepository.allCards()).contains {
            $0.isKana && ($0.fsrsState.lastReview != nil || $0.fsrsState.reps > 0)
        }
        needsStudySetChoice = !hasStudiedKana
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
            totalReviewsCompleted = state.totalReviewsCompleted
            EquippedCosmeticsBridge.sync(state: state)

            // Compute recent achievement from recently unlocked attributes.
            // Previously fell back to the last loot-inventory item first —
            // dropped with the loot pipeline retirement (2026-07-15) since no
            // new loot can be earned; attribute unlocks are the sole signal now.
            let attrs = state.attributes
            if let lastAttr = attrs.last {
                recentAchievement = "Unlocked \(lastAttr.name)!"
            } else {
                recentAchievement = nil
            }
        } else {
            xp = 0
            level = 1
            recentAchievement = nil
            totalReviewsCompleted = 0
        }

        xpForNextLevel = RPGConstants.xpForLevel(level)
        Logger.ui.debug("Home RPG state: level=\(self.level), xp=\(self.xp)")
    }

    private func loadDueCardCount() async {
        let dueCards = await cardRepository.dueCards(before: Date())
        dueCardCount = dueCards.count
    }

    /// Refreshes `derivedReviewCount` from `ReviewLog`. A pure read, no
    /// cache — the same source `TatamiEligibilityRow` uses, so the two can
    /// never drift apart the way the hand-incremented counter did.
    private func loadDerivedReviewCount() async {
        derivedReviewCount = await cardRepository.activeProfileReviewCount()
    }

    private func loadKanjiLearnedCount() async {
        let allCards = await cardRepository.allCards()
        kanjiLearnedCount = allCards.filter { $0.fsrsState.reps > 0 }.count
    }

    private func loadKanaProgress() async {
        let allCards = await cardRepository.allCards()
        kanaProgress = KanaProgress.from(cards: allCards)
    }

    /// Loads the competency-booklet mirror: combines SRS card mastery (kana
    /// today) with the personal vocabulary dictionary, then diffs against a
    /// week-old UserDefaults baseline (`MasteryBookSnapshotStore`) for the
    /// weekly delta. No SwiftData schema involved — see the store's doc
    /// comment for why a schema-backed history table isn't used here.
    private func loadMasteryBook() async {
        let cards = await cardRepository.allCards()
        // Guard the vocabulary fetch on the container actually carrying the
        // `VocabularyEntry` entity. Production's schema always does
        // (`IkeruSchema`), but a caller can construct `HomeViewModel` with a
        // narrower `ModelContainer` (e.g. a test schema listing only
        // `UserProfile`/`Card`/`ReviewLog`/`RPGState`) — fetching an entity
        // absent from the container's schema is a programmer-error case
        // SwiftData is not guaranteed to fail gracefully on, so this is
        // checked ahead of the fetch rather than merely wrapped in `try?`.
        let vocabModelIsRegistered = modelContainer.schema.entities.contains { $0.name == "VocabularyEntry" }
        let vocabEntries: [VocabularyEntryDTO]
        if vocabModelIsRegistered {
            vocabEntries = await vocabularyRepository.allEntries()
        } else {
            vocabEntries = []
        }
        let counts = MasteryBookCounts.from(cards: cards) + MasteryBookCounts.from(vocabularyEntries: vocabEntries)
        masteryBook = counts

        guard let profileID = ActiveProfileResolver.activeProfileID() else {
            masteryBookWeeklyDelta = nil
            return
        }
        masteryBookWeeklyDelta = MasteryBookSnapshotStore
            .priorSnapshot(profileID: profileID)
            .map { counts.delta(from: $0) }
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts)
    }

    /// Computes the single "do this next" suggestion from a real snapshot of the
    /// learner's cards (kana per-character mastery + vocab/kanji/grammar
    /// familiar+, all derived by the builder). Listening accuracy still has no
    /// source on this path, so it stays 0 — correct for a beginner whose
    /// realistic next step is always a kana or vocabulary rung.
    private func loadNextStep() async {
        let cards = await cardRepository.allCards()
        let snapshot = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: skillBalance.asSkillBalances,
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

        // L'aperçu construit désormais le MÊME instantané que la séance réelle,
        // et le même ensemble déverrouillé.
        //
        // Il fabriquait auparavant un `LearnerSnapshot` rempli de zéros
        // (`hiraganaMastered: false`, tous les compteurs à 0) et se donnait
        // `Set(ExerciseType.allCases)` comme ensemble déverrouillé — c'est-à-dire
        // qu'il dimensionnait la séance sur des exercices que l'apprenant
        // n'avait pas débloqués. Le commentaire d'origine disait vouloir
        // « éviter la dérive de l'aperçu » ; c'est exactement ce qu'il
        // produisait. L'accueil annonçait « ~N min » pour une séance qui n'en
        // durerait pas autant.
        //
        // Trouvé le 2026-08-28 en faisant descendre `.writingPractice` au N5 :
        // un test d'aperçu est passé de 1 à 5 minutes alors que la séance réelle
        // n'aurait pas bougé, l'écriture n'étant pas déverrouillée pour ce
        // profil. La cause n'était pas le nouveau seuil, c'était l'aperçu.
        let snapshot = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: skillBalance.asSkillBalances,
            hasNewContentQueued: cards.contains { $0.fsrsState.reps == 0 },
            lastSessionAt: nil,
            now: Date()
        )
        // Même union que `SessionComposer.effectiveUnlockedTypes` : l'évaluation
        // vivante des seuils, plus les déverrouillages déjà acquis, qu'un profil
        // conserve même si ses compteurs redescendent.
        let acknowledged = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?
            .acknowledgedUnlocks ?? []
        let unlockedTypes = DefaultExerciseUnlockService()
            .unlockedTypes(profile: snapshot)
            .union(acknowledged)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: effectiveDuration,
            profile: snapshot,
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

        // What can still be offered once there is nothing due. Computed from
        // the same `cards` snapshot the preview used, so the proposal and the
        // count it replaces can never disagree.
        caughtUpOffers = DefaultSessionPlanner.caughtUpAvailability(cards: cards)
        Logger.ui.debug(
            "Session preview (planner): \(srsItems.count) SRS (\(newCount) new / \(reviewCount) review), ~\(self.sessionPreviewMinutes) min"
        )
    }

    private func loadSkillBalance() async {
        let data = await progressService.loadDashboardData()
        skillBalance = data.skillBalance
    }
}
