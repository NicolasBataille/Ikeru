import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("CardReviewViewModel")
@MainActor
struct CardReviewViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedCards(
        container: ModelContainer,
        count: Int = 3
    ) throws -> [UUID] {
        let context = container.mainContext
        var ids: [UUID] = []

        for i in 0..<count {
            let card = Card(
                front: "Card \(i)",
                back: "Back \(i)",
                type: .kanji,
                dueDate: Date().addingTimeInterval(-3600) // Due 1 hour ago
            )
            context.insert(card)
            ids.append(card.id)
        }
        try context.save()
        return ids
    }

    // MARK: - Loading Tests

    @Test("Loads due cards on init")
    func loadsDueCards() async throws {
        let container = try makeContainer()
        let cardIds = try seedCards(container: container, count: 3)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.sessionTotal == 3)
        #expect(viewModel.remainingCount == 3)
        #expect(viewModel.currentCard != nil)
        #expect(cardIds.contains(viewModel.currentCard!.id))
    }

    @Test("Shows empty state when no cards due")
    func showsEmptyStateWhenNoCardsDue() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        #expect(viewModel.isSessionComplete == true)
        #expect(viewModel.currentCard == nil)
        #expect(viewModel.remainingCount == 0)
    }

    @Test("Pre-loads next card for peek")
    func preloadsNextCard() async throws {
        let container = try makeContainer()
        _ = try seedCards(container: container, count: 2)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        #expect(viewModel.currentCard != nil)
        #expect(viewModel.nextCard != nil)
        #expect(viewModel.currentCard?.id != viewModel.nextCard?.id)
    }

    // MARK: - Grading Tests

    @Test("Grading advances to next card")
    func gradingAdvancesToNextCard() async throws {
        let container = try makeContainer()
        _ = try seedCards(container: container, count: 3)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        let firstCardId = viewModel.currentCard?.id

        await viewModel.gradeCard(grade: .good)

        #expect(viewModel.currentCard?.id != firstCardId)
        // After grading 1 of 3 cards, 2 remain
        #expect(viewModel.remainingCount == 2)
    }

    @Test("Again re-queues card at end of session")
    func againRequeuesCard() async throws {
        let container = try makeContainer()
        _ = try seedCards(container: container, count: 2)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        let firstCardId = viewModel.currentCard?.id

        // Grade "Again" — card should be re-queued
        await viewModel.gradeCard(grade: .again)

        // Should have moved to next card
        #expect(viewModel.currentCard?.id != firstCardId)

        // Remaining count should still be 2 (1 regular + 1 re-queued)
        #expect(viewModel.remainingCount == 2)
    }

    @Test("Session completes when all cards graded")
    func sessionCompletesWhenAllGraded() async throws {
        let container = try makeContainer()
        _ = try seedCards(container: container, count: 1)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()
        #expect(viewModel.currentCard != nil)

        await viewModel.gradeCard(grade: .good)

        #expect(viewModel.isSessionComplete == true)
        #expect(viewModel.currentCard == nil)
        #expect(viewModel.remainingCount == 0)
    }

    @Test("Session progress tracks correctly")
    func sessionProgressTracksCorrectly() async throws {
        let container = try makeContainer()
        _ = try seedCards(container: container, count: 4)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()
        #expect(viewModel.sessionProgress == 0.0)

        await viewModel.gradeCard(grade: .good)
        // 1 of 4 completed = 0.25
        let progress1 = viewModel.sessionProgress
        #expect(progress1 > 0.2 && progress1 < 0.3)

        await viewModel.gradeCard(grade: .good)
        // 2 of 4 completed = 0.50
        let progress2 = viewModel.sessionProgress
        #expect(progress2 > 0.4 && progress2 < 0.6)
    }

    @Test("Grading persists via CardRepository")
    func gradingPersistsViaRepository() async throws {
        let container = try makeContainer()
        let cardIds = try seedCards(container: container, count: 1)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()
        await viewModel.gradeCard(grade: .good)

        // Verify a review log was created
        let logs = await repo.reviewLogs(for: cardIds[0])
        #expect(logs.count == 1)
        #expect(logs.first?.grade == .good)
    }

    @Test("FSRS integration updates dueDate after grading")
    func fsrsIntegrationUpdatesDueDate() async throws {
        let container = try makeContainer()
        let cardIds = try seedCards(container: container, count: 1)
        let repo = CardRepository(modelContainer: container)

        // Get original due date
        let originalCard = await repo.card(by: cardIds[0])
        let originalDueDate = originalCard?.dueDate

        let viewModel = CardReviewViewModel(cardRepository: repo)
        await viewModel.loadDueCards()
        await viewModel.gradeCard(grade: .good)

        // Fetch updated card and check dueDate changed
        let updatedCard = await repo.card(by: cardIds[0])
        #expect(updatedCard != nil)
        #expect(updatedCard!.dueDate != originalDueDate)
        // After a "Good" grade, due date should be in the future
        #expect(updatedCard!.dueDate > Date())
    }

    // MARK: - Swipe Direction Tests

    @Test("Left swipe maps to Again grade")
    func leftSwipeMapsToAgain() {
        #expect(SwipeDirection.left.grade == .again)
    }

    @Test("Right swipe maps to Good grade")
    func rightSwipeMapsToGood() {
        #expect(SwipeDirection.right.grade == .good)
    }

    @Test("Up swipe maps to Easy grade")
    func upSwipeMapsToEasy() {
        #expect(SwipeDirection.up.grade == .easy)
    }

    @Test("Down swipe maps to Hard grade")
    func downSwipeMapsToHard() {
        #expect(SwipeDirection.down.grade == .hard)
    }

    @Test("SwipeDirection.from detects direction from offset")
    func swipeDirectionFromOffset() {
        let threshold: CGFloat = 100

        // Below threshold returns nil
        #expect(SwipeDirection.from(offset: CGSize(width: 50, height: 0), threshold: threshold) == nil)

        // Left swipe
        #expect(SwipeDirection.from(offset: CGSize(width: -150, height: 0), threshold: threshold) == .left)

        // Right swipe
        #expect(SwipeDirection.from(offset: CGSize(width: 150, height: 0), threshold: threshold) == .right)

        // Up swipe
        #expect(SwipeDirection.from(offset: CGSize(width: 0, height: -150), threshold: threshold) == .up)

        // Down swipe
        #expect(SwipeDirection.from(offset: CGSize(width: 0, height: 150), threshold: threshold) == .down)
    }

    @Test("SwipeDirection.from prioritizes dominant axis")
    func swipeDirectionPrioritizesDominantAxis() {
        let threshold: CGFloat = 100

        // Width > height => horizontal
        #expect(SwipeDirection.from(offset: CGSize(width: 200, height: 120), threshold: threshold) == .right)

        // Height > width => vertical
        #expect(SwipeDirection.from(offset: CGSize(width: 120, height: -200), threshold: threshold) == .up)
    }

    // MARK: - Response Time Tests

    @Test("Response time is tracked per card")
    func responseTimeTracked() async throws {
        let container = try makeContainer()
        let cardIds = try seedCards(container: container, count: 1)
        let repo = CardRepository(modelContainer: container)
        let viewModel = CardReviewViewModel(cardRepository: repo)

        await viewModel.loadDueCards()

        // Small delay to ensure response time > 0
        try await Task.sleep(for: .milliseconds(50))

        await viewModel.gradeCard(grade: .good)

        let logs = await repo.reviewLogs(for: cardIds[0])
        #expect(logs.count == 1)
        #expect(logs.first!.responseTimeMs > 0)
    }

    // MARK: - Feedback State Tests

    @Test("FeedbackState correct and incorrect are distinct")
    func feedbackStatesDistinct() {
        #expect(FeedbackState.correct != FeedbackState.incorrect)
    }

    @Test("FeedbackState colors match design spec")
    func feedbackStateColors() {
        // Jade green for correct
        #expect(FeedbackState.correct.color == Color(hex: IkeruTheme.Colors.success))
        // Vermillion for incorrect
        #expect(FeedbackState.incorrect.color == Color(hex: IkeruTheme.Colors.secondaryAccent))
    }
}
