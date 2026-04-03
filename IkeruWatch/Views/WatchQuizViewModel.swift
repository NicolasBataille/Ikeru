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

    // MARK: - Session Control

    func startSession() {
        pool = KanaData.hiragana
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

        // Auto-advance after brief delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            currentQuestion += 1
            lastAnswerResult = nil
            lastAnsweredId = nil
            if !isComplete {
                loadNextQuestion()
            } else {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }

    // MARK: - Private

    private func loadNextQuestion() {
        guard let question = KanaData.generateQuizQuestion(from: pool) else { return }
        targetCharacter = question.target.character
        correctId = question.target.id
        choices = question.choices
    }
}
