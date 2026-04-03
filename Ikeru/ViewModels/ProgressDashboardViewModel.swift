import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - ProgressDashboardViewModel

@MainActor
@Observable
final class ProgressDashboardViewModel {

    // MARK: - Exposed State

    /// Skill balance for the radar chart.
    private(set) var skillBalance: SkillBalanceSnapshot = SkillBalanceSnapshot()

    /// Estimated JLPT level and mastery.
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

    private let progressService: ProgressService

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        let repo = CardRepository(modelContainer: modelContainer)
        self.progressService = ProgressService(cardRepository: repo)
    }

    /// Initializer for testing with injected dependencies.
    init(progressService: ProgressService) {
        self.progressService = progressService
    }

    // MARK: - Data Loading

    /// Loads all dashboard data from ProgressService.
    func loadData() async {
        let data = await progressService.loadDashboardData()

        skillBalance = data.skillBalance
        jlptEstimate = data.jlptEstimate
        dueNowCount = data.dueNowCount
        dueTodayCount = data.dueTodayCount
        forecast = data.forecast
        monthlySnapshots = data.monthlySnapshots
        hasLoaded = true

        Logger.ui.info("Progress dashboard loaded")
    }
}
