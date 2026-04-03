import Testing
import SwiftUI
@testable import Ikeru
@testable import IkeruCore

@Suite("StrokeOrder Integration")
@MainActor
struct StrokeOrderIntegrationTests {

    // MARK: - Sample KanjiVG Data

    /// Simplified KanjiVG-style SVG for 十 (juu/ten) - cross shape, 2 strokes
    private let tenSVG = """
    <path d="M 14.25,48.5 C 21.75,46 42.5,42.75 54.5,41.75 C 66.5,40.75 83.75,41.25 93.25,42.25"/>
    <path d="M 52.25,16.75 C 52.75,18 53.25,20 53.25,21.25 C 53.25,22.5 53.25,72.25 53.25,80.75 C 53.25,89.25 50.75,93 50.75,93"/>
    """

    /// SVG for 一 (ichi/one) - single horizontal stroke
    private let ichiSVG = """
    <path d="M 14.25,48.5 C 21.75,46 42.5,42.75 54.5,41.75 C 66.5,40.75 83.75,41.25 93.25,42.25"/>
    """

    // MARK: - Full Pipeline: Load -> Parse -> Render -> Trace -> Evaluate

    @Test("Full pipeline: parse SVG, trace correctly, get passing result")
    func fullPipelineCorrectTrace() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        // Step 1: Load strokes
        await viewModel.loadStrokes(for: "十", svgData: tenSVG)
        #expect(viewModel.strokeData != nil)
        #expect(viewModel.strokeData?.strokes.count == 2)

        // Step 2: Watch animation
        viewModel.startAnimation()
        #expect(viewModel.mode == .watch)
        #expect(viewModel.isAnimating == true)

        // Step 3: Switch to practice
        viewModel.beginTracing()
        #expect(viewModel.mode == .practice)

        // Step 4: Trace strokes (using target points for "perfect" trace)
        let stroke1Points = viewModel.strokeData!.strokes[0].points
        viewModel.recordStroke(points: stroke1Points)
        #expect(viewModel.strokeResults.count == 1)
        #expect(viewModel.strokeResults[0].isPassing)

        let stroke2Points = viewModel.strokeData!.strokes[1].points
        viewModel.recordStroke(points: stroke2Points)
        #expect(viewModel.strokeResults.count == 2)
        #expect(viewModel.strokeResults[1].isPassing)

        // Step 5: Verify overall result
        #expect(viewModel.overallResult != nil)
        #expect(viewModel.overallResult!.passed == true)
    }

    // MARK: - Stroke Order Enforcement

    @Test("Out-of-order strokes are detected via accuracy scoring")
    func outOfOrderStrokesDetected() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "十", svgData: tenSVG)
        viewModel.beginTracing()

        // Trace stroke 2's path in stroke 1's position (wrong order)
        let stroke2Points = viewModel.strokeData!.strokes[1].points
        viewModel.recordStroke(points: stroke2Points)

        // The accuracy service compares against stroke 1's target,
        // so tracing stroke 2's path should score poorly
        #expect(viewModel.strokeResults.count == 1)
        // Vertical stroke traced when horizontal expected should be incorrect
        let result = viewModel.strokeResults[0]
        #expect(result == .incorrect || result == .approximatelyCorrect)
    }

    // MARK: - Accuracy Scoring

    @Test("Known good trace scores high")
    func knownGoodTraceScoresHigh() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "一", svgData: ichiSVG)
        viewModel.beginTracing()

        // Trace along the same path (perfect score)
        let targetPoints = viewModel.strokeData!.strokes[0].points
        viewModel.recordStroke(points: targetPoints)

        #expect(viewModel.strokeResults[0] == .correct)
    }

    @Test("Random scribble scores low")
    func randomScribbleScoresLow() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "一", svgData: ichiSVG)
        viewModel.beginTracing()

        // Random zigzag scribble
        let scribble = [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 5, y: 100),
            CGPoint(x: 100, y: 5),
        ]
        viewModel.recordStroke(points: scribble)

        #expect(viewModel.strokeResults[0] == .incorrect)
    }

    // MARK: - Offline Operation

    @Test("All data comes from bundled SVG strings, no network needed")
    func offlineOperation() async {
        // This test verifies that stroke data is parsed from strings,
        // not fetched from any network source
        let service = StrokeDataService()
        let result = service.parseStrokes(from: ichiSVG)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        // No network calls, no async dependencies beyond the SVG string
    }

    // MARK: - ViewModel State Transitions

    @Test("State transitions: load -> watch -> practice -> result")
    func stateTransitions() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        // Initial state
        #expect(viewModel.strokeData == nil)
        #expect(viewModel.mode == .watch)

        // After loading
        await viewModel.loadStrokes(for: "一", svgData: ichiSVG)
        #expect(viewModel.strokeData != nil)

        // Start watching
        viewModel.startAnimation()
        #expect(viewModel.isAnimating == true)
        #expect(viewModel.mode == .watch)

        // Switch to practice
        viewModel.beginTracing()
        #expect(viewModel.mode == .practice)
        #expect(viewModel.isAnimating == false)
        #expect(viewModel.currentStrokeIndex == 0)

        // Trace the single stroke
        let points = viewModel.strokeData!.strokes[0].points
        viewModel.recordStroke(points: points)

        // Result available
        #expect(viewModel.overallResult != nil)
        #expect(viewModel.overallResult!.passed == true)

        // Retry resets
        viewModel.retry()
        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.drawnStrokes.isEmpty)
        #expect(viewModel.overallResult == nil)
        #expect(viewModel.mode == .practice)
    }

    // MARK: - Replay After Practice

    @Test("Replay after practice switches back to watch mode")
    func replayAfterPractice() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "一", svgData: ichiSVG)
        viewModel.beginTracing()
        viewModel.recordStroke(points: viewModel.strokeData!.strokes[0].points)

        #expect(viewModel.overallResult != nil)

        // Replay should reset everything and go back to watch
        viewModel.replayAnimation()
        #expect(viewModel.mode == .watch)
        #expect(viewModel.isAnimating == true)
        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.drawnStrokes.isEmpty)
        #expect(viewModel.overallResult == nil)
    }
}
