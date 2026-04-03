import SwiftUI
import IkeruCore
import os

// MARK: - ExerciseResult

/// Result of a listening exercise answer submission.
public enum ExerciseResult: Sendable, Equatable {
    case correct
    case incorrect
}

// MARK: - ListeningViewModel

/// ViewModel for listening exercises. Coordinates audio playback, exercise loading,
/// and answer evaluation.
@MainActor
@Observable
public final class ListeningViewModel {

    // MARK: - Observable State

    /// The current listening exercise being presented.
    public private(set) var currentExercise: ListeningExercise?

    /// The current playback rate.
    public private(set) var playbackRate: PlaybackRate = .normal

    /// Whether audio is currently playing (delegated from AudioService).
    public var isPlaying: Bool {
        audioService.isPlaying
    }

    /// The user's selected answer, or nil if not yet answered.
    public private(set) var selectedAnswer: String?

    /// The result of the last answer submission.
    public private(set) var exerciseResult: ExerciseResult?

    /// Whether audio exercises should be skipped (silent mode).
    public var shouldSkipAudioExercises: Bool {
        audioService.shouldSkipAudioExercises
    }

    /// Whether the transcript is revealed (passage exercises).
    public private(set) var isTranscriptRevealed: Bool = false

    /// Loading state for async exercise loading.
    public private(set) var loadingState: LoadingState<ListeningExercise> = .idle

    // MARK: - Dependencies

    private let audioService: AudioService
    private let vocabulary: [VocabularyItem]
    private let passages: [ListeningExercisePassage]

    // MARK: - Init

    public init(
        audioService: AudioService,
        vocabulary: [VocabularyItem],
        passages: [ListeningExercisePassage]
    ) {
        self.audioService = audioService
        self.vocabulary = vocabulary
        self.passages = passages
    }

    // MARK: - Exercise Loading

    /// Loads a new exercise of the given type and JLPT level.
    /// - Parameters:
    ///   - type: The type of listening exercise to generate.
    ///   - level: The JLPT difficulty level.
    public func loadExercise(
        type: ListeningExerciseType,
        level: JLPTLevel
    ) async {
        loadingState = .loading
        selectedAnswer = nil
        exerciseResult = nil
        isTranscriptRevealed = false

        let filteredVocabulary = vocabulary.filter { $0.jlptLevel == level }
        let filteredPassages = passages.filter { $0.jlptLevel == level }

        let exercise: ListeningExercise?

        switch type {
        case .wordRecognition:
            guard let target = filteredVocabulary.randomElement(),
                  filteredVocabulary.count >= 4 else {
                loadingState = .idle
                Logger.audio.warning(
                    "Insufficient vocabulary for word recognition exercise at level \(level.displayLabel)"
                )
                return
            }
            exercise = ListeningExerciseGenerator.generateWordRecognition(
                target: target,
                pool: filteredVocabulary
            )

        case .meaningSelection:
            guard let target = filteredVocabulary.randomElement(),
                  filteredVocabulary.count >= 4 else {
                loadingState = .idle
                Logger.audio.warning(
                    "Insufficient vocabulary for meaning selection exercise at level \(level.displayLabel)"
                )
                return
            }
            exercise = ListeningExerciseGenerator.generateMeaningSelection(
                target: target,
                pool: filteredVocabulary
            )

        case .passageComprehension:
            guard let passage = filteredPassages.randomElement() else {
                loadingState = .idle
                Logger.audio.warning(
                    "No passages available for comprehension exercise at level \(level.displayLabel)"
                )
                return
            }
            exercise = ListeningExerciseGenerator.generatePassageComprehension(
                passage: passage
            )
        }

        if let exercise {
            currentExercise = exercise
            loadingState = .loaded(exercise)
            Logger.audio.info(
                "Loaded \(type.rawValue) exercise at \(level.displayLabel)"
            )
        }
    }

    // MARK: - Audio Playback

    /// Plays the audio for the current exercise.
    public func playAudio() async {
        guard let exercise = currentExercise else { return }
        await audioService.playTTS(
            text: exercise.audioText,
            rate: playbackRate
        )
    }

    /// Sets the playback rate.
    /// - Parameter rate: The new playback rate.
    public func setPlaybackRate(_ rate: PlaybackRate) {
        playbackRate = rate
        audioService.currentRate = rate
    }

    // MARK: - Answer Evaluation

    /// Submits an answer and evaluates correctness.
    /// - Parameter answer: The selected answer string.
    public func submitAnswer(_ answer: String) {
        guard let exercise = currentExercise else { return }

        selectedAnswer = answer
        exerciseResult = exercise.isCorrect(answer: answer) ? .correct : .incorrect

        Logger.audio.debug(
            "Answer submitted: \(answer), correct=\(exercise.isCorrect(answer: answer))"
        )
    }

    // MARK: - Transcript

    /// Reveals the transcript for passage exercises.
    public func revealTranscript() {
        isTranscriptRevealed = true
    }

    // MARK: - Reset

    /// Resets the exercise state for a new attempt.
    public func reset() {
        selectedAnswer = nil
        exerciseResult = nil
        isTranscriptRevealed = false
        audioService.stop()
    }
}
