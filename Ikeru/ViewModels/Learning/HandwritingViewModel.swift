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
    /// Recogniser was confident about *something* (a candidate cleared the
    /// partial threshold) but it was not the target — an honest miss.
    case incorrect
    /// The recogniser could not produce a usable verdict: it errored, returned
    /// no candidates, or its best guess fell below the partial-confidence
    /// threshold. We DO NOT fabricate a pass (or a fail) from a scribble the
    /// machine couldn't read — the learner self-grades honestly instead.
    case unavailable
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
            feedbackState = Self.evaluateFeedback(
                candidates: result.candidates,
                target: targetCharacter,
                correctThreshold: correctThreshold,
                partialThreshold: partialThreshold
            )

            Logger.content.info(
                "Recognition for '\(self.targetCharacter)': \(String(describing: self.feedbackState)) in \(result.formattedDuration)"
            )
        } catch {
            // A thrown error means the recogniser is unavailable (Vision failed
            // or is missing). Do NOT mark the attempt incorrect — the machine
            // never rendered a verdict — surface the honest self-grade path.
            recognitionState = .failed(error)
            feedbackState = .unavailable
            Logger.content.error(
                "Recognition unavailable for '\(self.targetCharacter)': \(error.localizedDescription)"
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

    /// Pure decision: map recognition candidates (sorted by confidence
    /// descending) against the target to a feedback tier. Kept `nonisolated
    /// static` so it can be unit-tested directly without a MainActor view model.
    ///
    /// Honesty contract (remediation 7.8): when the recogniser produces no
    /// usable read — no candidates, or a top candidate below the partial
    /// threshold — we return `.unavailable` (self-grade) rather than fabricating
    /// a `.correct`/`.partial` pass or silently stamping `.incorrect`. A pass is
    /// only ever returned when the recogniser was genuinely confident the target
    /// was drawn.
    nonisolated static func evaluateFeedback(
        candidates: [RecognitionCandidate],
        target: String,
        correctThreshold: Double,
        partialThreshold: Double
    ) -> HandwritingFeedbackState {
        // Pick the most-confident candidate by value, NOT by array position —
        // the honesty verdict must not depend on the provider happening to sort
        // its output. If even the best guess is below the partial threshold, the
        // machine has no usable verdict → route to self-grade.
        guard let topCandidate = candidates.max(by: { $0.confidence < $1.confidence }),
              topCandidate.confidence >= partialThreshold else {
            return .unavailable
        }

        // Best candidate is the target at high confidence → a real pass.
        if topCandidate.character == target,
           topCandidate.confidence >= correctThreshold {
            return .correct
        }

        // The target appears among candidates with at least partial confidence
        // (use its most-confident occurrence, again independent of order).
        if let candidate = candidates
            .filter({ $0.character == target })
            .max(by: { $0.confidence < $1.confidence }),
           candidate.confidence >= partialThreshold {
            return .partial
        }

        // Recogniser was confident about something else → an honest miss.
        return .incorrect
    }
}
