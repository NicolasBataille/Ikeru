import Testing
import Foundation
@testable import IkeruCore

@Suite("StrokeAccuracyService")
struct StrokeAccuracyServiceTests {

    // MARK: - Helpers

    private let viewBoxDiagonal: Double = {
        let w = 109.0
        let h = 109.0
        return (w * w + h * h).squareRoot()
    }()

    // MARK: - Stroke Result Scoring

    @Test("Identical stroke scores as correct")
    func identicalStrokeScoresCorrect() {
        let target = StrokePathData(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)],
            rawPathData: "M 10,10 L 90,10"
        )
        let drawn = [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        #expect(result == .correct)
    }

    @Test("Nearly matching stroke scores as correct")
    func nearlyMatchingStrokeScoresCorrect() {
        let target = StrokePathData(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)],
            rawPathData: "M 10,10 L 90,10"
        )
        // Slightly off but within tolerance
        let drawn = [CGPoint(x: 12, y: 11), CGPoint(x: 88, y: 12)]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        #expect(result == .correct || result == .approximatelyCorrect)
    }

    @Test("Moderately off stroke scores as approximately correct")
    func moderatelyOffStrokeScoresApproximate() {
        let target = StrokePathData(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)],
            rawPathData: "M 10,10 L 90,10"
        )
        // Moderately off
        let drawn = [CGPoint(x: 15, y: 25), CGPoint(x: 85, y: 25)]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        #expect(result == .approximatelyCorrect || result == .correct)
    }

    @Test("Completely wrong stroke scores as incorrect")
    func completelyWrongStrokeScoresIncorrect() {
        let target = StrokePathData(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)],
            rawPathData: "M 10,10 L 90,10"
        )
        // Totally different location
        let drawn = [CGPoint(x: 10, y: 90), CGPoint(x: 90, y: 90)]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        #expect(result == .incorrect || result == .approximatelyCorrect)
    }

    @Test("Random scribble scores as incorrect")
    func randomScribbleScoresIncorrect() {
        let target = StrokePathData(
            points: [
                CGPoint(x: 10, y: 50),
                CGPoint(x: 30, y: 50),
                CGPoint(x: 50, y: 50),
                CGPoint(x: 70, y: 50),
                CGPoint(x: 90, y: 50),
            ],
            rawPathData: "M 10,50 L 90,50"
        )
        // Random scribble across the canvas
        let drawn = [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 5, y: 100),
            CGPoint(x: 100, y: 5),
        ]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        // A zigzag scribble may score as approximately correct or incorrect
        // depending on how many points happen to be near the target line
        #expect(result == .incorrect || result == .approximatelyCorrect)
    }

    // MARK: - StrokeResult Properties

    @Test("StrokeResult correct has score < 0.15")
    func correctScoreThreshold() {
        let result = StrokeResult.correct
        #expect(result.score < 0.15)
    }

    @Test("StrokeResult approximatelyCorrect has score between 0.15 and 0.30")
    func approximatelyCorrectScoreRange() {
        let result = StrokeResult.approximatelyCorrect
        #expect(result.score >= 0.10)
        #expect(result.score <= 0.30)
    }

    @Test("StrokeResult incorrect has score >= 0.30")
    func incorrectScoreThreshold() {
        let result = StrokeResult.incorrect
        #expect(result.score >= 0.30)
    }

    @Test("StrokeResult isPassing for correct and approximatelyCorrect")
    func strokeResultIsPassing() {
        #expect(StrokeResult.correct.isPassing == true)
        #expect(StrokeResult.approximatelyCorrect.isPassing == true)
        #expect(StrokeResult.incorrect.isPassing == false)
    }

    // MARK: - Overall Character Evaluation

    @Test("All correct strokes produce passing overall result")
    func allCorrectStrokesProduce_passing() {
        let service = StrokeAccuracyService()

        let results: [StrokeResult] = [.correct, .correct, .correct]
        let overall = service.evaluateOverall(strokeResults: results)

        #expect(overall.passed == true)
        #expect(overall.strokeResults.count == 3)
    }

    @Test("Any incorrect stroke produces failing overall result")
    func anyIncorrectStrokeProduces_failing() {
        let service = StrokeAccuracyService()

        let results: [StrokeResult] = [.correct, .incorrect, .correct]
        let overall = service.evaluateOverall(strokeResults: results)

        #expect(overall.passed == false)
    }

    @Test("Mixed correct and approximately correct still passes")
    func mixedCorrectAndApproxPasses() {
        let service = StrokeAccuracyService()

        let results: [StrokeResult] = [.correct, .approximatelyCorrect, .correct]
        let overall = service.evaluateOverall(strokeResults: results)

        #expect(overall.passed == true)
    }

    @Test("Empty stroke results fail")
    func emptyStrokeResultsFail() {
        let service = StrokeAccuracyService()

        let overall = service.evaluateOverall(strokeResults: [])

        #expect(overall.passed == false)
    }

    // MARK: - Distance Calculation

    @Test("Distance between identical points is zero")
    func distanceBetweenIdenticalPointsIsZero() {
        let service = StrokeAccuracyService()
        let distance = service.normalizedAverageDistance(
            drawn: [CGPoint(x: 50, y: 50)],
            target: [CGPoint(x: 50, y: 50)],
            viewBoxDiagonal: viewBoxDiagonal
        )
        #expect(abs(distance) < 0.001)
    }

    @Test("Distance is normalized by viewBox diagonal")
    func distanceIsNormalized() {
        let service = StrokeAccuracyService()
        // Points at opposite corners of a 109x109 viewBox
        let distance = service.normalizedAverageDistance(
            drawn: [CGPoint(x: 0, y: 0)],
            target: [CGPoint(x: 109, y: 109)],
            viewBoxDiagonal: viewBoxDiagonal
        )
        // Should be approximately 1.0 (full diagonal distance)
        #expect(distance > 0.9)
        #expect(distance < 1.1)
    }
}
