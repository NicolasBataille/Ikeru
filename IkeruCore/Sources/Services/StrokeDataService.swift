import Foundation
import os

// MARK: - Stroke Data Models

/// Represents the complete stroke order data for a character.
public struct StrokeData: Sendable, Equatable {
    /// Ordered strokes, in writing sequence.
    public let strokes: [StrokePathData]
    /// ViewBox width from SVG (typically 109 for KanjiVG).
    public let viewBoxWidth: Int
    /// ViewBox height from SVG (typically 109 for KanjiVG).
    public let viewBoxHeight: Int

    public init(strokes: [StrokePathData], viewBoxWidth: Int, viewBoxHeight: Int) {
        self.strokes = strokes
        self.viewBoxWidth = viewBoxWidth
        self.viewBoxHeight = viewBoxHeight
    }

    /// Diagonal length of the viewBox, used for normalizing distances.
    public var viewBoxDiagonal: Double {
        let w = Double(viewBoxWidth)
        let h = Double(viewBoxHeight)
        return (w * w + h * h).squareRoot()
    }
}

/// A single stroke represented as a sequence of control points.
public struct StrokePathData: Sendable, Equatable {
    /// Ordered control/sample points along this stroke path.
    public let points: [CGPoint]
    /// The raw SVG path data string for this stroke.
    public let rawPathData: String

    public init(points: [CGPoint], rawPathData: String) {
        self.points = points
        self.rawPathData = rawPathData
    }

    /// Returns `count` evenly-spaced points sampled along the polyline defined by `points`.
    /// Useful for stroke accuracy comparison.
    public func sampledPoints(count: Int) -> [CGPoint] {
        guard count > 1, points.count >= 2 else {
            return points
        }

        // Compute cumulative distances along the polyline
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

            // Find the segment containing targetDist
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

// MARK: - StrokeDataService

/// Parses KanjiVG SVG path data into native stroke representations.
/// Pure Swift, no SwiftUI dependencies. Stateless service.
public struct StrokeDataService: Sendable {

    public init() {}

    /// Parse stroke order data from raw SVG string containing `<path>` elements.
    /// - Parameters:
    ///   - svgString: Raw SVG/XML string with `<path d="..."/>` elements.
    ///   - viewBoxWidth: Width of the SVG viewBox (default 109 for KanjiVG).
    ///   - viewBoxHeight: Height of the SVG viewBox (default 109 for KanjiVG).
    /// - Returns: Parsed StrokeData, or nil if no valid strokes found.
    public func parseStrokes(
        from svgString: String,
        viewBoxWidth: Int = 109,
        viewBoxHeight: Int = 109
    ) -> StrokeData? {
        let pathDataStrings = extractPathData(from: svgString)

        guard !pathDataStrings.isEmpty else {
            Logger.content.warning("No path elements found in SVG string")
            return nil
        }

        let strokes = pathDataStrings.compactMap { pathData -> StrokePathData? in
            let points = parseSVGPathToPoints(pathData)
            guard !points.isEmpty else { return nil }
            return StrokePathData(points: points, rawPathData: pathData)
        }

        guard !strokes.isEmpty else {
            Logger.content.warning("Failed to parse any valid strokes from SVG")
            return nil
        }

        return StrokeData(
            strokes: strokes,
            viewBoxWidth: viewBoxWidth,
            viewBoxHeight: viewBoxHeight
        )
    }

    // MARK: - SVG Path Extraction

    /// Extracts `d` attribute values from `<path>` elements in the SVG string.
    private func extractPathData(from svgString: String) -> [String] {
        let pattern = #"<path[^>]*\sd=\"([^\"]+)\"[^>]*/?\s*>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = svgString as NSString
        let matches = regex.matches(
            in: svgString,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsString.substring(with: range)
        }
    }

    // MARK: - SVG Path Parsing

    /// Parses an SVG path data string (d attribute) into an array of CGPoints.
    /// Supports M, L, C, Q, Z commands and implicit repeats.
    private func parseSVGPathToPoints(_ pathData: String) -> [CGPoint] {
        let tokens = tokenize(pathData)
        var points: [CGPoint] = []
        var currentPoint = CGPoint.zero
        var startPoint = CGPoint.zero
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            guard token.first?.isLetter == true else {
                index += 1
                continue
            }

            let command = String(token)
            index += 1

            switch command.uppercased() {
            case "M":
                // Move to (handles implicit L for subsequent pairs)
                while let point = consumePoint(tokens: tokens, index: &index) {
                    currentPoint = point
                    startPoint = point
                    points.append(currentPoint)
                    // After first M pair, subsequent pairs are implicit L
                    break
                }
                // Handle implicit L after M
                while peekIsNumber(tokens: tokens, index: index) {
                    guard let point = consumePoint(tokens: tokens, index: &index) else { break }
                    currentPoint = point
                    points.append(currentPoint)
                }

            case "L":
                while let point = consumePoint(tokens: tokens, index: &index) {
                    currentPoint = point
                    points.append(currentPoint)
                    // Check if more number pairs follow (implicit repeat)
                    if !peekIsNumber(tokens: tokens, index: index) { break }
                }

            case "C":
                while peekHasNumbers(tokens: tokens, index: index, count: 6) {
                    guard let cp1 = consumePoint(tokens: tokens, index: &index),
                          let cp2 = consumePoint(tokens: tokens, index: &index),
                          let endPt = consumePoint(tokens: tokens, index: &index) else { break }
                    let samples = sampleCubicBezier(
                        from: currentPoint, cp1: cp1, cp2: cp2, to: endPt, sampleCount: 8
                    )
                    points.append(contentsOf: samples)
                    currentPoint = endPt
                }

            case "Q":
                while peekHasNumbers(tokens: tokens, index: index, count: 4) {
                    guard let cp = consumePoint(tokens: tokens, index: &index),
                          let endPt = consumePoint(tokens: tokens, index: &index) else { break }
                    let samples = sampleQuadraticBezier(
                        from: currentPoint, cp: cp, to: endPt, sampleCount: 8
                    )
                    points.append(contentsOf: samples)
                    currentPoint = endPt
                }

            case "Z":
                currentPoint = startPoint

            default:
                break
            }
        }

        return points
    }

    // MARK: - Tokenization

    /// Tokenizes an SVG path data string into individual tokens (commands and numbers).
    private func tokenize(_ pathData: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in pathData {
            if char.isLetter {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else if char == "," || char == " " || char == "\t" || char == "\n" || char == "\r" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if char == "-" && !current.isEmpty {
                // Negative sign starts a new number (e.g., "10-20")
                tokens.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Consumes two numbers from the token stream as a CGPoint.
    /// Returns nil if not enough numbers available.
    private func consumePoint(tokens: [String], index: inout Int) -> CGPoint? {
        guard index < tokens.count, let x = Double(tokens[index]) else {
            return nil
        }
        index += 1
        guard index < tokens.count, let y = Double(tokens[index]) else {
            return nil
        }
        index += 1
        return CGPoint(x: x, y: y)
    }

    /// Checks if the next token is a number (not a command letter).
    private func peekIsNumber(tokens: [String], index: Int) -> Bool {
        guard index < tokens.count else { return false }
        return Double(tokens[index]) != nil
    }

    /// Checks if at least `count` numbers are available from the current index.
    private func peekHasNumbers(tokens: [String], index: Int, count: Int) -> Bool {
        var consumed = 0
        var i = index
        while i < tokens.count && consumed < count {
            guard Double(tokens[i]) != nil else { return false }
            consumed += 1
            i += 1
        }
        return consumed >= count
    }

    // MARK: - Bezier Sampling

    /// Sample points along a cubic bezier curve (excludes start point, includes end).
    private func sampleCubicBezier(
        from p0: CGPoint,
        cp1: CGPoint,
        cp2: CGPoint,
        to p3: CGPoint,
        sampleCount: Int
    ) -> [CGPoint] {
        (1...sampleCount).map { i in
            let t: Double = Double(i) / Double(sampleCount)
            let u: Double = 1.0 - t
            let u2 = u * u
            let u3 = u2 * u
            let t2 = t * t
            let t3 = t2 * t
            let x: Double = u3 * p0.x + 3.0 * u2 * t * cp1.x + 3.0 * u * t2 * cp2.x + t3 * p3.x
            let y: Double = u3 * p0.y + 3.0 * u2 * t * cp1.y + 3.0 * u * t2 * cp2.y + t3 * p3.y
            return CGPoint(x: x, y: y)
        }
    }

    /// Sample points along a quadratic bezier curve (excludes start point, includes end).
    private func sampleQuadraticBezier(
        from p0: CGPoint,
        cp: CGPoint,
        to p2: CGPoint,
        sampleCount: Int
    ) -> [CGPoint] {
        (1...sampleCount).map { i in
            let t: Double = Double(i) / Double(sampleCount)
            let u: Double = 1.0 - t
            let u2 = u * u
            let t2 = t * t
            let x: Double = u2 * p0.x + 2.0 * u * t * cp.x + t2 * p2.x
            let y: Double = u2 * p0.y + 2.0 * u * t * cp.y + t2 * p2.y
            return CGPoint(x: x, y: y)
        }
    }
}
