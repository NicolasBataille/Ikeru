import SwiftUI
import IkeruCore
import os

// MARK: - Feedback State

/// The feedback state after handwriting recognition.
public enum HandwritingFeedbackState: Sendable, Equatable {
    /// No recognition attempted yet.
    case idle
    /// Top candidate matches target with high confidence (>= 0.7).
    case correct
    /// Target found in candidates but not top match, or lower confidence (>= 0.3).
    case partial
    /// Target not found in candidates or all below threshold.
    case incorrect
}

// MARK: - HandwritingViewModel

@MainActor
@Observable
public final class HandwritingViewModel {

    // MARK: - State

    /// The target character the learner should write.
    public private(set) var targetCharacter: String = ""

    /// All strokes drawn on the canvas. Each stroke is an array of points.
    public private(set) var strokes: [[CGPoint]] = []

    /// The recognition result after submission.
    public private(set) var recognitionResult: RecognitionResult?

    /// Loading state for the recognition operation.
    public private(set) var recognitionState: LoadingState<RecognitionResult> = .idle

    /// Feedback state derived from recognition result vs target.
    public private(set) var feedbackState: HandwritingFeedbackState = .idle

    /// Canvas size used for rendering strokes to image.
    public var canvasSize: CGFloat = 300

    // MARK: - Confidence Thresholds

    private let correctThreshold: Double = 0.7
    private let partialThreshold: Double = 0.3

    // MARK: - Dependencies

    private let recognitionService: HandwritingRecognitionService

    // MARK: - Init

    public init(recognitionService: HandwritingRecognitionService = HandwritingRecognitionService()) {
        self.recognitionService = recognitionService
    }

    // MARK: - Target

    /// Set the target character for this exercise.
    /// - Parameter character: The kanji or kana character to practice.
    public func loadTarget(character: String) {
        targetCharacter = character
        strokes = []
        recognitionResult = nil
        recognitionState = .idle
        feedbackState = .idle
        Logger.ui.debug("Loaded target character: '\(character)'")
    }

    // MARK: - Stroke Management

    /// Add a new completed stroke to the canvas.
    /// Creates a new array (immutable pattern).
    /// - Parameter points: The touch points captured for this stroke.
    public func addStroke(points: [CGPoint]) {
        guard !points.isEmpty else { return }
        strokes = strokes + [points]
        Logger.ui.debug("Added stroke \(self.strokes.count) with \(points.count) points")
    }

    /// Remove the last stroke from the canvas.
    /// Creates a new array (immutable pattern).
    public func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes = Array(strokes.dropLast())
        Logger.ui.debug("Undo stroke, \(self.strokes.count) strokes remaining")
    }

    /// Clear all strokes from the canvas.
    public func clearCanvas() {
        strokes = []
        recognitionResult = nil
        recognitionState = .idle
        feedbackState = .idle
        Logger.ui.debug("Canvas cleared for '\(self.targetCharacter)'")
    }

    // MARK: - Recognition

    /// Submit current strokes for recognition.
    /// Renders strokes to image, runs recognition, and evaluates against target.
    public func submitForRecognition() async {
        guard !strokes.isEmpty else {
            Logger.ui.warning("Submit called with no strokes")
            return
        }

        recognitionState = .loading

        do {
            let result = try await recognitionService.recognize(
                strokes: strokes,
                canvasSize: canvasSize
            )

            recognitionResult = result
            recognitionState = .loaded(result)
            feedbackState = evaluateFeedback(result: result)

            Logger.content.info(
                "Recognition for '\(self.targetCharacter)': " +
                "\(self.feedbackState) in \(result.formattedDuration)"
            )
        } catch {
            recognitionState = .failed(error)
            feedbackState = .incorrect
            Logger.content.error(
                "Recognition failed for '\(self.targetCharacter)': " +
                "\(error.localizedDescription)"
            )
        }
    }

    /// Reset the exercise for another attempt.
    public func retry() {
        strokes = []
        recognitionResult = nil
        recognitionState = .idle
        feedbackState = .idle
        Logger.ui.debug("Retry for '\(self.targetCharacter)'")
    }

    // MARK: - Feedback Evaluation

    /// Determine feedback state by comparing recognition candidates against the target.
    private func evaluateFeedback(result: RecognitionResult) -> HandwritingFeedbackState {
        guard !result.candidates.isEmpty else { return .incorrect }

        // Check if top candidate matches target with high confidence
        if let topCandidate = result.candidates.first,
           topCandidate.character == targetCharacter,
           topCandidate.confidence >= correctThreshold {
            return .correct
        }

        // Check if target appears anywhere in candidates with partial confidence
        let targetCandidate = result.candidates.first { $0.character == targetCharacter }
        if let candidate = targetCandidate, candidate.confidence >= partialThreshold {
            return .partial
        }

        return .incorrect
    }
}
