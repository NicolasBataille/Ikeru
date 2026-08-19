import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import IkeruCore

// MARK: - Fake Provider

/// A provider that returns what the test decided, so the whole pipeline can be
/// exercised without a camera, a photo, or the Vision engine.
private struct FakeTextRecognitionProvider: TextRecognitionProvider, Sendable {
    let fragments: [RecognizedTextFragment]
    let error: TextRecognitionError?

    init(fragments: [RecognizedTextFragment] = [], error: TextRecognitionError? = nil) {
        self.fragments = fragments
        self.error = error
    }

    /// Records what it was handed, so a test can assert the orientation read
    /// off the file actually reaches the engine — the point of the parameter.
    func recognizeFragments(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [RecognizedTextFragment] {
        if let error { throw error }
        return fragments
    }
}

// MARK: - Fixtures

/// Bounding boxes are Vision-normalised with a **bottom-left origin**: the top
/// of the page has the higher `y`. The fixtures below are written that way on
/// purpose — an ascending-y page would make a wrong sorter look right.
private func fragment(
    _ text: String,
    x: Double,
    y: Double,
    width: Double = 0.3,
    height: Double = 0.08,
    confidence: Double = 0.9
) -> RecognizedTextFragment {
    RecognizedTextFragment(
        text: text,
        boundingBox: CGRect(x: x, y: y, width: width, height: height),
        confidence: confidence
    )
}

/// A 1×1 image, only there to satisfy the signature — the fake provider never
/// looks at it.
private func makeStubImage() -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 1,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    return context.makeImage()
}

// MARK: - Tests

@Suite("TextRecognitionService")
struct TextRecognitionServiceTests {

    // MARK: Reading order

    @Test("Lines are ordered top to bottom, whatever order the engine returned")
    func readingOrderIsTopDown() {
        // Deliberately shuffled: Vision does not hand its observations back in
        // page order.
        let fragments = [
            fragment("三行目", x: 0.1, y: 0.20),
            fragment("一行目", x: 0.1, y: 0.80),
            fragment("二行目", x: 0.1, y: 0.50)
        ]

        let recognized = RecognizedText.assemble(from: fragments)

        #expect(recognized.lines == ["一行目", "二行目", "三行目"])
    }

    @Test("Fragments sharing a line are ordered left to right")
    func readingOrderIsLeftToRightWithinALine() {
        let fragments = [
            fragment("です", x: 0.60, y: 0.80, width: 0.2),
            fragment("これは", x: 0.10, y: 0.802, width: 0.2),
            fragment("本", x: 0.35, y: 0.798, width: 0.2)
        ]

        let recognized = RecognizedText.assemble(from: fragments)

        // No separator inside a line: Japanese has no inter-word space, and
        // inserting one would rewrite the learner's text.
        #expect(recognized.lines == ["これは本です"])
        #expect(recognized.text == "これは本です")
    }

    @Test("A slightly tilted photo still groups its fragments on one line")
    func readingOrderToleratesTilt() {
        // Midpoints differ by 0.02, well under half of the 0.08 box height.
        let fragments = [
            fragment("みぎ", x: 0.55, y: 0.52),
            fragment("ひだり", x: 0.05, y: 0.50)
        ]

        let lines = RecognizedText.readingOrderLines(fragments)

        #expect(lines.count == 1)
        #expect(lines.first?.map(\.text) == ["ひだり", "みぎ"])
    }

    @Test("Fragments further apart than half a box height start a new line")
    func readingOrderSplitsDistinctLines() {
        let fragments = [
            fragment("うえ", x: 0.05, y: 0.80),
            fragment("した", x: 0.05, y: 0.60)
        ]

        let lines = RecognizedText.readingOrderLines(fragments)

        #expect(lines.count == 2)
        #expect(lines.map { $0.map(\.text).joined() } == ["うえ", "した"])
    }

    // MARK: Joining

    @Test("Lines are joined by a newline, and nothing is rewritten")
    func linesAreJoinedByNewline() {
        let fragments = [
            fragment("今日はいい天気ですね。", x: 0.05, y: 0.80),
            fragment("散歩に行きましょう！", x: 0.05, y: 0.60)
        ]

        let recognized = RecognizedText.assemble(from: fragments)

        #expect(recognized.text == "今日はいい天気ですね。\n散歩に行きましょう！")
        #expect(recognized.lines.count == 2)
    }

    @Test("Confidence is the mean of the fragment confidences")
    func confidenceIsTheMean() {
        let fragments = [
            fragment("あ", x: 0.05, y: 0.80, confidence: 1.0),
            fragment("い", x: 0.05, y: 0.60, confidence: 0.5)
        ]

        let recognized = RecognizedText.assemble(from: fragments)

        #expect(abs(recognized.confidence - 0.75) < 0.0001)
    }

    @Test("An empty fragment list assembles into an empty page, not a crash")
    func assembleHandlesNoFragments() {
        let recognized = RecognizedText.assemble(from: [])

        #expect(recognized.lines.isEmpty)
        #expect(recognized.text.isEmpty)
        #expect(recognized.confidence == 0)
    }

    // MARK: Nothing recognised

    @Test("Recognising nothing throws the named vertical-text error")
    func nothingRecognizedThrowsNamedError() async throws {
        let image = try #require(makeStubImage())
        let service = TextRecognitionService(provider: FakeTextRecognitionProvider())

        await #expect(throws: TextRecognitionError.noHorizontalTextFound) {
            _ = try await service.recognizeText(in: image)
        }
    }

    @Test("Blank fragments count as nothing recognised")
    func blankFragmentsThrowTheSameError() async throws {
        let image = try #require(makeStubImage())
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("   ", x: 0.05, y: 0.80),
            fragment("\n", x: 0.05, y: 0.60)
        ])
        let service = TextRecognitionService(provider: provider)

        await #expect(throws: TextRecognitionError.noHorizontalTextFound) {
            _ = try await service.recognizeText(in: image)
        }
    }

    @Test("The vertical-text error carries its own catalogue key")
    func verticalErrorCarriesACatalogueKey() {
        #expect(
            TextRecognitionError.noHorizontalTextFound.messageKey
                == "import.photo.error.verticalNotSupported"
        )
        #expect(
            TextRecognitionError.recognitionFailed("boom").messageKey
                == "import.photo.error.recognitionFailed"
        )
        #expect(
            TextRecognitionError.imageUnreadable.messageKey
                == "import.photo.error.imageUnreadable"
        )
    }

    // MARK: Service pipeline

    @Test("The service returns the page in reading order")
    func serviceReturnsPageInReadingOrder() async throws {
        let image = try #require(makeStubImage())
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("二行目", x: 0.05, y: 0.60),
            fragment("一行目", x: 0.05, y: 0.80)
        ])
        let service = TextRecognitionService(provider: provider)

        let recognized = try await service.recognizeText(in: image)

        #expect(recognized.lines == ["一行目", "二行目"])
        #expect(recognized.text == "一行目\n二行目")
    }

    @Test("A blank fragment does not swallow the text around it")
    func blankFragmentsAreDroppedNotTheRest() async throws {
        let image = try #require(makeStubImage())
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("  ", x: 0.05, y: 0.80),
            fragment("本文", x: 0.05, y: 0.60)
        ])
        let service = TextRecognitionService(provider: provider)

        let recognized = try await service.recognizeText(in: image)

        #expect(recognized.lines == ["本文"])
    }

    @Test("An engine failure surfaces as a recognition failure, not as emptiness")
    func engineFailureIsSurfaced() async throws {
        let image = try #require(makeStubImage())
        let provider = FakeTextRecognitionProvider(error: .recognitionFailed("engine down"))
        let service = TextRecognitionService(provider: provider)

        // The specific case matters: asserting only the error *type* would
        // also pass if the service swallowed the failure and reported
        // « nothing recognised », which is exactly the confusion to prevent.
        await #expect(throws: TextRecognitionError.recognitionFailed("engine down")) {
            _ = try await service.recognizeText(in: image)
        }
    }
}
