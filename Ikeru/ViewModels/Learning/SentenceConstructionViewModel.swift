import SwiftUI
import IkeruCore
import os

// MARK: - SentencePhase

/// The current phase of a sentence construction exercise.
public enum SentencePhase: Sendable {
    /// Learner is arranging tokens.
    case constructing
    /// Feedback is shown after submission.
    case feedback
}

// MARK: - SentenceConstructionViewModel

@MainActor
@Observable
public final class SentenceConstructionViewModel {

    // MARK: - Published State

    /// The current exercise being worked on.
    public private(set) var currentExercise: SentenceExercise?

    /// Tokens not yet placed by the learner.
    public private(set) var availableTokens: [SentenceToken] = []

    /// Tokens placed by the learner in order.
    public private(set) var arrangedTokens: [SentenceToken] = []

    /// Validation result after submission, nil before submission.
    public private(set) var validationResult: SentenceValidationResult?

    /// Loading state for exercise generation.
    public private(set) var loadingState: LoadingState<Void> = .idle

    /// Current exercise phase.
    public private(set) var exercisePhase: SentencePhase = .constructing

    /// Feedback flash state for haptics.
    public private(set) var feedbackState: FeedbackState?

    /// Whether all tokens have been placed.
    public var allTokensPlaced: Bool {
        availableTokens.isEmpty && !arrangedTokens.isEmpty
    }

    // MARK: - Private State

    private var exercises: [SentenceExercise] = []
    private var currentIndex: Int = 0
    private let validator: any SentenceValidator

    // MARK: - Init

    public init(validator: any SentenceValidator = SentenceValidationService()) {
        self.validator = validator
    }

    // MARK: - Loading

    /// Load exercises for a given difficulty level.
    public func loadExercise(difficulty: SentenceDifficulty) {
        loadingState = .loading

        let generated = validator.generateExercises(from: [], level: difficulty)

        guard !generated.isEmpty else {
            loadingState = .failed(SentenceExerciseError.noExercisesAvailable)
            Logger.content.warning("No sentence exercises available for \(difficulty.rawValue)")
            return
        }

        exercises = generated
        currentIndex = 0
        presentExercise(generated[0])
        loadingState = .loaded(())

        Logger.content.info("Loaded \(generated.count) sentence exercises at \(difficulty.rawValue) level")
    }

    // MARK: - Token Interaction

    /// Move a token from available to the end of the arranged area.
    public func selectToken(_ token: SentenceToken) {
        guard exercisePhase == .constructing else { return }
        guard let index = availableTokens.firstIndex(of: token) else { return }

        var newAvailable = availableTokens
        newAvailable.remove(at: index)
        availableTokens = newAvailable

        var newArranged = arrangedTokens
        newArranged.append(token)
        arrangedTokens = newArranged
    }

    /// Move a token from arranged back to the available area.
    public func removeToken(_ token: SentenceToken) {
        guard exercisePhase == .constructing else { return }
        guard let index = arrangedTokens.firstIndex(of: token) else { return }

        var newArranged = arrangedTokens
        newArranged.remove(at: index)
        arrangedTokens = newArranged

        var newAvailable = availableTokens
        newAvailable.append(token)
        availableTokens = newAvailable
    }

    // MARK: - Submission

    /// Validate the current arrangement against the target sentence.
    public func submitAnswer() {
        guard let exercise = currentExercise else { return }
        guard exercisePhase == .constructing else { return }
        guard allTokensPlaced else { return }

        let result = validator.validate(
            arranged: arrangedTokens,
            against: exercise.targetSentence
        )

        validationResult = result
        exercisePhase = .feedback
        feedbackState = result.isCorrect ? .correct : .incorrect

        Logger.ui.info("Sentence exercise submitted: correct=\(result.isCorrect), incorrectPositions=\(result.incorrectPositions)")
    }

    // MARK: - Navigation

    /// Advance to the next exercise in the queue.
    public func nextExercise() {
        let nextIndex = currentIndex + 1
        guard nextIndex < exercises.count else {
            // All exercises completed — cycle back to beginning
            currentIndex = 0
            if let first = exercises.first {
                presentExercise(first)
            }
            return
        }

        currentIndex = nextIndex
        presentExercise(exercises[nextIndex])
    }

    /// Clear all arranged tokens and return them to available.
    public func resetArrangement() {
        guard exercisePhase == .constructing else { return }
        guard let exercise = currentExercise else { return }

        arrangedTokens = []
        availableTokens = exercise.shuffledTokens
        validationResult = nil
    }

    // MARK: - Private

    private func presentExercise(_ exercise: SentenceExercise) {
        currentExercise = exercise
        availableTokens = exercise.shuffledTokens
        arrangedTokens = []
        validationResult = nil
        exercisePhase = .constructing
        feedbackState = nil
    }
}

// MARK: - SentenceExerciseError

enum SentenceExerciseError: LocalizedError {
    case noExercisesAvailable

    var errorDescription: String? {
        switch self {
        case .noExercisesAvailable:
            "No sentence exercises are available for this difficulty level."
        }
    }
}
