import Testing
import Foundation
import CoreGraphics
@testable import IkeruCore

// MARK: - Mock Recognition Provider

/// A mock provider for testing that returns predetermined candidates.
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

// MARK: - Image Preprocessor Tests

@Suite("ImagePreprocessor")
struct ImagePreprocessorTests {

    @Test("renderStrokes returns nil for empty strokes")
    func renderStrokesEmptyReturnsNil() {
        let image = ImagePreprocessor.renderStrokes([], canvasSize: 300)
        #expect(image == nil)
    }

    @Test("renderStrokes produces image with default size")
    func renderStrokesDefaultSize() {
        let strokes: [[CGPoint]] = [
            [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)]
        ]
        let image = ImagePreprocessor.renderStrokes(strokes, canvasSize: 300)

        #expect(image != nil)
        #expect(image?.width == ImagePreprocessor.defaultSize)
        #expect(image?.height == ImagePreprocessor.defaultSize)
    }

    @Test("renderStrokes produces image with custom size")
    func renderStrokesCustomSize() {
        let strokes: [[CGPoint]] = [
            [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)]
        ]
        let image = ImagePreprocessor.renderStrokes(strokes, canvasSize: 200, outputSize: 64)

        #expect(image != nil)
        #expect(image?.width == 64)
        #expect(image?.height == 64)
    }

    @Test("renderStrokes produces grayscale image")
    func renderStrokesGrayscale() {
        let strokes: [[CGPoint]] = [
            [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)]
        ]
        let image = ImagePreprocessor.renderStrokes(strokes, canvasSize: 300)

        #expect(image != nil)
        // Grayscale images have 1 component (no alpha in our case)
        #expect(image?.bitsPerPixel == 8)
    }

    @Test("renderStrokes handles multiple strokes")
    func renderStrokesMultiple() {
        let strokes: [[CGPoint]] = [
            [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
            [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)],
            [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)],
        ]
        let image = ImagePreprocessor.renderStrokes(strokes, canvasSize: 300)

        #expect(image != nil)
        #expect(image?.width == ImagePreprocessor.defaultSize)
    }

    @Test("defaultSize is 128")
    func defaultSizeIs128() {
        #expect(ImagePreprocessor.defaultSize == 128)
    }
}

// MARK: - Recognition Candidate Tests

@Suite("RecognitionCandidate")
struct RecognitionCandidateTests {

    @Test("Candidate stores character and confidence")
    func candidateProperties() {
        let candidate = RecognitionCandidate(character: "\u{5c71}", confidence: 0.95)
        #expect(candidate.character == "\u{5c71}")
        #expect(candidate.confidence == 0.95)
    }

    @Test("Candidates are equatable")
    func candidateEquatable() {
        let a = RecognitionCandidate(character: "A", confidence: 0.8)
        let b = RecognitionCandidate(character: "A", confidence: 0.8)
        let c = RecognitionCandidate(character: "B", confidence: 0.8)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - Recognition Result Tests

@Suite("RecognitionResult")
struct RecognitionResultTests {

    @Test("Result stores candidates and duration")
    func resultProperties() {
        let candidates = [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.9),
            RecognitionCandidate(character: "\u{5ddd}", confidence: 0.7),
        ]
        let result = RecognitionResult(candidates: candidates, duration: 0.123)

        #expect(result.candidates.count == 2)
        #expect(result.duration == 0.123)
    }

    @Test("formattedDuration shows milliseconds")
    func formattedDuration() {
        let result = RecognitionResult(candidates: [], duration: 0.12)
        #expect(result.formattedDuration == "120ms")
    }

    @Test("formattedDuration rounds down for sub-millisecond")
    func formattedDurationSubMs() {
        let result = RecognitionResult(candidates: [], duration: 0.0009)
        #expect(result.formattedDuration == "0ms")
    }
}

// MARK: - HandwritingRecognitionService Tests

@Suite("HandwritingRecognitionService")
struct HandwritingRecognitionServiceTests {

    private func makeSampleStrokes() -> [[CGPoint]] {
        [
            [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
            [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)],
        ]
    }

    @Test("recognize returns candidates from provider")
    func recognizeReturnsCandidates() async throws {
        let mockCandidates = [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.9),
            RecognitionCandidate(character: "\u{5ddd}", confidence: 0.7),
        ]
        let provider = MockRecognitionProvider(candidates: mockCandidates)
        let service = HandwritingRecognitionService(provider: provider)

        let result = try await service.recognize(
            strokes: makeSampleStrokes(),
            canvasSize: 300
        )

        #expect(result.candidates.count == 2)
        #expect(result.candidates[0].character == "\u{5c71}")
        #expect(result.candidates[1].character == "\u{5ddd}")
        #expect(result.duration > 0)
    }

    @Test("recognize throws for empty strokes")
    func recognizeEmptyStrokesThrows() async {
        let provider = MockRecognitionProvider(candidates: [])
        let service = HandwritingRecognitionService(provider: provider)

        do {
            _ = try await service.recognize(strokes: [], canvasSize: 300)
            Issue.record("Expected error for empty strokes")
        } catch {
            #expect(error is HandwritingRecognitionError)
        }
    }

    @Test("recognize propagates provider errors")
    func recognizeProviderErrorPropagates() async {
        let provider = MockRecognitionProvider(shouldThrow: true)
        let service = HandwritingRecognitionService(provider: provider)

        do {
            _ = try await service.recognize(
                strokes: makeSampleStrokes(),
                canvasSize: 300
            )
            Issue.record("Expected provider error")
        } catch {
            #expect(error is HandwritingRecognitionError)
        }
    }

    @Test("recognize limits candidates to maxCandidates")
    func recognizeLimitsCandidates() async throws {
        let manyCandidates = (0..<10).map { i in
            RecognitionCandidate(
                character: "char\(i)",
                confidence: Double(10 - i) / 10.0
            )
        }
        let provider = MockRecognitionProvider(candidates: manyCandidates)
        let service = HandwritingRecognitionService(provider: provider, maxCandidates: 3)

        let result = try await service.recognize(
            strokes: makeSampleStrokes(),
            canvasSize: 300
        )

        #expect(result.candidates.count == 3)
    }

    @Test("recognize completes within 500ms with mock provider")
    func recognizePerformance() async throws {
        let provider = MockRecognitionProvider(candidates: [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.9)
        ])
        let service = HandwritingRecognitionService(provider: provider)

        let result = try await service.recognize(
            strokes: makeSampleStrokes(),
            canvasSize: 300
        )

        #expect(result.duration < 0.5)
    }

    @Test("recognize image directly returns candidates")
    func recognizeImageDirect() async throws {
        let mockCandidates = [
            RecognitionCandidate(character: "\u{5c71}", confidence: 0.85)
        ]
        let provider = MockRecognitionProvider(candidates: mockCandidates)
        let service = HandwritingRecognitionService(provider: provider)

        let image = ImagePreprocessor.renderStrokes(
            makeSampleStrokes(),
            canvasSize: 300
        )!

        let result = try await service.recognize(image: image)

        #expect(result.candidates.count == 1)
        #expect(result.candidates[0].character == "\u{5c71}")
    }
}

// MARK: - HandwritingRecognitionError Tests

@Suite("HandwritingRecognitionError")
struct HandwritingRecognitionErrorTests {

    @Test("Error descriptions are non-empty")
    func errorDescriptions() {
        let errors: [HandwritingRecognitionError] = [
            .imageRenderingFailed,
            .visionFailed("test detail"),
            .noStrokesProvided,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("visionFailed includes detail")
    func visionFailedDetail() {
        let error = HandwritingRecognitionError.visionFailed("timeout")
        #expect(error.errorDescription?.contains("timeout") == true)
    }
}

// MARK: - ShapeMatchingProvider Tests

@Suite("ShapeMatchingProvider")
struct ShapeMatchingProviderTests {

    @Test("Returns target character with low confidence")
    func returnsTargetCharacter() async throws {
        let provider = ShapeMatchingProvider(targetCharacter: "\u{5c71}")

        let image = ImagePreprocessor.renderStrokes(
            [[CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)]],
            canvasSize: 100
        )!

        let candidates = try await provider.recognize(image: image)

        #expect(candidates.count == 1)
        #expect(candidates[0].character == "\u{5c71}")
        #expect(candidates[0].confidence > 0)
        #expect(candidates[0].confidence <= 0.5)
    }
}
