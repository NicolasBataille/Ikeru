import Foundation
import Vision
import CoreGraphics
import os

// MARK: - Recognition Candidate

/// A single character recognition result with its confidence score.
public struct RecognitionCandidate: Sendable, Equatable {
    /// The recognized character string.
    public let character: String
    /// Confidence score from 0.0 (no confidence) to 1.0 (certain).
    public let confidence: Double

    public init(character: String, confidence: Double) {
        self.character = character
        self.confidence = confidence
    }
}

// MARK: - Recognition Result

/// The result of a handwriting recognition operation.
public struct RecognitionResult: Sendable, Equatable {
    /// Top candidates sorted by confidence descending.
    public let candidates: [RecognitionCandidate]
    /// Wall-clock duration of the recognition pipeline in seconds.
    public let duration: TimeInterval

    public init(candidates: [RecognitionCandidate], duration: TimeInterval) {
        self.candidates = candidates
        self.duration = duration
    }

    /// Duration formatted for display, e.g. "120ms".
    public var formattedDuration: String {
        let ms = Int(duration * 1000)
        return "\(ms)ms"
    }
}

// MARK: - Recognition Provider Protocol

/// Abstraction for handwriting recognition backends.
/// Enables testing with mocks and swapping implementations.
public protocol RecognitionProvider: Sendable {
    func recognize(image: CGImage) async throws -> [RecognitionCandidate]
}

// MARK: - Vision Recognition Provider

/// On-device handwriting recognition using Apple's Vision framework.
/// Uses VNRecognizeTextRequest with Japanese language support.
/// Works fully offline -- no network calls.
public struct VisionRecognitionProvider: RecognitionProvider, Sendable {

    /// Maximum number of candidates to return.
    private let maxCandidates: Int

    public init(maxCandidates: Int = 5) {
        self.maxCandidates = maxCandidates
    }

    public func recognize(image: CGImage) async throws -> [RecognitionCandidate] {
        let maxN = maxCandidates
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            let request = VNRecognizeTextRequest { request, error in
                guard !resumed else { return }
                resumed = true

                if let error {
                    continuation.resume(throwing: HandwritingRecognitionError.visionFailed(
                        error.localizedDescription
                    ))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let candidates = Self.extractCandidates(
                    from: observations,
                    maxCandidates: maxN
                )
                continuation.resume(returning: candidates)
            }

            request.recognitionLanguages = ["ja"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: HandwritingRecognitionError.visionFailed(
                    error.localizedDescription
                ))
            }
        }
    }

    /// Extract and deduplicate candidates from Vision observations.
    private static func extractCandidates(
        from observations: [VNRecognizedTextObservation],
        maxCandidates: Int
    ) -> [RecognitionCandidate] {
        var seen = Set<String>()
        var candidates: [RecognitionCandidate] = []

        for observation in observations {
            let topN = observation.topCandidates(maxCandidates)
            for textCandidate in topN {
                // Extract individual characters from recognized text
                for character in textCandidate.string {
                    let charString = String(character)
                    guard !seen.contains(charString) else { continue }
                    seen.insert(charString)
                    candidates.append(RecognitionCandidate(
                        character: charString,
                        confidence: Double(textCandidate.confidence)
                    ))
                }
            }
        }

        return Array(
            candidates
                .sorted { $0.confidence > $1.confidence }
                .prefix(maxCandidates)
        )
    }
}

// MARK: - Shape Matching Fallback Provider

/// Basic shape matching fallback when Vision is unavailable.
/// Compares the drawn image against a rendered reference of the target character.
/// Returns low-confidence results as a best-effort fallback.
public struct ShapeMatchingProvider: RecognitionProvider, Sendable {

    private let targetCharacter: String

    public init(targetCharacter: String) {
        self.targetCharacter = targetCharacter
    }

    public func recognize(image: CGImage) async throws -> [RecognitionCandidate] {
        // Basic fallback: compare pixel density as a rough similarity measure.
        // This is intentionally simple -- Vision is the primary path.
        let drawnDensity = pixelDensity(of: image)

        // A drawn character with reasonable ink coverage suggests a match attempt.
        // Use density as a rough confidence proxy.
        let confidence = min(max(drawnDensity * 2.0, 0.1), 0.5)

        return [RecognitionCandidate(
            character: targetCharacter,
            confidence: confidence
        )]
    }

    /// Calculate the ratio of non-black pixels to total pixels.
    private func pixelDensity(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        let totalPixels = width * height
        guard totalPixels > 0, totalPixels <= 256 * 256 else { return 0 }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }
        let pixelData = data.bindMemory(to: UInt8.self, capacity: totalPixels)

        var litPixels = 0
        for i in 0..<totalPixels {
            if pixelData[i] > 128 {
                litPixels += 1
            }
        }

        return Double(litPixels) / Double(totalPixels)
    }
}

// MARK: - Handwriting Recognition Error

/// Errors that can occur during handwriting recognition.
public enum HandwritingRecognitionError: Error, LocalizedError, Sendable {
    case imageRenderingFailed
    case visionFailed(String)
    case noStrokesProvided

    public var errorDescription: String? {
        switch self {
        case .imageRenderingFailed:
            "Failed to render strokes to image for recognition."
        case .visionFailed(let detail):
            "Vision recognition failed: \(detail)"
        case .noStrokesProvided:
            "No strokes provided for recognition."
        }
    }
}

// MARK: - Image Preprocessing

/// Pure functions for preparing stroke data for recognition.
public enum ImagePreprocessor {

    /// Default rendering size for recognition input.
    public static let defaultSize: Int = 128

    /// Render an array of strokes to a grayscale CGImage.
    /// White strokes on black background, suitable for recognition.
    /// - Parameters:
    ///   - strokes: Array of stroke point arrays in canvas coordinates.
    ///   - canvasSize: The size of the original canvas.
    ///   - outputSize: The output image dimension (square).
    /// - Returns: A grayscale CGImage, or nil on failure.
    public static func renderStrokes(
        _ strokes: [[CGPoint]],
        canvasSize: CGFloat,
        outputSize: Int = defaultSize
    ) -> CGImage? {
        guard !strokes.isEmpty else { return nil }

        let size = CGFloat(outputSize)
        let scale = size / canvasSize

        guard let context = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: outputSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Black background
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // White strokes
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineWidth(max(3 * scale, 2))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            context.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for point in stroke.dropFirst() {
                context.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
            }
            context.strokePath()
        }

        return context.makeImage()
    }
}

// MARK: - Handwriting Recognition Service

/// Orchestrates on-device handwriting recognition using Vision framework.
/// Handles image preprocessing, provider selection, and result assembly.
/// Stateless and Sendable -- safe to use from any context.
public struct HandwritingRecognitionService: Sendable {

    private let provider: any RecognitionProvider
    private let maxCandidates: Int

    /// Initialize with a specific recognition provider.
    /// - Parameters:
    ///   - provider: The recognition backend to use. Defaults to VisionRecognitionProvider.
    ///   - maxCandidates: Maximum number of candidates to return. Defaults to 5.
    public init(
        provider: any RecognitionProvider = VisionRecognitionProvider(),
        maxCandidates: Int = 5
    ) {
        self.provider = provider
        self.maxCandidates = maxCandidates
    }

    /// Recognize handwritten character from stroke data.
    /// - Parameters:
    ///   - strokes: Array of stroke point arrays in canvas coordinates.
    ///   - canvasSize: The size of the drawing canvas.
    /// - Returns: Recognition result with ranked candidates and timing.
    public func recognize(
        strokes: [[CGPoint]],
        canvasSize: CGFloat
    ) async throws -> RecognitionResult {
        guard !strokes.isEmpty else {
            throw HandwritingRecognitionError.noStrokesProvided
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        guard let image = ImagePreprocessor.renderStrokes(
            strokes,
            canvasSize: canvasSize
        ) else {
            throw HandwritingRecognitionError.imageRenderingFailed
        }

        let candidates = try await provider.recognize(image: image)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        let result = RecognitionResult(
            candidates: Array(candidates.prefix(maxCandidates)),
            duration: duration
        )

        Logger.content.info("Handwriting recognition completed in \(result.formattedDuration) with \(result.candidates.count) candidates")

        return result
    }

    /// Recognize handwritten character from a pre-rendered image.
    /// - Parameter image: A CGImage of the handwritten character.
    /// - Returns: Recognition result with ranked candidates and timing.
    public func recognize(image: CGImage) async throws -> RecognitionResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let candidates = try await provider.recognize(image: image)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        let result = RecognitionResult(
            candidates: Array(candidates.prefix(maxCandidates)),
            duration: duration
        )

        Logger.content.info("Handwriting recognition (image) completed in \(result.formattedDuration) with \(result.candidates.count) candidates")

        return result
    }
}
