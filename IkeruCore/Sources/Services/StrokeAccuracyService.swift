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
    /// Average normalized distance across all strokes (0 = perfect, 1 = worst).
    public let averageScore: Double

    public init(strokeResults: [StrokeResult], passed: Bool, averageScore: Double) {
        self.strokeResults = strokeResults
        self.passed = passed
        self.averageScore = averageScore
    }
}

// MARK: - StrokeAccuracyService

/// Evaluates stroke accuracy by comparing drawn paths against target stroke paths.
/// Uses a simplified point-distance comparison for v1.
/// Pure Swift, no SwiftUI dependencies. Stateless service.
public struct StrokeAccuracyService: Sendable {

    /// Number of evenly-spaced sample points for comparison.
    private let sampleCount: Int

    /// Threshold: normalized distance below this is "correct".
    private let correctThreshold: Double

    /// Threshold: normalized distance below this is "approximately correct".
    private let approximateThreshold: Double

    public init(
        sampleCount: Int = 20,
        correctThreshold: Double = 0.15,
        approximateThreshold: Double = 0.30
    ) {
        self.sampleCount = sampleCount
        self.correctThreshold = correctThreshold
        self.approximateThreshold = approximateThreshold
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
        let targetSampled = target.sampledPoints(count: sampleCount)
        let distance = normalizedAverageDistance(
            drawn: drawn,
            target: targetSampled,
            viewBoxDiagonal: viewBoxDiagonal
        )

        if distance < correctThreshold {
            return .correct
        } else if distance < approximateThreshold {
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
            return CharacterResult(strokeResults: [], passed: false, averageScore: 1.0)
        }

        let allPassing = strokeResults.allSatisfy(\.isPassing)
        let avgScore = strokeResults.map(\.score).reduce(0, +) / Double(strokeResults.count)

        return CharacterResult(
            strokeResults: strokeResults,
            passed: allPassing,
            averageScore: avgScore
        )
    }

    // MARK: - Distance Computation

    /// Compute the normalized average distance between drawn and target point sequences.
    /// Both sequences are resampled to `sampleCount` evenly-spaced points.
    /// The result is normalized by `viewBoxDiagonal` to produce a 0-1 score.
    /// - Returns: Normalized average distance (0 = identical, 1 = full diagonal apart).
    public func normalizedAverageDistance(
        drawn: [CGPoint],
        target: [CGPoint],
        viewBoxDiagonal: Double
    ) -> Double {
        guard viewBoxDiagonal > 0 else { return 1.0 }

        let drawnSampled = resamplePoints(drawn, count: sampleCount)
        let targetSampled = resamplePoints(target, count: sampleCount)

        guard drawnSampled.count == targetSampled.count, !drawnSampled.isEmpty else {
            return 1.0
        }

        var totalDistance: Double = 0
        for i in 0..<drawnSampled.count {
            let dx = drawnSampled[i].x - targetSampled[i].x
            let dy = drawnSampled[i].y - targetSampled[i].y
            totalDistance += (dx * dx + dy * dy).squareRoot()
        }

        let averageDistance = totalDistance / Double(drawnSampled.count)
        return averageDistance / viewBoxDiagonal
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
