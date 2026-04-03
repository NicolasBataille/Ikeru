import SwiftUI
import IkeruCore
import os

// MARK: - ExercisePhase

/// The current phase of a shadowing exercise.
public enum ExercisePhase: Sendable, Equatable {
    /// Listening to the target audio.
    case listen

    /// Recording the learner's speech.
    case record

    /// Showing feedback comparing expected vs recognized.
    case feedback
}

// MARK: - ShadowingViewModel

/// ViewModel for shadowing exercises. Coordinates audio playback, speech recognition,
/// pronunciation scoring, and exercise lifecycle.
@MainActor
@Observable
public final class ShadowingViewModel {

    // MARK: - Observable State

    /// The current shadowing exercise being presented.
    public private(set) var currentExercise: ShadowingExercise?

    /// The current phase of the exercise.
    public private(set) var exercisePhase: ExercisePhase = .listen

    /// Whether audio is currently playing (delegated from AudioService).
    public var isPlaying: Bool {
        audioService.isPlaying
    }

    /// Whether speech is currently being recorded.
    public var isRecording: Bool {
        speechService.isRecording
    }

    /// The real-time recognized text from speech recognition.
    public var recognizedText: String {
        speechService.recognizedText
    }

    /// The result of pronunciation scoring after recording.
    public private(set) var shadowingResult: ShadowingResult?

    /// The permission status for microphone and speech recognition.
    public var permissionStatus: SpeechPermissionStatus {
        speechService.permissionStatus
    }

    /// Loading state for async exercise loading.
    public private(set) var loadingState: LoadingState<ShadowingExercise> = .idle

    /// The current playback rate.
    public private(set) var playbackRate: PlaybackRate = .normal

    // MARK: - Dependencies

    private let audioService: AudioService
    private let speechService: SpeechRecognitionService
    private let vocabulary: [VocabularyItem]

    // MARK: - Init

    public init(
        audioService: AudioService,
        speechService: SpeechRecognitionService,
        vocabulary: [VocabularyItem]
    ) {
        self.audioService = audioService
        self.speechService = speechService
        self.vocabulary = vocabulary
    }

    // MARK: - Permission Check

    /// Checks and updates permission status for microphone and speech recognition.
    public func checkPermissions() {
        speechService.checkPermissionStatus()
    }

    /// Requests microphone and speech recognition permissions.
    /// - Returns: True if both permissions are authorized.
    public func requestPermissions() async -> Bool {
        await speechService.requestAuthorization()
    }

    // MARK: - Exercise Loading

    /// Loads a new shadowing exercise filtered by difficulty and JLPT level.
    /// - Parameters:
    ///   - difficulty: The desired difficulty level.
    ///   - level: The JLPT level to filter by.
    public func loadExercise(
        difficulty: ShadowingDifficulty,
        level: JLPTLevel
    ) async {
        loadingState = .loading
        shadowingResult = nil
        exercisePhase = .listen

        let exercises = ShadowingExerciseGenerator.generateExercises(
            from: vocabulary,
            difficulty: difficulty,
            level: level,
            count: 1
        )

        guard let exercise = exercises.first else {
            loadingState = .idle
            Logger.audio.warning(
                "Insufficient vocabulary for shadowing exercise at \(difficulty.displayLabel) / \(level.displayLabel)"
            )
            return
        }

        currentExercise = exercise
        loadingState = .loaded(exercise)

        // Check permissions after loading
        checkPermissions()

        Logger.audio.info(
            "Loaded shadowing exercise: \(exercise.targetText.prefix(20)) at \(difficulty.displayLabel) / \(level.displayLabel)"
        )
    }

    // MARK: - Audio Playback

    /// Plays the target audio for the current exercise.
    public func playTarget() async {
        guard let exercise = currentExercise else { return }

        // Use the reading (hiragana) for more accurate TTS pronunciation
        await audioService.playTTS(
            text: exercise.reading,
            rate: playbackRate
        )

        // After playback completes, transition to record phase if still in listen phase
        if exercisePhase == .listen {
            exercisePhase = .record
        }
    }

    /// Sets the playback rate.
    /// - Parameter rate: The new playback rate.
    public func setPlaybackRate(_ rate: PlaybackRate) {
        playbackRate = rate
        audioService.currentRate = rate
    }

    // MARK: - Recording

    /// Starts recording the learner's speech.
    public func startRecording() async {
        guard currentExercise != nil else { return }
        guard permissionStatus == .authorized else {
            Logger.audio.warning("Cannot start recording — permissions not authorized")
            return
        }

        exercisePhase = .record
        do {
            try await speechService.startRecording()
        } catch {
            Logger.audio.error("Failed to start recording: \(error.localizedDescription)")
            exercisePhase = .listen
        }
    }

    /// Stops recording and scores the pronunciation.
    public func stopRecording() async {
        guard isRecording else { return }
        guard let exercise = currentExercise else { return }

        let result = speechService.stopRecording()

        // Score the pronunciation
        let scoringResult = PronunciationScorer.score(
            recognized: result.text,
            expected: exercise.targetText
        )

        shadowingResult = scoringResult
        exercisePhase = .feedback

        Logger.audio.info(
            "Shadowing scored: accuracy=\(String(format: "%.0f%%", scoringResult.accuracy * 100))"
        )
    }

    // MARK: - Retry

    /// Resets the exercise to the listen phase for another attempt.
    public func retryExercise() {
        audioService.stop()
        if isRecording {
            _ = speechService.stopRecording()
        }
        shadowingResult = nil
        exercisePhase = .listen
    }

    // MARK: - Cleanup

    /// Tears down resources when the view is dismissed.
    public func tearDown() {
        audioService.stop()
        speechService.tearDown()
    }
}
