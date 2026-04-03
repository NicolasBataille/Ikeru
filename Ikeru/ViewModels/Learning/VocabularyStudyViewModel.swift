import SwiftUI
import IkeruCore
import os

// MARK: - VocabularyStudyViewModel

@MainActor
@Observable
final class VocabularyStudyViewModel {

    // MARK: - Published State

    /// The vocabulary items to study in this session.
    private(set) var vocabularyItems: [VocabularyExercise] = []

    /// The grammar points to study in this session.
    private(set) var grammarPoints: [GrammarPoint] = []

    /// The fill-in-the-blank exercises for this session.
    private(set) var exercises: [FillInBlankExercise] = []

    /// Index of the current exercise being attempted.
    private(set) var currentExerciseIndex: Int = 0

    /// The answer the user selected for the current exercise (nil if not yet answered).
    private(set) var selectedAnswer: String?

    /// Whether the current exercise has been answered.
    private(set) var isAnswered: Bool = false

    /// Whether the selected answer was correct.
    private(set) var isCorrect: Bool = false

    /// Feedback state for visual flash overlay.
    private(set) var feedbackState: FeedbackState?

    /// Total XP earned during this study session.
    private(set) var xpEarned: Int = 0

    /// Number of exercises answered correctly.
    private(set) var correctCount: Int = 0

    // MARK: - Computed Properties

    /// The current fill-in-the-blank exercise, or nil if all done.
    var currentExercise: FillInBlankExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    /// Whether all exercises have been completed.
    var isExerciseSessionComplete: Bool {
        currentExerciseIndex >= exercises.count && !exercises.isEmpty
    }

    /// Progress fraction through the exercises (0.0 to 1.0).
    var exerciseProgress: Double {
        guard !exercises.isEmpty else { return 0 }
        return Double(currentExerciseIndex) / Double(exercises.count)
    }

    /// XP awarded per correct answer.
    private let xpPerCorrectAnswer = 5

    // MARK: - Init

    init() {}

    // MARK: - Loading

    /// Load vocabulary items for study.
    func loadVocabulary(_ items: [VocabularyExercise]) {
        vocabularyItems = items
        Logger.content.info("Loaded \(items.count) vocabulary items for study")
    }

    /// Load grammar points for study.
    func loadGrammarPoints(_ points: [GrammarPoint]) {
        grammarPoints = points
        Logger.content.info("Loaded \(points.count) grammar points for study")
    }

    /// Load fill-in-the-blank exercises.
    func loadExercises(_ items: [FillInBlankExercise]) {
        exercises = items
        currentExerciseIndex = 0
        selectedAnswer = nil
        isAnswered = false
        isCorrect = false
        correctCount = 0
        xpEarned = 0
        Logger.content.info("Loaded \(items.count) fill-in-blank exercises")
    }

    // MARK: - Exercise Interaction

    /// Submit an answer for the current exercise.
    func submitAnswer(_ answer: String) async {
        guard let exercise = currentExercise, !isAnswered else { return }

        let correct = answer == exercise.correctAnswer
        selectedAnswer = answer
        isAnswered = true
        isCorrect = correct

        if correct {
            correctCount += 1
            xpEarned += xpPerCorrectAnswer
            feedbackState = .correct
        } else {
            feedbackState = .incorrect
        }

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(600))
        feedbackState = nil
    }

    /// Advance to the next exercise after the user has seen the result.
    func advanceToNextExercise() {
        currentExerciseIndex += 1
        selectedAnswer = nil
        isAnswered = false
        isCorrect = false
    }
}
