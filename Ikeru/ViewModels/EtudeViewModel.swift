import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - EtudeViewModel
//
// Backs the Étude tab (Practice library). Loads aggregate progress for the
// JLPT-estimate hero, exposes a `LearnerSnapshot` builder for the Browse
// grid / Compose row, and routes single-surface and custom-session starts
// through `DefaultSessionPlanner`.
//
// The four-winds skill-balance card that previously lived on this VM has
// moved to the RPG profile (Task 22) — `skillBalance` is intentionally
// not exposed here.

@MainActor
@Observable
final class EtudeViewModel {

    // MARK: - Exposed State

    /// Estimated JLPT level and mastery — feeds the hero panel.
    private(set) var jlptEstimate: JLPTEstimate = JLPTEstimate(
        level: "N5",
        masteryFraction: 0,
        masteredCount: 0,
        totalRequired: 100
    )

    /// Number of cards due right now.
    private(set) var dueNowCount: Int = 0

    /// Number of cards due today total.
    private(set) var dueTodayCount: Int = 0

    /// 7-day review forecast.
    private(set) var forecast: [ForecastEntry] = []

    /// Monthly progress snapshots (last 6 months).
    private(set) var monthlySnapshots: [MonthlySnapshot] = []

    /// Whether initial data load has completed.
    private(set) var hasLoaded: Bool = false

    /// Last `SessionPlan` produced by `startCustomSession(...)`. Exposed so
    /// the view (or tests) can observe planner output without coupling to
    /// the planner directly.
    public private(set) var lastComposedPlan: SessionPlan?

    // MARK: - Computed

    /// JLPT mastery as a display string (e.g., "N5: 42% mastered").
    var jlptDisplayText: String {
        let percent = Int(jlptEstimate.masteryFraction * 100)
        return "\(jlptEstimate.level): \(percent)% mastered"
    }

    /// Due now display text.
    var dueNowText: String {
        if dueNowCount == 0 {
            return "No cards due"
        }
        return "\(dueNowCount) card\(dueNowCount == 1 ? "" : "s") due now"
    }

    /// Due today display text.
    var dueTodayText: String {
        "\(dueTodayCount) due today"
    }

    /// Maximum value in the forecast (for chart scaling).
    var forecastMaxValue: Int {
        max(1, forecast.map(\.cardsDue).max() ?? 1)
    }

    /// Maximum cards mastered across monthly snapshots (for chart scaling).
    var monthlyMaxValue: Int {
        max(1, monthlySnapshots.map(\.cardsMastered).max() ?? 1)
    }

    // MARK: - Dependencies

    private let modelContainer: ModelContainer
    private let cardRepository: CardRepository
    private let progressService: ProgressService

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        let repo = CardRepository(modelContainer: modelContainer)
        self.modelContainer = modelContainer
        self.cardRepository = repo
        self.progressService = ProgressService(cardRepository: repo)
    }

    /// Initializer for testing with injected dependencies.
    init(
        modelContainer: ModelContainer,
        cardRepository: CardRepository,
        progressService: ProgressService
    ) {
        self.modelContainer = modelContainer
        self.cardRepository = cardRepository
        self.progressService = progressService
    }

    // MARK: - Data Loading

    /// Loads all dashboard data from `ProgressService`.
    func loadData() async {
        let data = await progressService.loadDashboardData()

        jlptEstimate = data.jlptEstimate
        dueNowCount = data.dueNowCount
        dueTodayCount = data.dueTodayCount
        forecast = data.forecast
        monthlySnapshots = data.monthlySnapshots
        hasLoaded = true

        Logger.ui.info("Etude dashboard loaded")
    }

    // MARK: - Session Routing

    /// Builds a fresh `LearnerSnapshot` from real cards + active RPG state.
    /// Used by the Browse grid and `startCustomSession(...)`.
    public func buildSnapshot() async -> LearnerSnapshot {
        let cards = await cardRepository.allCards()
        let progressService = ProgressService(cardRepository: cardRepository)
        let progress = await progressService.loadDashboardData(now: Date())
        let jlpt = JLPTLevel(rawValue: progress.jlptEstimate.level.lowercased()) ?? .n5
        let lastSession = ActiveProfileResolver
            .fetchActiveRPGState(in: modelContainer.mainContext)?.lastSessionDate
        return LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: jlpt,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: cards.contains(where: { $0.fsrsState.reps == 0 }),
            lastSessionAt: lastSession,
            now: Date()
        )
    }

    /// Tap-through from a single Étude tile. Logs intent; the full
    /// drill-launch wiring is added in a later task.
    public func startSingleSurface(type: ExerciseType) {
        Logger.planner.info("Etude → drill type=\(type.rawValue, privacy: .public)")
    }

    /// Compose a custom session from the Étude planner sheet.
    public func startCustomSession(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) {
        Logger.planner.info("Etude → custom session types=\(types.count, privacy: .public) levels=\(levels.count, privacy: .public)")
        Task {
            let snapshot = await buildSnapshot()
            let cards = await cardRepository.allCards()
            let unlocked = DefaultExerciseUnlockService().unlockedTypes(profile: snapshot)
            let inputs = SessionPlannerInputs(
                source: .studyCustom(types: types, jlptLevels: levels),
                durationMinutes: duration,
                profile: snapshot,
                unlockedTypes: unlocked,
                availableCards: cards
            )
            self.lastComposedPlan = await DefaultSessionPlanner().compose(inputs: inputs)
        }
    }
}
