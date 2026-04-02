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

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let repo = CardRepository(modelContainer: modelContainer)
        self.cardRepository = repo
        self.plannerService = PlannerService(cardRepository: repo)
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

        hasLoaded = true

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.ui.info("Home screen data loaded in \(elapsed, format: .fixed(precision: 1))ms")
    }

    // MARK: - Private Loading

    private func loadProfile() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(descriptor)) ?? []
        displayName = profiles.first?.displayName ?? ""
    }

    private func loadRPGState() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RPGState>()
        let results = (try? context.fetch(descriptor)) ?? []

        if let state = results.first {
            xp = state.xp
            level = state.level
        } else {
            xp = 0
            level = 1
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
        Logger.ui.debug("Session preview: \(queue.count) cards, ~\(self.sessionPreviewMinutes) min")
    }
}
