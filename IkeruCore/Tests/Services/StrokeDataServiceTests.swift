import Testing
import Foundation
@testable import IkeruCore

@Suite("StrokeDataService")
struct StrokeDataServiceTests {

    // MARK: - SVG Path Parsing

    @Test("Parses simple M L path into two points")
    func parsesSimpleMoveLine() throws {
        let svg = "<path d=\"M 10,20 L 30,40\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        #expect(result!.strokes[0].points.count >= 2)
    }

    @Test("Parses multiple path elements as separate strokes")
    func parsesMultipleStrokes() throws {
        let svg = """
        <path d="M 10,20 L 30,40"/>
        <path d="M 50,60 L 70,80"/>
        <path d="M 15,25 L 35,45"/>
        """
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 3)
    }

    @Test("Parses cubic bezier C command")
    func parsesCubicBezier() throws {
        let svg = "<path d=\"M 10,20 C 15,25 20,30 30,40\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        #expect(result!.strokes[0].points.count >= 2)
    }

    @Test("Parses quadratic bezier Q command")
    func parsesQuadraticBezier() throws {
        let svg = "<path d=\"M 10,20 Q 20,30 30,40\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        #expect(result!.strokes[0].points.count >= 2)
    }

    @Test("Parses Z close path command without crash")
    func parsesClosePathCommand() throws {
        let svg = "<path d=\"M 10,20 L 30,40 L 50,20 Z\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
    }

    @Test("Parses complex KanjiVG-style SVG with multiple strokes")
    func parsesKanjiVGStyle() throws {
        // Simplified example of KanjiVG format for the character 一 (ichi)
        let svg = """
        <path d="M 14.25,48.5 C 21.75,46 42.5,42.75 54.5,41.75 C 66.5,40.75 83.75,41.25 93.25,42.25"/>
        """
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        #expect(result!.viewBoxWidth == 109)
        #expect(result!.viewBoxHeight == 109)
    }

    @Test("Preserves stroke order from SVG path sequence")
    func preservesStrokeOrder() throws {
        let svg = """
        <path d="M 10,10 L 90,10"/>
        <path d="M 50,10 L 50,90"/>
        """
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 2)
        // First stroke starts at (10,10)
        let firstPoint = result!.strokes[0].points.first!
        #expect(abs(firstPoint.x - 10) < 0.01)
        #expect(abs(firstPoint.y - 10) < 0.01)
        // Second stroke starts at (50,10)
        let secondPoint = result!.strokes[1].points.first!
        #expect(abs(secondPoint.x - 50) < 0.01)
        #expect(abs(secondPoint.y - 10) < 0.01)
    }

    @Test("Returns nil for empty SVG string")
    func returnsNilForEmptySVG() throws {
        let service = StrokeDataService()

        let result = service.parseStrokes(from: "", viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result == nil)
    }

    @Test("Returns nil for SVG with no path elements")
    func returnsNilForNoPathElements() throws {
        let service = StrokeDataService()

        let result = service.parseStrokes(from: "<svg><rect/></svg>", viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result == nil)
    }

    @Test("StrokeData contains correct viewBox dimensions")
    func strokeDataViewBox() throws {
        let svg = "<path d=\"M 10,20 L 30,40\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 200, viewBoxHeight: 200)

        #expect(result != nil)
        #expect(result!.viewBoxWidth == 200)
        #expect(result!.viewBoxHeight == 200)
    }

    @Test("Parses comma-separated and space-separated coordinates")
    func parsesCoordinateFormats() throws {
        // Comma-separated
        let svg1 = "<path d=\"M 10,20 L 30,40\"/>"
        // Space-separated
        let svg2 = "<path d=\"M 10 20 L 30 40\"/>"
        let service = StrokeDataService()

        let result1 = service.parseStrokes(from: svg1, viewBoxWidth: 109, viewBoxHeight: 109)
        let result2 = service.parseStrokes(from: svg2, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result1 != nil)
        #expect(result2 != nil)
        #expect(result1!.strokes.count == result2!.strokes.count)
    }

    // MARK: - StrokePathData Sampling

    @Test("Sampled points include start and end of stroke")
    func sampledPointsIncludeEndpoints() throws {
        let svg = "<path d=\"M 10,20 L 90,80\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        let stroke = result!.strokes[0]
        let sampled = stroke.sampledPoints(count: 10)
        #expect(sampled.count == 10)
        // First sampled point near start
        #expect(abs(sampled.first!.x - 10) < 1.0)
        #expect(abs(sampled.first!.y - 20) < 1.0)
        // Last sampled point near end
        #expect(abs(sampled.last!.x - 90) < 1.0)
        #expect(abs(sampled.last!.y - 80) < 1.0)
    }

    // MARK: - Multiple Commands in One Path

    @Test("Parses path with multiple commands chained")
    func parsesChainedCommands() throws {
        let svg = "<path d=\"M 10,20 C 15,25 20,30 30,40 C 35,45 40,50 50,60\"/>"
        let service = StrokeDataService()

        let result = service.parseStrokes(from: svg, viewBoxWidth: 109, viewBoxHeight: 109)

        #expect(result != nil)
        #expect(result!.strokes.count == 1)
        #expect(result!.strokes[0].points.count >= 3)
    }
}
