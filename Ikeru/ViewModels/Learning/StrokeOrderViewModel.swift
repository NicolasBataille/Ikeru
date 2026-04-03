import SwiftUI
import IkeruCore
import os

// MARK: - StrokeLoadError

enum StrokeLoadError: LocalizedError {
    case noDataAvailable(String)

    var errorDescription: String? {
        switch self {
        case .noDataAvailable(let character):
            "No stroke data available for '\(character)'"
        }
    }
}

// MARK: - StrokeOrderViewModel

@MainActor
@Observable
public final class StrokeOrderViewModel {

    // MARK: - Published State

    /// Loading state for stroke data.
    public private(set) var loadingState: LoadingState<StrokeData> = .idle

    /// The character being practiced.
    public private(set) var character: String = ""

    /// Current stroke index (used for both animation and practice).
    public private(set) var currentStrokeIndex: Int = 0

    /// Current exercise mode.
    public private(set) var mode: StrokeExerciseMode = .watch

    /// Drawn strokes from the learner (practice mode).
    public private(set) var drawnStrokes: [[CGPoint]] = []

    /// Per-stroke accuracy results (practice mode).
    public private(set) var strokeResults: [StrokeResult] = []

    /// Overall character evaluation result (set after all strokes are traced).
    public private(set) var overallResult: CharacterResult?

    /// Whether the stroke animation is currently playing.
    public private(set) var isAnimating: Bool = false

    /// Selected animation speed.
    public var animationSpeed: StrokeAnimationSpeed = .normal

    /// Convenience accessor for the loaded stroke data.
    public var strokeData: StrokeData? {
        loadingState.value
    }

    // MARK: - Dependencies

    private let strokeDataService: StrokeDataService
    private let accuracyService: StrokeAccuracyService

    // MARK: - Init

    public init(
        strokeDataService: StrokeDataService = StrokeDataService(),
        accuracyService: StrokeAccuracyService = StrokeAccuracyService()
    ) {
        self.strokeDataService = strokeDataService
        self.accuracyService = accuracyService
    }

    // MARK: - Loading

    /// Load stroke data for a character from raw SVG data.
    /// - Parameters:
    ///   - character: The character to display.
    ///   - svgData: Raw SVG string with path elements.
    public func loadStrokes(for character: String, svgData: String) async {
        self.character = character
        loadingState = .loading

        let parsed = strokeDataService.parseStrokes(from: svgData)

        if let parsed {
            loadingState = .loaded(parsed)
            Logger.content.info("Loaded \(parsed.strokes.count) strokes for '\(character)'")
        } else {
            loadingState = .failed(StrokeLoadError.noDataAvailable(character))
            Logger.content.warning("No stroke data available for '\(character)'")
        }
    }

    // MARK: - Animation Control

    /// Start the stroke order animation from the current position.
    public func startAnimation() {
        guard strokeData != nil else { return }
        isAnimating = true
        Logger.ui.debug("Started stroke animation for '\(self.character)'")
    }

    /// Advance to the next stroke in the animation sequence.
    /// Called when the current stroke animation completes.
    public func advanceAnimationStroke() {
        guard let strokeData, mode == .watch else { return }

        let nextIndex = currentStrokeIndex + 1
        if nextIndex < strokeData.strokes.count {
            currentStrokeIndex = nextIndex
        } else {
            // Animation complete
            isAnimating = false
            Logger.ui.debug("Stroke animation complete for '\(self.character)'")
        }
    }

    /// Replay the animation from the beginning.
    public func replayAnimation() {
        mode = .watch
        currentStrokeIndex = 0
        drawnStrokes = []
        strokeResults = []
        overallResult = nil
        isAnimating = true
        Logger.ui.debug("Replaying stroke animation for '\(self.character)'")
    }

    // MARK: - Practice Mode

    /// Switch to guided tracing practice mode.
    public func beginTracing() {
        mode = .practice
        currentStrokeIndex = 0
        drawnStrokes = []
        strokeResults = []
        overallResult = nil
        isAnimating = false
        Logger.ui.debug("Switched to practice mode for '\(self.character)'")
    }

    /// Record a drawn stroke and evaluate its accuracy.
    /// - Parameter points: Touch points captured from the learner's finger input.
    public func recordStroke(points: [CGPoint]) {
        guard let strokeData, currentStrokeIndex < strokeData.strokes.count else { return }

        let targetStroke = strokeData.strokes[currentStrokeIndex]

        // Store drawn points
        drawnStrokes.append(points)

        // Evaluate accuracy
        let result = accuracyService.evaluateStroke(
            drawn: points,
            target: targetStroke,
            viewBoxDiagonal: strokeData.viewBoxDiagonal
        )
        strokeResults.append(result)

        Logger.ui.debug(
            "Stroke \(self.currentStrokeIndex) result: \(String(describing: result)), score: \(result.score)"
        )

        // Advance to next stroke
        let nextIndex = currentStrokeIndex + 1
        if nextIndex < strokeData.strokes.count {
            currentStrokeIndex = nextIndex
        } else {
            // All strokes completed - evaluate overall
            let overall = accuracyService.evaluateOverall(strokeResults: strokeResults)
            overallResult = overall
            Logger.ui.info(
                "Character '\(self.character)' tracing complete: passed=\(overall.passed), avgScore=\(overall.averageScore)"
            )
        }
    }

    /// Reset the practice canvas for another attempt.
    public func retry() {
        currentStrokeIndex = 0
        drawnStrokes = []
        strokeResults = []
        overallResult = nil
        // Stay in practice mode
        mode = .practice
        Logger.ui.debug("Retry tracing for '\(self.character)'")
    }
}
