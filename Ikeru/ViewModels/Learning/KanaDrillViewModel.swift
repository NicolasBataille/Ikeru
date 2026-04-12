import Foundation
import IkeruCore

// MARK: - KanaDrillViewModel

/// Shared view model that drives both the flashcard and the 4-choice quiz
/// drill views. Holds the queue of cards, per-card state (revealed / answered /
/// quiz options), and session-wide stats. Calls into `CardRepository.gradeCard`
/// to persist FSRS scheduling and review logs.
@MainActor
@Observable
public final class KanaDrillViewModel {

    // MARK: Input

    public let mode: KanaDrillMode
    public private(set) var queue: [CardDTO]

    // MARK: Current card

    public private(set) var currentCard: CardDTO?
    public private(set) var currentIndex: Int = 0
    public private(set) var isRevealed: Bool = false
    public private(set) var isAnswered: Bool = false

    // MARK: Quiz state

    public private(set) var quizOptions: [String] = []
    public private(set) var selectedOption: String? = nil
    public private(set) var correctOption: String = ""
    public private(set) var selectedOptionCharacter: String? = nil

    // MARK: Session stats

    public private(set) var correctCount: Int = 0
    public private(set) var wrongCount: Int = 0
    public private(set) var startedAt: Date = Date()
    public private(set) var cardStartedAt: Date = Date()
    public private(set) var sessionEnded: Bool = false

    // MARK: Predicted intervals (flashcard mode)

    public private(set) var predictedIntervals: [Grade: String] = [:]

    // MARK: Dependencies

    private let cardRepository: CardRepository
    private let now: @Sendable () -> Date

    // MARK: Init

    public init(
        mode: KanaDrillMode,
        queue: [CardDTO],
        cardRepository: CardRepository,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.mode = mode
        self.queue = queue.shuffled()
        self.cardRepository = cardRepository
        self.now = now
        let nowValue = now()
        self.startedAt = nowValue
        self.cardStartedAt = nowValue
        self.currentCard = self.queue.first
        if self.currentCard != nil {
            buildQuiz(for: self.queue[0])
        } else {
            sessionEnded = true
        }
    }

    // MARK: - Computed

    public var isFirstCard: Bool { currentIndex == 0 }
    public var isLastCard: Bool {
        guard !queue.isEmpty else { return true }
        return currentIndex == queue.count - 1
    }
    public var progressPercent: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(queue.count)
    }

    // MARK: - Flashcard actions

    public func reveal() {
        guard let card = currentCard, !isRevealed else { return }
        isRevealed = true
        predictedIntervals = computePredictedIntervals(for: card)
    }

    public func grade(_ grade: Grade) async {
        guard let card = currentCard else { return }
        let elapsed = Int(now().timeIntervalSince(cardStartedAt) * 1000)
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: max(0, elapsed),
            now: now()
        )
        if grade == .again {
            wrongCount += 1
        } else {
            correctCount += 1
        }
        advance()
    }

    // MARK: - Quiz actions

    public func selectOption(_ option: String) {
        guard !isAnswered else { return }
        selectedOption = option
    }

    public func submitQuizAnswer() async {
        guard let card = currentCard, let selected = selectedOption, !isAnswered else { return }
        isAnswered = true
        let elapsedMs = Int(now().timeIntervalSince(cardStartedAt) * 1000)
        let isCorrect = selected == correctOption
        let grade = mapQuizResult(correct: isCorrect, responseTimeMs: elapsedMs)

        // Track which kana corresponds to the selected (potentially wrong) romaji
        // for the pedagogical "Le caractère pour {romaji} est {kana}" feedback.
        selectedOptionCharacter = lookupCharacter(forRomaji: selected, in: card)

        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: max(0, elapsedMs),
            now: now()
        )
        if isCorrect {
            correctCount += 1
        } else {
            wrongCount += 1
        }
    }

    // MARK: - Navigation

    public func advance() {
        let next = currentIndex + 1
        if next >= queue.count {
            sessionEnded = true
            currentCard = nil
            isRevealed = false
            isAnswered = false
            selectedOption = nil
            selectedOptionCharacter = nil
            quizOptions = []
            return
        }
        currentIndex = next
        let card = queue[next]
        currentCard = card
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        selectedOptionCharacter = nil
        predictedIntervals = [:]
        cardStartedAt = now()
        buildQuiz(for: card)
    }

    public func restart() {
        queue = queue.shuffled()
        currentIndex = 0
        correctCount = 0
        wrongCount = 0
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        selectedOptionCharacter = nil
        predictedIntervals = [:]
        sessionEnded = false
        let nowValue = now()
        startedAt = nowValue
        cardStartedAt = nowValue
        if let first = queue.first {
            currentCard = first
            buildQuiz(for: first)
        } else {
            currentCard = nil
            sessionEnded = true
        }
    }

    // MARK: - Helpers

    /// Map (correct, time) -> Grade for the quiz speed bonus.
    func mapQuizResult(correct: Bool, responseTimeMs: Int) -> Grade {
        if !correct { return .again }
        if responseTimeMs < 2_000 { return .easy }
        if responseTimeMs < 5_000 { return .good }
        return .hard
    }

    /// Build the 4 quiz options for a given card. The correct romaji plus 3
    /// distractors picked from the same KanaGroup when possible, falling back
    /// to other groups in the same script + section. Final order is shuffled.
    private func buildQuiz(for card: CardDTO) {
        guard let group = card.kanaGroup,
              let correctChar = group.characters.first(where: { $0.character == card.front })
        else {
            quizOptions = [card.back]
            correctOption = card.back
            return
        }
        let correctRomaji = correctChar.romaji
        correctOption = correctRomaji

        var pool: [String] = group.characters
            .filter { $0.character != correctChar.character }
            .map { $0.romaji }

        if pool.count < 3 {
            let siblings = KanaGroup.allCases
                .filter { $0.script == group.script && $0.section == group.section && $0 != group }
                .flatMap { $0.characters }
                .map { $0.romaji }
                .filter { $0 != correctRomaji }
            for romaji in siblings where !pool.contains(romaji) {
                pool.append(romaji)
                if pool.count >= 8 { break }
            }
        }

        var distractors = Array(Set(pool)).shuffled().prefix(3).map { $0 }
        // Pad if still short (extreme edge: tiny dataset)
        while distractors.count < 3 {
            distractors.append("?\(distractors.count)")
        }

        var options = distractors
        options.append(correctRomaji)
        quizOptions = options.shuffled()
    }

    /// Find the kana character whose romaji matches `romaji`, searching the
    /// current card's group first then any sibling group in the same script.
    private func lookupCharacter(forRomaji romaji: String, in card: CardDTO) -> String? {
        guard let group = card.kanaGroup else { return nil }
        if let hit = group.characters.first(where: { $0.romaji == romaji }) {
            return hit.character
        }
        let siblings = KanaGroup.allCases
            .filter { $0.script == group.script }
            .flatMap { $0.characters }
        return siblings.first(where: { $0.romaji == romaji })?.character
    }

    /// Run FSRS once per grade to estimate intervals shown on the reveal buttons.
    private func computePredictedIntervals(for card: CardDTO) -> [Grade: String] {
        var result: [Grade: String] = [:]
        let nowValue = now()
        for grade in Grade.allCases {
            let newState = FSRSService.schedule(state: card.fsrsState, grade: grade, now: nowValue)
            let due = FSRSService.dueDate(for: newState, now: nowValue)
            result[grade] = formatInterval(from: nowValue, to: due)
        }
        return result
    }

    private func formatInterval(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 60 {
            return "1 min"
        }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = Int(ceil(seconds / 3_600))
        if hours < 24 {
            return "\(hours) h"
        }
        let days = Int(ceil(seconds / 86_400))
        if days < 30 {
            return "\(days) j"
        }
        let months = Int(ceil(seconds / (86_400 * 30)))
        return "\(months) mois"
    }
}
