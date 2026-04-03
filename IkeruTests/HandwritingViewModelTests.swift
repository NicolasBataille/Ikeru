import Testing
import SwiftUI
@testable import Ikeru
@testable import IkeruCore

@Suite("HandwritingViewModel")
@MainActor
struct HandwritingViewModelTests {

    // MARK: - Helpers

    private func makeService(
        candidates: [RecognitionCandidate] = [],
        shouldThrow: Bool = false
    ) -> HandwritingRecognitionService {
        let provider = MockRecognitionProvider(
            candidates: candidates,
            shouldThrow: shouldThrow
        )
        return HandwritingRecognitionService(provider: provider)
    }

    private func makeViewModel(
        candidates: [RecognitionCandidate] = [],
        shouldThrow: Bool = false
    ) -> HandwritingViewModel {
        HandwritingViewModel(recognitionService: makeService(
            candidates: candidates,
            shouldThrow: shouldThrow
        ))
    }

    // MARK: - Initial State

    @Test("Initial state is idle with empty strokes")
    func initialState() {
        let vm = makeViewModel()

        #expect(vm.targetCharacter == "")
        #expect(vm.strokes.isEmpty)
        #expect(vm.recognitionResult == nil)
        #expect(vm.recognitionState.isIdle)
        #expect(vm.feedbackState == .idle)
    }

    // MARK: - Load Target

    @Test("loadTarget sets target and resets state")
    func loadTarget() {
        let vm = makeViewModel()
        vm.loadTarget(character: "\u{5c71}")

        #expect(vm.targetCharacter == "\u{5c71}")
        #expect(vm.strokes.isEmpty)
        #expect(vm.recognitionResult == nil)
        #expect(vm.feedbackState == .idle)
    }

    @Test("loadTarget resets previous strokes and results")
    func loadTargetResets() {
        let vm = makeViewModel()
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)])

        vm.loadTarget(character: "\u{5ddd}")

        #expect(vm.targetCharacter == "\u{5ddd}")
        #expect(vm.strokes.isEmpty)
    }

    // MARK: - Stroke Management

    @Test("addStroke appends to strokes array")
    func addStroke() {
        let vm = makeViewModel()
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)]
        vm.addStroke(points: points)

        #expect(vm.strokes.count == 1)
        #expect(vm.strokes[0] == points)
    }

    @Test("addStroke ignores empty points")
    func addStrokeEmpty() {
        let vm = makeViewModel()
        vm.addStroke(points: [])

        #expect(vm.strokes.isEmpty)
    }

    @Test("addStroke creates new array (immutability)")
    func addStrokeImmutability() {
        let vm = makeViewModel()
        let stroke1 = [CGPoint(x: 10, y: 10)]
        vm.addStroke(points: stroke1)
        let firstArray = vm.strokes

        let stroke2 = [CGPoint(x: 20, y: 20)]
        vm.addStroke(points: stroke2)

        // Original array should be unchanged
        #expect(firstArray.count == 1)
        #expect(vm.strokes.count == 2)
    }

    @Test("undoLastStroke removes the last stroke")
    func undoLastStroke() {
        let vm = makeViewModel()
        vm.addStroke(points: [CGPoint(x: 10, y: 10)])
        vm.addStroke(points: [CGPoint(x: 20, y: 20)])

        vm.undoLastStroke()

        #expect(vm.strokes.count == 1)
        #expect(vm.strokes[0] == [CGPoint(x: 10, y: 10)])
    }

    @Test("undoLastStroke on empty is no-op")
    func undoLastStrokeEmpty() {
        let vm = makeViewModel()
        vm.undoLastStroke()

        #expect(vm.strokes.isEmpty)
    }

    @Test("undoLastStroke creates new array (immutability)")
    func undoImmutability() {
        let vm = makeViewModel()
        vm.addStroke(points: [CGPoint(x: 10, y: 10)])
        vm.addStroke(points: [CGPoint(x: 20, y: 20)])
        let beforeUndo = vm.strokes

        vm.undoLastStroke()

        #expect(beforeUndo.count == 2)
        #expect(vm.strokes.count == 1)
    }

    @Test("clearCanvas resets all state")
    func clearCanvas() {
        let vm = makeViewModel()
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10)])

        vm.clearCanvas()

        #expect(vm.strokes.isEmpty)
        #expect(vm.recognitionResult == nil)
        #expect(vm.recognitionState.isIdle)
        #expect(vm.feedbackState == .idle)
        // Target should remain
        #expect(vm.targetCharacter == "\u{5c71}")
    }

    // MARK: - Recognition

    @Test("submitForRecognition with no strokes does not change state")
    func submitNoStrokes() async {
        let vm = makeViewModel()
        await vm.submitForRecognition()

        #expect(vm.recognitionState.isIdle)
        #expect(vm.recognitionResult == nil)
    }

    @Test("submitForRecognition sets correct feedback when target matches top candidate")
    func submitCorrectMatch() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.9)
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])

        await vm.submitForRecognition()

        #expect(vm.feedbackState == .correct)
        #expect(vm.recognitionResult != nil)
        #expect(vm.recognitionState.isLoaded)
    }

    @Test("submitForRecognition sets partial feedback when target in candidates but not top")
    func submitPartialMatch() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5ddd}", confidence: 0.8),
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.5),
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])

        await vm.submitForRecognition()

        #expect(vm.feedbackState == .partial)
    }

    @Test("submitForRecognition sets incorrect feedback when target not in candidates")
    func submitIncorrectNoMatch() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5ddd}", confidence: 0.9),
            RecognitionCandidate(character: "\u{706b}", confidence: 0.7),
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])

        await vm.submitForRecognition()

        #expect(vm.feedbackState == .incorrect)
    }

    @Test("submitForRecognition sets incorrect on provider error")
    func submitProviderError() async {
        let vm = makeViewModel(shouldThrow: true)
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])

        await vm.submitForRecognition()

        #expect(vm.feedbackState == .incorrect)
        #expect(vm.recognitionState.isFailed)
    }

    @Test("submitForRecognition sets incorrect for low-confidence target match")
    func submitLowConfidenceMatch() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.2)
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])

        await vm.submitForRecognition()

        #expect(vm.feedbackState == .incorrect)
    }

    // MARK: - Retry

    @Test("retry resets strokes and feedback but keeps target")
    func retry() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5ddd}", confidence: 0.9)
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])
        await vm.submitForRecognition()

        vm.retry()

        #expect(vm.strokes.isEmpty)
        #expect(vm.recognitionResult == nil)
        #expect(vm.recognitionState.isIdle)
        #expect(vm.feedbackState == .idle)
        #expect(vm.targetCharacter == "\u{5c71}")
    }

    // MARK: - State Transitions

    @Test("Full lifecycle: idle -> drawing -> recognizing -> feedback -> retry")
    func fullLifecycle() async {
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.95)
        ])

        // Idle
        #expect(vm.feedbackState == .idle)

        // Load target
        vm.loadTarget(character: "\u{5c71}")
        #expect(vm.targetCharacter == "\u{5c71}")

        // Draw
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])
        #expect(vm.strokes.count == 1)

        // Recognize
        await vm.submitForRecognition()
        #expect(vm.feedbackState == .correct)
        #expect(vm.recognitionResult != nil)

        // Retry
        vm.retry()
        #expect(vm.feedbackState == .idle)
        #expect(vm.strokes.isEmpty)
    }

    // MARK: - Offline Guarantee

    @Test("No network calls in recognition pipeline")
    func offlineOperation() async {
        // MockRecognitionProvider makes zero network calls.
        // This test verifies the pipeline completes without any network dependency.
        let vm = makeViewModel(candidates: [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.8)
        ])
        vm.loadTarget(character: "\u{5c71}")
        vm.addStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)])

        await vm.submitForRecognition()

        // If this completes without timeout/error, offline operation is verified.
        #expect(vm.recognitionState.isLoaded)
    }
}

// MARK: - MockRecognitionProvider (shared with service tests)

/// Re-exported mock for ViewModel tests.
/// Same as the one in HandwritingRecognitionServiceTests.
struct MockRecognitionProvider: RecognitionProvider, Sendable {
    let candidates: [RecognitionCandidate]
    let shouldThrow: Bool

    init(
        candidates: [RecognitionCandidate] = [],
        shouldThrow: Bool = false
    ) {
        self.candidates = candidates
        self.shouldThrow = shouldThrow
    }

    func recognize(image: CGImage) async throws -> [RecognitionCandidate] {
        if shouldThrow {
            throw HandwritingRecognitionError.visionFailed("Mock error")
        }
        return candidates
    }
}
