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

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let repo = CardRepository(modelContainer: modelContainer)
        self.cardRepository = repo
        self.plannerService = PlannerService(cardRepository: repo)
        self.progressService = ProgressService(cardRepository: repo)
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
    }

    // MARK: - Data Loading

    /// Loads all home screen data from local SwiftData.
    /// Called on .onAppear to refresh after session completion.
    public func loadData() async {
        let startTime = CFAbsoluteTimeGetCurrent()

        await loadProfile()
        await loadRPGState()
        await loadDueCardCount()
        await loadKanjiLearnedCount()
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

    private func loadRPGState() async {
        let context = modelContainer.mainContext

        if let state = ActiveProfileResolver.fetchActiveRPGState(in: context) {
            xp = state.xp
            level = state.level
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

    /// Composes a session preview: estimated card count and time.
    private func composeSessionPreview() async {
        let queue = await plannerService.composeSession()
        sessionPreviewCardCount = queue.count
        // Roughly 1 minute per card, minimum 1
        sessionPreviewMinutes = max(1, queue.count)

        // Approximate split between brand-new cards and reviews. A card is
        // "new" when it has never been answered (reps == 0); everything else
        // is a recurring review.
        var newCount = 0
        var reviewCount = 0
        for card in queue {
            if card.fsrsState.reps == 0 {
                newCount += 1
            } else {
                reviewCount += 1
            }
        }
        sessionPreviewNewCount = newCount
        sessionPreviewReviewCount = reviewCount
        Logger.ui.debug("Session preview: \(queue.count) cards, ~\(self.sessionPreviewMinutes) min")
    }

    private func loadSkillBalance() async {
        let data = await progressService.loadDashboardData()
        skillBalance = data.skillBalance
    }
}
