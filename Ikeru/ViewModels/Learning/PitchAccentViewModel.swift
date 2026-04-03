import AVFoundation
import IkeruCore
import Observation
import os

// MARK: - PitchAccentViewModel

/// Manages the state and logic for pitch accent analysis exercises.
/// Coordinates between the analyzer service and the tracking service.
@MainActor
@Observable
public final class PitchAccentViewModel {

    // MARK: - Observable State

    /// The target pitch accent pattern for the current exercise.
    public private(set) var targetPattern: PitchAccentPattern?

    /// The result of the most recent analysis.
    public private(set) var result: PitchAccentResult?

    /// Whether an analysis is currently in progress.
    public private(set) var isAnalyzing: Bool = false

    /// Loading state for async operations.
    public private(set) var loadingState: LoadingState<Void> = .idle

    /// Per-pattern accuracy values.
    public private(set) var patternAccuracies: [PitchAccentType: Double] = [:]

    /// Per-pattern attempt counts.
    public private(set) var patternAttempts: [PitchAccentType: Int] = [:]

    /// Overall accuracy across all patterns.
    public private(set) var overallAccuracy: Double = 0.0

    // MARK: - Dependencies

    private let analyzer: any PitchAccentAnalyzer
    private let tracker: any PitchAccentTracking

    // MARK: - Init

    public init(
        analyzer: any PitchAccentAnalyzer = PitchAccentService(),
        tracker: any PitchAccentTracking = PitchAccentTracker()
    ) {
        self.analyzer = analyzer
        self.tracker = tracker
    }

    // MARK: - Public API

    /// Sets the target pattern for the current exercise.
    /// - Parameter pattern: The pitch accent pattern the learner should match.
    func setTarget(pattern: PitchAccentPattern) {
        targetPattern = pattern
        result = nil
        Logger.audio.info("Pitch accent target set: \(pattern.type.rawValue), morae=\(pattern.moraCount)")
    }

    /// Analyzes a recorded audio buffer against the current target pattern.
    /// - Parameter buffer: The PCM audio buffer from the learner's recording.
    func analyzeRecording(buffer: sending AVAudioPCMBuffer) async {
        guard !isAnalyzing else { return }
        guard let target = targetPattern else {
            Logger.audio.warning("Cannot analyze pitch — no target pattern set")
            return
        }

        isAnalyzing = true
        loadingState = .loading

        let analysisResult = await analyzer.analyzePitch(
            audioBuffer: buffer,
            targetPattern: target
        )

        result = analysisResult
        isAnalyzing = false
        loadingState = .loaded(())

        // Track the result
        await tracker.recordResult(
            pattern: target.type,
            wasCorrect: analysisResult.isCorrect
        )

        // Refresh accuracy stats
        await loadAccuracies()

        Logger.audio.info(
            "Pitch analysis complete: \(analysisResult.detectedPattern.rawValue) vs \(analysisResult.targetPattern.rawValue), correct=\(analysisResult.isCorrect)"
        )
    }

    /// Loads the current accuracy statistics from the tracker.
    func loadAccuracies() async {
        var accuracies: [PitchAccentType: Double] = [:]
        var attempts: [PitchAccentType: Int] = [:]

        for type in PitchAccentType.allCases {
            accuracies[type] = await tracker.accuracy(for: type)
            attempts[type] = await tracker.totalAttempts(for: type)
        }

        patternAccuracies = accuracies
        patternAttempts = attempts
        overallAccuracy = await tracker.overallAccuracy()
    }

    /// Resets the current exercise state for a new attempt.
    func reset() {
        result = nil
        isAnalyzing = false
        loadingState = .idle
    }
}
