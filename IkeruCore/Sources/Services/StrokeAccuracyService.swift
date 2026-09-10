import Foundation
import os

// MARK: - Stroke Result

/// Result of evaluating a single drawn stroke against its target.
public enum StrokeResult: Sendable, Equatable {
    case correct
    case approximatelyCorrect
    case incorrect

    /// A representative score for the result category.
    /// Lower is better. Used for UI feedback.
    public var score: Double {
        switch self {
        case .correct: 0.05
        case .approximatelyCorrect: 0.20
        case .incorrect: 0.50
        }
    }

    /// Whether this stroke counts as passing.
    public var isPassing: Bool {
        switch self {
        case .correct, .approximatelyCorrect: true
        case .incorrect: false
        }
    }
}

// MARK: - Overall Character Result

/// Result of evaluating all strokes for a complete character tracing attempt.
public struct CharacterResult: Sendable, Equatable {
    /// Per-stroke results in stroke order.
    public let strokeResults: [StrokeResult]
    /// Whether the overall attempt passes.
    public let passed: Bool
    /// Mean of the per-stroke *severity* constants — `StrokeResult.score`, i.e.
    /// 0.05 / 0.20 / 0.50 — and **not** a measured distance. Three tiers in,
    /// so only 3^n values out: two strokes can only ever produce 0.05, 0.125,
    /// 0.20, 0.275, 0.35 or 0.50.
    ///
    /// This field used to be documented as "average normalized distance across
    /// all strokes", which it has never been. Fixed the doc rather than the
    /// code: carrying the real measured distances up here would mean changing
    /// `evaluateOverall`'s public signature and the ViewModel that calls it,
    /// for a number whose only consumer today is a single `os.Logger` line
    /// (`StrokeOrderViewModel.swift:173`) — no UI reads it. Renamed too,
    /// because a wrong name outlives a corrected comment.
    public let averageSeverity: Double

    public init(strokeResults: [StrokeResult], passed: Bool, averageSeverity: Double) {
        self.strokeResults = strokeResults
        self.passed = passed
        self.averageSeverity = averageSeverity
    }
}

// MARK: - Stroke Measures

/// The four independent measures taken on one drawn stroke against its target.
/// All distances are normalized by the viewBox diagonal (154.15 for KanjiVG's
/// 109×109 box), so 1.0 means "a full diagonal away".
///
/// Four of them because no single one is sufficient — measured on the shipped
/// 一 path (`n5-content.sqlite`), the mean distance alone rates a *stationary
/// tap at the centre* at 0.148, i.e. better than the `.correct` bar of 0.15 and
/// better than an honest-but-offset stroke. Mean distance rewards drawing
/// nothing, because `resamplePoints` expands a degenerate input into 20 copies
/// of one point and the metric degenerates into "how far is your ink from the
/// target's centroid". Lowering thresholds cannot fix that; a shape constraint
/// can.
public struct StrokeMeasures: Sendable, Equatable {
    /// Mean of the 20 index-paired point distances. Forgiving: averages away
    /// a single bad excursion.
    public let meanDistance: Double
    /// Largest of the 20 index-paired point distances. Catches the excursion
    /// the mean hides, and (because pairing is by index along arc length) it
    /// also punishes a stroke drawn in the wrong direction.
    public let maxDistance: Double
    /// Drawn arc length ÷ target arc length, both measured on the resampled
    /// polylines. 0 for a tap, ~1 for an honest trace, large for a scribble.
    public let lengthRatio: Double
    /// Worst of (start↔start, end↔end). This is the term that rejects a
    /// reversed stroke and a vertical line drawn over a horizontal target —
    /// both of which sit inside the mean-distance tolerance.
    public let endpointGap: Double

    public init(meanDistance: Double, maxDistance: Double, lengthRatio: Double, endpointGap: Double) {
        self.meanDistance = meanDistance
        self.maxDistance = maxDistance
        self.lengthRatio = lengthRatio
        self.endpointGap = endpointGap
    }
}

// MARK: - StrokeAccuracyService

/// Evaluates stroke accuracy by comparing drawn paths against target stroke paths.
/// Deliberately demanding: a stroke has to be in the right place, the right
/// shape, the right length **and** the right direction to pass.
/// Pure Swift, no SwiftUI dependencies. Stateless service.
public struct StrokeAccuracyService: Sendable {

    // MARK: - Gates

    /// The bounds a stroke's four measures must all satisfy to earn one verdict
    /// tier. Every bound is a veto: the verdict is the best tier that admits
    /// all four measures.
    private struct Gate: Sendable {
        let maxMeanDistance: Double
        let maxPeakDistance: Double
        let maxEndpointGap: Double
        let lengthRatioRange: ClosedRange<Double>

        func admits(_ measures: StrokeMeasures) -> Bool {
            measures.meanDistance < maxMeanDistance
                && measures.maxDistance < maxPeakDistance
                && measures.endpointGap < maxEndpointGap
                && lengthRatioRange.contains(measures.lengthRatio)
        }
    }

    /// Number of evenly-spaced sample points for comparison.
    private let sampleCount: Int

    /// Bounds for `.correct`.
    private let correctGate: Gate

    /// Bounds for `.approximatelyCorrect`.
    private let approximateGate: Gate

    /// - Parameters:
    ///   - sampleCount: Points both polylines are resampled to before pairing.
    ///   - correctThreshold: Mean-distance bound for `.correct`.
    ///   - approximateThreshold: Mean-distance bound for `.approximatelyCorrect`.
    ///
    /// The mean-distance bounds keep their historical values (0.15 / 0.30) —
    /// they were never the problem. The shape bounds below are what makes the
    /// scorer demanding; see each constant for the measurement that set it.
    public init(
        sampleCount: Int = 20,
        correctThreshold: Double = 0.15,
        approximateThreshold: Double = 0.30
    ) {
        self.sampleCount = sampleCount
        self.correctGate = Gate(
            maxMeanDistance: correctThreshold,
            // ≈1.5× the mean bound: one local excursion may be worse than the
            // average, but not unboundedly so. Measured headroom — the worst
            // "honest but imperfect" fixture (±2 units of per-point jitter on
            // top of a 6-unit uniform offset) peaks at 0.078, so this bound is
            // 2.8× away from anything a sincere trace produces.
            maxPeakDistance: 0.22,
            // 0.08 × 154.15 ≈ 12.3 viewBox units ≈ 11% of the 109-wide box.
            // On a 300pt canvas that is ~34pt of slack on the start and end
            // points, with a start dot drawn on screen to aim at. Measured
            // consequence: the "moderately off" fixture (drawn 15 units below
            // its target) gaps 0.103 and is demoted to `.approximatelyCorrect`
            // — which is what its own test name always claimed it was, while
            // its mean distance of 0.099 had it silently passing as `.correct`.
            // The honest jitter+offset fixture gaps 0.044, i.e. 1.8× inside.
            maxEndpointGap: 0.08,
            // Asymmetric on purpose. The lower bound is the load-bearing one:
            // it is what rejects a stationary tap (ratio 0.000) and a stroke
            // abandoned halfway (0.416). The upper bound is loose because arc
            // length is the measure most inflated by input noise; measured
            // inflation on the shipped 一 (25 parsed points ~3.6 units apart):
            // ±1 unit of jitter → 1.017, ±2 → 1.090, ±3 → 1.221, and a
            // 120-point dense resample with ±1 unit → 1.023. 2.00 leaves ample
            // room; a genuinely overlong stroke is caught by the endpoint and
            // peak terms instead (the 4-point scribble ratios 4.21 anyway).
            lengthRatioRange: 0.60...2.00
        )
        self.approximateGate = Gate(
            maxMeanDistance: approximateThreshold,
            // ≈1.2× the approximate mean bound. Set at 0.36 rather than 0.42
            // so the vertical-line-over-一 case (peak 0.420) is vetoed here as
            // well as by the endpoint term — two independent vetoes, because a
            // single one sitting 0.0003 from its bound is not a guarantee.
            maxPeakDistance: 0.36,
            // 0.18 × 154.15 ≈ 27.7 units. Measured on the shipped 一: a
            // vertical line through the centre gaps 0.420, the 4-point
            // diagonal scribble 0.322, a stationary tap 0.282, and the
            // reference stroke traced backwards 0.558. All four land outside,
            // i.e. `.incorrect`. Reversal is graded `.incorrect` and not
            // `.approximatelyCorrect` deliberately: 筆順 practice exists to
            // train direction, so a stroke drawn end-to-start is not a rough
            // version of the right motion, it is the wrong motion.
            maxEndpointGap: 0.18,
            lengthRatioRange: 0.45...3.00
        )
    }

    // MARK: - Single Stroke Evaluation

    /// Evaluate a single drawn stroke against its target.
    /// - Parameters:
    ///   - drawn: Points captured from the learner's finger input.
    ///   - target: The target stroke path data.
    ///   - viewBoxDiagonal: Diagonal of the viewBox for normalization.
    /// - Returns: The stroke result classification.
    public func evaluateStroke(
        drawn: [CGPoint],
        target: StrokePathData,
        viewBoxDiagonal: Double
    ) -> StrokeResult {
        let measures = measure(
            drawn: drawn,
            target: target.sampledPoints(count: sampleCount),
            viewBoxDiagonal: viewBoxDiagonal
        )

        if correctGate.admits(measures) {
            return .correct
        } else if approximateGate.admits(measures) {
            return .approximatelyCorrect
        } else {
            return .incorrect
        }
    }

    // MARK: - Overall Character Evaluation

    /// Evaluate the overall character tracing result from individual stroke results.
    /// - Parameter strokeResults: Per-stroke results in order.
    /// - Returns: Overall character result.
    public func evaluateOverall(strokeResults: [StrokeResult]) -> CharacterResult {
        guard !strokeResults.isEmpty else {
            return CharacterResult(strokeResults: [], passed: false, averageSeverity: 1.0)
        }

        let allPassing = strokeResults.allSatisfy(\.isPassing)
        let avgSeverity = strokeResults.map(\.score).reduce(0, +) / Double(strokeResults.count)

        return CharacterResult(
            strokeResults: strokeResults,
            passed: allPassing,
            averageSeverity: avgSeverity
        )
    }

    // MARK: - Measurement

    /// Take all four measures on a drawn stroke against a target point sequence.
    /// Both sequences are resampled to `sampleCount` arc-length-uniform points
    /// and paired by index, so a pause mid-stroke costs nothing (arc length,
    /// not time) but drawing in the wrong direction costs a great deal.
    public func measure(
        drawn: [CGPoint],
        target: [CGPoint],
        viewBoxDiagonal: Double
    ) -> StrokeMeasures {
        // Worst possible measures: a caller with a broken viewBox or an empty
        // target gets `.incorrect`, never a free pass.
        let unmeasurable = StrokeMeasures(
            meanDistance: 1.0, maxDistance: 1.0, lengthRatio: 0, endpointGap: 1.0
        )
        guard viewBoxDiagonal > 0 else { return unmeasurable }

        let drawnSampled = resamplePoints(drawn, count: sampleCount)
        let targetSampled = resamplePoints(target, count: sampleCount)

        guard drawnSampled.count == targetSampled.count, !drawnSampled.isEmpty else {
            return unmeasurable
        }

        var totalDistance: Double = 0
        var peakDistance: Double = 0
        for i in 0..<drawnSampled.count {
            let distance = euclideanDistance(drawnSampled[i], targetSampled[i])
            totalDistance += distance
            peakDistance = max(peakDistance, distance)
        }
        let meanDistance = totalDistance / Double(drawnSampled.count)

        // A target of zero arc length is not a stroke; refusing to divide by it
        // means no drawn input can be "the right length" for it.
        let targetLength = polylineLength(targetSampled)
        let lengthRatio = targetLength > 0 ? polylineLength(drawnSampled) / targetLength : 0

        let startGap = euclideanDistance(drawnSampled[0], targetSampled[0])
        let endGap = euclideanDistance(drawnSampled[drawnSampled.count - 1], targetSampled[targetSampled.count - 1])

        return StrokeMeasures(
            meanDistance: meanDistance / viewBoxDiagonal,
            maxDistance: peakDistance / viewBoxDiagonal,
            lengthRatio: lengthRatio,
            endpointGap: max(startGap, endGap) / viewBoxDiagonal
        )
    }

    /// Compute the normalized average distance between drawn and target point sequences.
    /// Both sequences are resampled to `sampleCount` evenly-spaced points.
    /// The result is normalized by `viewBoxDiagonal` to produce a 0-1 score.
    /// - Returns: Normalized average distance (0 = identical, 1 = full diagonal apart).
    /// - Note: This is only one of the four terms of a verdict — on its own it
    ///   rates a stationary tap at 0.148, better than the `.correct` bar. Use
    ///   `evaluateStroke(drawn:target:viewBoxDiagonal:)` to grade a stroke.
    public func normalizedAverageDistance(
        drawn: [CGPoint],
        target: [CGPoint],
        viewBoxDiagonal: Double
    ) -> Double {
        measure(drawn: drawn, target: target, viewBoxDiagonal: viewBoxDiagonal).meanDistance
    }

    // MARK: - Geometry Helpers

    private func euclideanDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Total length of the polyline through `points` (0 for fewer than 2 points).
    private func polylineLength(_ points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            total += euclideanDistance(points[i], points[i - 1])
        }
        return total
    }

    // MARK: - Point Resampling

    /// Resample a point sequence to exactly `count` evenly-spaced points.
    private func resamplePoints(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 1, points.count >= 2 else {
            if let first = points.first {
                return Array(repeating: first, count: max(count, 1))
            }
            return []
        }

        // Compute cumulative arc lengths
        var distances: [Double] = [0]
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            let segLength = (dx * dx + dy * dy).squareRoot()
            distances.append(distances[i - 1] + segLength)
        }

        let totalLength = distances.last!
        guard totalLength > 0 else {
            return Array(repeating: points[0], count: count)
        }

        var sampled: [CGPoint] = []
        for sampleIndex in 0..<count {
            let targetDist = totalLength * Double(sampleIndex) / Double(count - 1)

            var segIndex = 0
            for j in 1..<distances.count {
                if distances[j] >= targetDist {
                    segIndex = j - 1
                    break
                }
                segIndex = j - 1
            }

            let segStart = distances[segIndex]
            let segEnd = distances[segIndex + 1]
            let segLength = segEnd - segStart
            let t = segLength > 0 ? (targetDist - segStart) / segLength : 0

            let interpolated = CGPoint(
                x: points[segIndex].x + t * (points[segIndex + 1].x - points[segIndex].x),
                y: points[segIndex].y + t * (points[segIndex + 1].y - points[segIndex].y)
            )
            sampled.append(interpolated)
        }

        return sampled
    }
}
