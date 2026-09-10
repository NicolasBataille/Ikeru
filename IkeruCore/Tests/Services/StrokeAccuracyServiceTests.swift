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

        #expect(result == .correct)
    }

    @Test("Moderately off stroke scores as approximately correct")
    func moderatelyOffStrokeScoresApproximate() {
        let target = StrokePathData(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)],
            rawPathData: "M 10,10 L 90,10"
        )
        // Moderately off: the whole stroke sits 15 units below its target and
        // is 10 units short. Measured — mean 0.099 (inside the 0.15 `.correct`
        // bar, which is why this used to grade `.correct` while its own name
        // said otherwise), endpoint gap 0.103 (outside the 0.08 bar). The
        // endpoint term is what demotes it.
        let drawn = [CGPoint(x: 15, y: 25), CGPoint(x: 85, y: 25)]
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: drawn,
            target: target,
            viewBoxDiagonal: viewBoxDiagonal
        )

        #expect(result == .approximatelyCorrect)
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

        #expect(result == .incorrect)
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

        // Measured: mean 0.289, peak 0.507, length ratio 4.53, endpoint gap
        // 0.299. Three of the four terms veto it. The mean alone put it at
        // 0.289 — a hair under the old 0.30 bar, i.e. "approximately correct",
        // which is how a learner scribbling nonsense used to be told they were
        // close.
        #expect(result == .incorrect)
    }

    // MARK: - Named Scenarios Against the Shipped 一

    // Everything below traces against the *real* KanjiVG path shipped in
    // `Ikeru/Resources/ContentBundles/n5-content.sqlite` for 一, not a
    // hand-written straight line. That matters: the synthetic two-point
    // fixtures above are symmetric and forgiving, the shipped path droops
    // (starts at y=54.25, ends at y=50.0) and parses to 25 points.
    //
    // No genuine human stroke has ever been recorded in this repo — every
    // fixture here is synthetic, so these scenarios are constructed failures,
    // not observed ones. `StrokeTracingView` now carries an
    // `IKERU_DEV_TOOLS`-gated capture hook so a device pass can replace them
    // with real ink.

    /// The shipped stroke for 一, verbatim from `n5-content.sqlite`.
    private static let shippedIchiPath =
        #"<path d="M 11,54.25 C 14.19,54.87 17.25,55 20.73,54.75 C 41.37,53.25 71.12,49.63 89.31,49.51 C 92.91,49.49 95.08,49.75 96.88,50"/>"#

    private func shippedIchi() throws -> (target: StrokePathData, diagonal: Double) {
        let data = try #require(StrokeDataService().parseStrokes(from: Self.shippedIchiPath))
        return (try #require(data.strokes.first), data.viewBoxDiagonal)
    }

    /// Deterministic noise. A seeded LCG rather than `Double.random` so a
    /// failure is reproducible: a flaky accuracy test teaches nothing.
    private struct SeededNoise {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func symmetric(_ amplitude: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state >> 11) & 0xFFFF_FFFF) / Double(0xFFFF_FFFF)
            return (unit * 2 - 1) * amplitude
        }
    }

    @Test("A stationary tap at the centre scores as incorrect")
    func stationaryTapScoresIncorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // The centre of the 109×109 viewBox. This is THE case that proves the
        // defect was never a matter of threshold height: measured mean
        // distance 0.1489, i.e. *under* the 0.15 `.correct` bar and better
        // than an honest stroke offset by 13 units. `resamplePoints` turns one
        // point into 20 copies of itself, so the mean distance collapses into
        // "how far is your ink from the target's centroid" — and drawing
        // nothing at all is the cheapest way to sit on a centroid.
        let tap = [CGPoint(x: 54.5, y: 54.5)]

        let measures = service.measure(
            drawn: tap,
            target: target.sampledPoints(count: 20),
            viewBoxDiagonal: diagonal
        )
        #expect(abs(measures.meanDistance - 0.1489) < 0.001)
        #expect(measures.meanDistance < 0.15) // would have passed on mean alone
        #expect(measures.lengthRatio == 0)
        #expect(measures.endpointGap > 0.18)

        let result = service.evaluateStroke(drawn: tap, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .incorrect)
    }

    @Test("The 4-point diagonal scribble scores as incorrect")
    func diagonalScribbleScoresIncorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // Measured: mean 0.2936 (under the old 0.30 bar → `.approximatelyCorrect`),
        // peak 0.502, length ratio 4.21, endpoint gap 0.322.
        let scribble = [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 5, y: 100),
            CGPoint(x: 100, y: 5),
        ]

        let result = service.evaluateStroke(drawn: scribble, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .incorrect)
    }

    @Test("A vertical line through the centre of 一 scores as incorrect")
    func verticalLineScoresIncorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // The case the task singles out: its arc length is close to 一's, so
        // the length ratio (measured 1.033) does NOT reject it. Measured mean
        // 0.2201 — comfortably inside the old 0.30 bar. What rejects it is the
        // endpoint gap (0.420) and the peak distance (0.420).
        let vertical = [CGPoint(x: 54.5, y: 10), CGPoint(x: 54.5, y: 99)]

        let measures = service.measure(
            drawn: vertical,
            target: target.sampledPoints(count: 20),
            viewBoxDiagonal: diagonal
        )
        #expect(measures.lengthRatio > 0.95 && measures.lengthRatio < 1.10)
        #expect(measures.meanDistance < 0.30) // the old scorer's whole test

        let result = service.evaluateStroke(drawn: vertical, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .incorrect)
    }

    @Test("The reference stroke traced backwards scores as incorrect")
    func reversedStrokeScoresIncorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // Reversal is graded `.incorrect`, not `.approximatelyCorrect`: 筆順
        // practice exists to train direction, so an end-to-start stroke is not
        // a rough version of the right motion, it is the wrong motion.
        // Measured: mean 0.2940, length ratio 1.000 (identical ink!), endpoint
        // gap 0.558. Only the endpoint and peak terms can see the difference.
        let backwards = Array(target.points.reversed())

        let measures = service.measure(
            drawn: backwards,
            target: target.sampledPoints(count: 20),
            viewBoxDiagonal: diagonal
        )
        #expect(abs(measures.lengthRatio - 1.0) < 0.01)
        #expect(measures.meanDistance < 0.30)

        let result = service.evaluateStroke(drawn: backwards, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .incorrect)
    }

    @Test("The exact reference trace still scores as correct")
    func exactReferenceTraceScoresCorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        let result = service.evaluateStroke(
            drawn: target.points,
            target: target,
            viewBoxDiagonal: diagonal
        )
        #expect(result == .correct)
    }

    @Test("An honest but imperfect stroke still scores as correct")
    func honestImperfectStrokeScoresCorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // Two independent kinds of human error, applied together:
        //
        // (a) per-point jitter of ±2 viewBox units. On a 300pt canvas one
        //     viewBox unit is ~2.75pt, so this is ±5.5pt of tremor on every
        //     sample — more than iOS touch delivers after its own smoothing.
        // (b) a uniform offset of +6 units on both axes (8.5 units diagonally,
        //     ~23pt on screen): the whole stroke placed low and to the right,
        //     the commonest sincere error when a finger hides the guide.
        //
        // Magnitudes chosen to be the worst a sincere learner plausibly
        // produces while still being obviously the right stroke. Measured:
        // mean 0.052 (bar 0.15), peak 0.078 (bar 0.22), ratio 1.044 (band
        // 0.60-2.00), endpoint gap 0.044 (bar 0.08). The tightest of the four
        // sits 1.8× inside its bound.
        var noise = SeededNoise(seed: 7)
        let honest = target.points.map { point in
            CGPoint(
                x: point.x + 6.0 + noise.symmetric(2.0),
                y: point.y + 6.0 + noise.symmetric(2.0)
            )
        }

        let measures = service.measure(
            drawn: honest,
            target: target.sampledPoints(count: 20),
            viewBoxDiagonal: diagonal
        )
        #expect(measures.endpointGap < 0.08)
        #expect(measures.lengthRatio > 0.60 && measures.lengthRatio < 2.00)

        let result = service.evaluateStroke(drawn: honest, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .correct)
    }

    @Test("A stroke abandoned halfway scores as incorrect")
    func halfStrokeScoresIncorrect() throws {
        let (target, diagonal) = try shippedIchi()
        let service = StrokeAccuracyService()

        // Not in the brief, but it is the same family as the tap and it is
        // what the length ratio's lower bound is really for. Measured: ratio
        // 0.416, endpoint gap 0.326, mean 0.163.
        let half = Array(target.points.prefix(target.points.count / 2))

        let result = service.evaluateStroke(drawn: half, target: target, viewBoxDiagonal: diagonal)
        #expect(result == .incorrect)
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
