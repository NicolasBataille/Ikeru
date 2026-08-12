import SwiftUI
import WatchKit
import IkeruCore

// MARK: - WatchQuizViewModel

/// View model for the Watch kana recognition quiz.
/// Manages quiz state, scoring, and haptic feedback triggers.
@MainActor
@Observable
final class WatchQuizViewModel {

    // MARK: - State

    /// Current question index (0-based).
    private(set) var currentQuestion: Int = 0

    /// Total questions in this nano-session.
    let totalQuestions: Int = 10

    /// Number of correct answers.
    private(set) var correctCount: Int = 0

    /// Whether the session is complete.
    var isComplete: Bool {
        currentQuestion >= totalQuestions
    }

    /// The target kana character to identify.
    private(set) var targetCharacter: String = ""

    /// The correct answer's ID.
    private(set) var correctId: String = ""

    /// The 4 answer choices.
    private(set) var choices: [KanaData.Entry] = []

    /// Result of the last answer (nil if no answer yet for current question).
    private(set) var lastAnswerResult: Bool?

    /// ID of the last answered choice.
    private(set) var lastAnsweredId: String?

    /// Results per question (true = correct).
    private(set) var questionResults: [Bool] = []

    /// Kana pool for this session.
    private var pool: [KanaData.Entry] = []

    /// Remaining targets for this session, drawn without replacement so the
    /// same kana never repeats as the answer across questions.
    private var targetQueue: [KanaData.Entry] = []

    /// The correct choice for the current question, once answered incorrectly.
    /// Used to surface a brief "correct answer" feedback before advancing —
    /// otherwise a wrong tap teaches nothing (see task #9).
    var correctAnswerFeedback: (romaji: String, kana: String)? {
        guard lastAnswerResult == false,
              let correct = choices.first(where: { $0.id == correctId }) else { return nil }
        return (romaji: correct.romanization, kana: correct.character)
    }

    // MARK: - Session Control

    func startSession() {
        pool = KanaData.hiragana
        targetQueue = pool.shuffled()
        currentQuestion = 0
        correctCount = 0
        questionResults = []
        lastAnswerResult = nil
        lastAnsweredId = nil
        loadNextQuestion()
    }

    func selectAnswer(_ choice: KanaData.Entry) {
        guard lastAnswerResult == nil else { return } // Already answered

        let isCorrect = choice.id == correctId
        lastAnswerResult = isCorrect
        lastAnsweredId = choice.id
        questionResults.append(isCorrect)

        if isCorrect {
            correctCount += 1
            // Success haptic played by WKInterfaceDevice
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.failure)
        }

        // Auto-advance after a brief delay. Wrong answers pause longer so the
        // correct-answer feedback (see `correctAnswerFeedback`) is readable.
        let pauseDuration: Duration = isCorrect ? .milliseconds(600) : .milliseconds(1700)

        Task { @MainActor in
            try? await Task.sleep(for: pauseDuration)
            currentQuestion += 1
            lastAnswerResult = nil
            lastAnsweredId = nil
            if !isComplete {
                loadNextQuestion()
            } else {
                WKInterfaceDevice.current().play(.notification)
                let result = WatchSessionResult(
                    correctCount: correctCount,
                    totalQuestions: totalQuestions,
                    drillType: .kanaQuiz,
                    xpEarned: correctCount * 5
                )
                WatchSessionManager.shared.sendSessionResult(result)
            }
        }
    }

    // MARK: - Private

    private func loadNextQuestion() {
        guard pool.count >= 4 else { return }
        if targetQueue.isEmpty {
            // Exhausted the pool without repeating within the session — reshuffle
            // for any remaining questions (only reachable if totalQuestions ever
            // exceeds the pool size).
            targetQueue = pool.shuffled()
        }
        let target = targetQueue.removeFirst()
        targetCharacter = target.character
        correctId = target.id
        choices = buildChoices(for: target)
    }

    /// Builds the 4-choice answer set for `target`, preferring distractors that
    /// are visually similar to it (e.g. る/ろ, き/さ) over purely random ones —
    /// random distractors waste the questions that would otherwise drill the
    /// pairs learners actually confuse.
    private func buildChoices(for target: KanaData.Entry) -> [KanaData.Entry] {
        let confusable = Self.confusableCharacters(for: target.character)
        let remainingPool = pool.filter { $0.id != target.id }

        var selected = Array(
            remainingPool
                .filter { confusable.contains($0.character) }
                .shuffled()
                .prefix(3)
        )

        if selected.count < 3 {
            let usedIds = Set(selected.map(\.id))
            let filler = remainingPool
                .filter { !usedIds.contains($0.id) }
                .shuffled()
            selected.append(contentsOf: filler.prefix(3 - selected.count))
        }

        var choices = selected + [target]
        choices.shuffle()
        return choices
    }

    /// Groups of kana that are commonly confused by shape, used to bias
    /// distractor selection toward realistic mistakes.
    private static let confusableGroups: [Set<String>] = [
        ["る", "ろ"],
        ["シ", "ツ"],
        ["ソ", "ン"],
        ["き", "さ"],
        ["ね", "れ", "わ"],
        ["は", "ほ"],
        ["あ", "お"],
        ["ま", "も"],
    ]

    private static func confusableCharacters(for character: String) -> Set<String> {
        confusableGroups.first { $0.contains(character) }?.subtracting([character]) ?? []
    }
}
