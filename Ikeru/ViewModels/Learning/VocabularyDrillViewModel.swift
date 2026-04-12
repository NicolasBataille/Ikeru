import Foundation
import IkeruCore
import os

// MARK: - VocabularyDrillViewModel

/// Drives flashcard and quiz drills for personal dictionary words.
/// Uses VocabularyRepository for FSRS grading (same algorithm as SRS cards).
@MainActor
@Observable
public final class VocabularyDrillViewModel {

    // MARK: - Input

    public private(set) var queue: [VocabularyEntryDTO]

    // MARK: - Current entry

    public private(set) var currentEntry: VocabularyEntryDTO?
    public private(set) var currentIndex: Int = 0
    public private(set) var isRevealed: Bool = false
    public private(set) var isAnswered: Bool = false

    // MARK: - Quiz state

    public private(set) var quizOptions: [String] = []
    public private(set) var selectedOption: String?
    public private(set) var correctOption: String = ""

    // MARK: - Session stats

    public private(set) var correctCount: Int = 0
    public private(set) var wrongCount: Int = 0
    public private(set) var startedAt: Date = Date()
    public private(set) var entryStartedAt: Date = Date()
    public private(set) var sessionEnded: Bool = false

    // MARK: - Predicted intervals (flashcard mode)

    public private(set) var predictedIntervals: [Grade: String] = [:]

    // MARK: - Dependencies

    private let vocabularyRepository: VocabularyRepository
    private let allEntries: [VocabularyEntryDTO]
    private let now: @Sendable () -> Date

    // MARK: - Init

    public init(
        queue: [VocabularyEntryDTO],
        allEntries: [VocabularyEntryDTO],
        vocabularyRepository: VocabularyRepository,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.allEntries = allEntries
        self.vocabularyRepository = vocabularyRepository
        self.now = now
        self.queue = queue.shuffled()
        let nowValue = now()
        self.startedAt = nowValue
        self.entryStartedAt = nowValue
        self.currentEntry = self.queue.first
        if self.currentEntry != nil {
            buildQuiz(for: self.queue[0])
        } else {
            sessionEnded = true
        }
    }

    // MARK: - Computed

    public var progressPercent: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(queue.count)
    }

    // MARK: - Flashcard Actions

    public func reveal() {
        guard let entry = currentEntry, !isRevealed else { return }
        isRevealed = true
        predictedIntervals = computePredictedIntervals(for: entry)
    }

    public func grade(_ grade: Grade) async {
        guard let entry = currentEntry else { return }
        let elapsed = Int(now().timeIntervalSince(entryStartedAt) * 1000)
        await vocabularyRepository.gradeEntry(
            entryId: entry.id,
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

    // MARK: - Quiz Actions

    public func selectOption(_ option: String) {
        guard !isAnswered else { return }
        selectedOption = option
    }

    public func submitQuizAnswer() async {
        guard let entry = currentEntry, let selected = selectedOption, !isAnswered else { return }
        isAnswered = true
        let elapsedMs = Int(now().timeIntervalSince(entryStartedAt) * 1000)
        let isCorrect = selected == correctOption
        let grade = mapQuizResult(correct: isCorrect, responseTimeMs: elapsedMs)

        await vocabularyRepository.gradeEntry(
            entryId: entry.id,
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
            currentEntry = nil
            isRevealed = false
            isAnswered = false
            selectedOption = nil
            quizOptions = []
            return
        }
        currentIndex = next
        let entry = queue[next]
        currentEntry = entry
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        predictedIntervals = [:]
        entryStartedAt = now()
        buildQuiz(for: entry)
    }

    public func restart() {
        queue = queue.shuffled()
        currentIndex = 0
        correctCount = 0
        wrongCount = 0
        isRevealed = false
        isAnswered = false
        selectedOption = nil
        predictedIntervals = [:]
        sessionEnded = false
        let nowValue = now()
        startedAt = nowValue
        entryStartedAt = nowValue
        if let first = queue.first {
            currentEntry = first
            buildQuiz(for: first)
        } else {
            currentEntry = nil
            sessionEnded = true
        }
    }

    // MARK: - Helpers

    func mapQuizResult(correct: Bool, responseTimeMs: Int) -> Grade {
        if !correct { return .again }
        if responseTimeMs < 2_000 { return .easy }
        if responseTimeMs < 5_000 { return .good }
        return .hard
    }

    /// Build 4 quiz options: correct meaning + 3 distractors from other dictionary entries.
    private func buildQuiz(for entry: VocabularyEntryDTO) {
        let correctMeaning = entry.meaning
        correctOption = correctMeaning

        var pool = allEntries
            .filter { $0.id != entry.id }
            .map { $0.meaning }

        // Deduplicate
        pool = Array(Set(pool))

        var distractors = pool.shuffled().prefix(3).map { $0 }
        while distractors.count < 3 {
            distractors.append("—")
        }

        var options = distractors
        options.append(correctMeaning)
        quizOptions = options.shuffled()
    }

    private func computePredictedIntervals(for entry: VocabularyEntryDTO) -> [Grade: String] {
        var result: [Grade: String] = [:]
        let nowValue = now()
        for grade in Grade.allCases {
            let newState = FSRSService.schedule(state: entry.fsrsState, grade: grade, now: nowValue)
            let due = FSRSService.dueDate(for: newState, now: nowValue)
            result[grade] = formatInterval(from: nowValue, to: due)
        }
        return result
    }

    private func formatInterval(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 60 { return "1 min" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "\(minutes) min" }
        let hours = Int(ceil(seconds / 3_600))
        if hours < 24 { return "\(hours) h" }
        let days = Int(ceil(seconds / 86_400))
        if days < 30 { return "\(days) j" }
        let months = Int(ceil(seconds / (86_400 * 30)))
        return "\(months) mois"
    }
}
