import Testing
import SwiftUI
@testable import Ikeru
@testable import IkeruCore

@Suite("StrokeOrderViewModel")
@MainActor
struct StrokeOrderViewModelTests {

    // MARK: - Helpers

    private func makeSampleStrokeData() -> StrokeData {
        StrokeData(
            strokes: [
                StrokePathData(
                    points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
                    rawPathData: "M 10,50 L 90,50"
                ),
                StrokePathData(
                    points: [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)],
                    rawPathData: "M 50,10 L 50,90"
                ),
            ],
            viewBoxWidth: 109,
            viewBoxHeight: 109
        )
    }

    private func makeService(svgData: String = "") -> MockStrokeDataService {
        MockStrokeDataService(svgData: svgData)
    }

    // MARK: - Initial State

    @Test("Initial state is idle with watch mode")
    func initialState() {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        #expect(viewModel.mode == .watch)
        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.drawnStrokes.isEmpty)
        #expect(viewModel.strokeResults.isEmpty)
        #expect(viewModel.overallResult == nil)
        #expect(viewModel.isAnimating == false)
        #expect(viewModel.strokeData == nil)
    }

    // MARK: - Loading

    @Test("loadStrokes sets strokeData when SVG is valid")
    func loadStrokesSuccess() async {
        let svg = """
        <path d="M 10,50 L 90,50"/>
        <path d="M 50,10 L 50,90"/>
        """
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "十", svgData: svg)

        #expect(viewModel.strokeData != nil)
        #expect(viewModel.strokeData?.strokes.count == 2)
        #expect(viewModel.character == "十")
    }

    @Test("loadStrokes sets nil strokeData for empty SVG")
    func loadStrokesEmptySVG() async {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        await viewModel.loadStrokes(for: "?", svgData: "")

        #expect(viewModel.strokeData == nil)
    }

    // MARK: - Mode Transitions

    @Test("beginTracing switches to practice mode")
    func beginTracingSwitchesMode() async {
        let svg = "<path d=\"M 10,50 L 90,50\"/>"
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "一", svgData: svg)

        viewModel.beginTracing()

        #expect(viewModel.mode == .practice)
        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.isAnimating == false)
    }

    @Test("replayAnimation switches to watch mode and resets")
    func replayAnimationResetsToWatch() async {
        let svg = "<path d=\"M 10,50 L 90,50\"/>"
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "一", svgData: svg)
        viewModel.beginTracing()

        viewModel.replayAnimation()

        #expect(viewModel.mode == .watch)
        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.isAnimating == true)
    }

    // MARK: - Practice Mode

    @Test("recordStroke stores drawn points and advances stroke index")
    func recordStrokeAdvances() async {
        let svg = """
        <path d="M 10,50 L 90,50"/>
        <path d="M 50,10 L 50,90"/>
        """
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "十", svgData: svg)
        viewModel.beginTracing()

        viewModel.recordStroke(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])

        #expect(viewModel.drawnStrokes.count == 1)
        #expect(viewModel.currentStrokeIndex == 1)
        #expect(viewModel.strokeResults.count == 1)
    }

    @Test("Recording all strokes triggers overall evaluation")
    func recordAllStrokesTriggersEvaluation() async {
        let svg = """
        <path d="M 10,50 L 90,50"/>
        <path d="M 50,10 L 50,90"/>
        """
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "十", svgData: svg)
        viewModel.beginTracing()

        // Trace both strokes
        viewModel.recordStroke(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])
        viewModel.recordStroke(points: [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)])

        #expect(viewModel.drawnStrokes.count == 2)
        #expect(viewModel.strokeResults.count == 2)
        #expect(viewModel.overallResult != nil)
    }

    // MARK: - Retry

    @Test("retry resets practice state")
    func retryResetsPracticeState() async {
        let svg = "<path d=\"M 10,50 L 90,50\"/>"
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "一", svgData: svg)
        viewModel.beginTracing()
        viewModel.recordStroke(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)])

        viewModel.retry()

        #expect(viewModel.currentStrokeIndex == 0)
        #expect(viewModel.drawnStrokes.isEmpty)
        #expect(viewModel.strokeResults.isEmpty)
        #expect(viewModel.overallResult == nil)
        #expect(viewModel.mode == .practice)
    }

    // MARK: - Animation

    @Test("startAnimation sets isAnimating to true")
    func startAnimationSetsFlag() async {
        let svg = "<path d=\"M 10,50 L 90,50\"/>"
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "一", svgData: svg)

        viewModel.startAnimation()

        #expect(viewModel.isAnimating == true)
    }

    @Test("advanceAnimationStroke increments stroke index")
    func advanceAnimationStrokeIncrements() async {
        let svg = """
        <path d="M 10,50 L 90,50"/>
        <path d="M 50,10 L 50,90"/>
        """
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "十", svgData: svg)
        viewModel.startAnimation()

        viewModel.advanceAnimationStroke()

        #expect(viewModel.currentStrokeIndex == 1)
    }

    @Test("advanceAnimationStroke stops when all strokes complete")
    func advanceAnimationStopsAtEnd() async {
        let svg = "<path d=\"M 10,50 L 90,50\"/>"
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )
        await viewModel.loadStrokes(for: "一", svgData: svg)
        viewModel.startAnimation()

        viewModel.advanceAnimationStroke()

        #expect(viewModel.isAnimating == false)
    }

    // MARK: - Speed

    @Test("Default animation speed is normal")
    func defaultSpeedIsNormal() {
        let viewModel = StrokeOrderViewModel(
            strokeDataService: StrokeDataService(),
            accuracyService: StrokeAccuracyService()
        )

        #expect(viewModel.animationSpeed == .normal)
    }
}

// MARK: - Mock

/// Simple mock for testing (not currently used since StrokeDataService is stateless,
/// but provided for extensibility).
private struct MockStrokeDataService {
    let svgData: String
}
