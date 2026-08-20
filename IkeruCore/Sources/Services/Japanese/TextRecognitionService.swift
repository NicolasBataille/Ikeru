import Foundation
import CoreGraphics
// `CGImagePropertyOrientation` and the `CGImageSource` decoding below live in
// ImageIO, which exists on watchOS — unlike Vision. Importing it here rather
// than relying on Vision re-exporting it keeps the watch build compiling.
import ImageIO
import os

// MARK: - Recognized Text Fragment

/// One piece of text the recognition engine returned, with where it sat on the
/// page.
///
/// ## Coordinate convention — read this before fabricating a fixture
///
/// `boundingBox` follows Vision's convention: **normalised** (0…1 on both axes)
/// and **bottom-left origin**, so the top of the page has the *higher* `y`.
/// Reading order is therefore *descending* `y`, not ascending. A test fixture
/// built the other way round passes a naive sort and is wrong on device.
public struct RecognizedTextFragment: Sendable, Equatable {

    /// The text as the engine read it. Never rewritten — the learner's text is
    /// theirs, and any correction happens later, in the editable draft.
    public let text: String

    /// Where the fragment sits, Vision-normalised, bottom-left origin.
    public let boundingBox: CGRect

    /// Engine confidence, 0.0 (no confidence) to 1.0 (certain).
    public let confidence: Double


    public init(text: String, boundingBox: CGRect, confidence: Double) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

// MARK: - Recognized Text

/// The assembled result of reading a photo: the page, in reading order.
public struct RecognizedText: Sendable, Equatable {

    /// One entry per visual line, top to bottom.
    public let lines: [String]

    /// The lines joined by `\n`. This is what feeds the editable draft.
    public let text: String

    /// Mean confidence over the fragments that produced this text.
    public let confidence: Double
    /// How many fragments the engine read and `subject(of:)` set aside — the
    /// interface of the app the photo was taken through, thumbnails, captions.
    ///
    /// Carried so the capture screen can SAY that something was left out. A
    /// filter the learner cannot see is a filter they cannot correct: they
    /// would re-photograph the same sign, get the same two lines, and never
    /// learn that the caption underneath was dropped on purpose.
    public var discardedFragmentCount: Int = 0

    public init(lines: [String], text: String, confidence: Double) {
        self.lines = lines
        self.text = text
        self.confidence = confidence
    }

    /// Assemble fragments into a page: group them into visual lines, order them
    /// the way a human reads, join.
    ///
    /// Vision hands its observations back in an order that is not the order of
    /// the page, so position is the only trustworthy signal. Fragments sharing
    /// a line are joined with no separator: Japanese has no inter-word space,
    /// and inserting one would rewrite the learner's text.
    public static func assemble(from fragments: [RecognizedTextFragment]) -> RecognizedText {
        let grouped = readingOrderLines(fragments)
        let lines = grouped.map { line in
            line.map(\.text).joined()
        }
        let confidences = fragments.map(\.confidence)
        let mean = confidences.isEmpty
            ? 0
            : confidences.reduce(0, +) / Double(confidences.count)

        return RecognizedText(
            lines: lines,
            text: lines.joined(separator: "\n"),
            confidence: mean
        )
    }

    /// Group fragments into visual lines and sort everything into reading
    /// order: lines top → bottom, fragments left → right inside a line.
    ///
    /// Two fragments belong to the same line when their vertical midpoints are
    /// closer than half the taller box — a tolerance rather than an equality,
    /// because a photographed page is never perfectly level.
    public static func readingOrderLines(
        _ fragments: [RecognizedTextFragment]
    ) -> [[RecognizedTextFragment]] {
        // Top of the page = higher y (bottom-left origin), hence descending.
        let topDown = fragments.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var lines: [[RecognizedTextFragment]] = []
        for fragment in topDown {
            guard let current = lines.last, let reference = current.first else {
                lines.append([fragment])
                continue
            }
            let tallest = max(reference.boundingBox.height, fragment.boundingBox.height)
            let tolerance = tallest / 2
            let gap = abs(reference.boundingBox.midY - fragment.boundingBox.midY)

            if gap <= tolerance {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        return lines.map { line in
            line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        }
    }
}

// MARK: - Text Recognition Error

/// Errors that can occur while reading text off a photo.
public enum TextRecognitionError: Error, LocalizedError, Equatable, Sendable {

    /// The engine came back with nothing at all.
    ///
    /// Measured on this codebase (Vision, `recognitionLanguages ["ja"]`,
    /// `.accurate`, `usesLanguageCorrection false`): horizontal printed
    /// Japanese is read exactly, **vertical Japanese returns zero characters**,
    /// and none of the four image orientations rescues it. The image was
    /// verified to be properly inked (2.95 % dark pixels against 3.41 % for the
    /// horizontal control), so this is the engine, not the photo.
    ///
    /// Product decision (Nico, 2026-08-19): when nothing comes back we *say*
    /// that vertical text is not supported yet, instead of showing an empty
    /// result or letting the learner believe their photo was bad. The case is
    /// named for what was measured — no horizontal text was found — because we
    /// cannot know the photo actually was vertical.
    case noHorizontalTextFound

    /// The recognition engine itself failed.
    case recognitionFailed(String)

    /// The image data could not be decoded into a picture at all.
    ///
    /// Thrown by ``TextRecognitionService/recognizeText(in:)-(Data)`` when the
    /// bytes handed over are not a picture the device can open. Distinct from
    /// ``noHorizontalTextFound``: nothing was *read* because there was nothing
    /// to read, and telling the learner « vertical text » there would be a lie.
    case imageUnreadable

    /// Catalogue key, rendered by the view layer.
    ///
    /// A key rather than a string: `String(localized:)` inside IkeruCore
    /// resolves the wrong bundle and ignores the app's `AppLocale` override.
    /// See CLAUDE.md.
    public var messageKey: String {
        switch self {
        case .noHorizontalTextFound: "import.photo.error.verticalNotSupported"
        case .recognitionFailed: "import.photo.error.recognitionFailed"
        case .imageUnreadable: "import.photo.error.imageUnreadable"
        }
    }

    /// Developer-facing description. The learner sees `messageKey` instead.
    public var errorDescription: String? {
        switch self {
        case .noHorizontalTextFound:
            "No horizontal Japanese text was found in the image."
        case .recognitionFailed(let detail):
            "Text recognition failed: \(detail)"
        case .imageUnreadable:
            "The image could not be read for recognition."
        }
    }
}

// MARK: - Text Recognition Provider Protocol

/// Abstraction over the recognition backend, so the service can be tested
/// without a camera and the engine can be swapped later.
public protocol TextRecognitionProvider: Sendable {
    /// Return every fragment the engine read, in whatever order it likes —
    /// ordering is the service's job.
    ///
    /// - Parameter orientation: how the pixels are laid out relative to the way
    ///   the photo was framed. A phone camera stores a portrait shot rotated,
    ///   with the rotation recorded in metadata; handing those pixels over as
    ///   if they were upright makes horizontal Japanese arrive sideways, the
    ///   engine read nothing, and the app blame « vertical text » for a photo
    ///   that was perfectly horizontal.
    func recognizeFragments(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [RecognizedTextFragment]
}

#if canImport(Vision)
import Vision

// MARK: - Vision Text Recognition Provider

/// On-device recognition of continuous Japanese text using Apple's Vision
/// framework. Fully offline — no network, no paid API.
///
/// The settings below are exactly those the vertical-text measurement was made
/// under (see `TextRecognitionError.noHorizontalTextFound`). Changing them
/// invalidates that measurement, so re-measure before touching them.
/// `usesLanguageCorrection` stays `false`: correcting the learner's text would
/// break the promise that what they photographed is what they get.
public struct VisionTextRecognitionProvider: TextRecognitionProvider, Sendable {

    public init() {}

    public func recognizeFragments(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [RecognizedTextFragment] {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            let request = VNRecognizeTextRequest { request, error in
                guard !resumed else { return }
                resumed = true

                if let error {
                    continuation.resume(throwing: TextRecognitionError.recognitionFailed(
                        error.localizedDescription
                    ))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: Self.fragments(from: observations))
            }

            request.recognitionLanguages = ["ja"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(
                cgImage: image,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: TextRecognitionError.recognitionFailed(
                    error.localizedDescription
                ))
            }
        }
    }

    /// Keep the top candidate of each observation. Continuous text is read line
    /// by line, so — unlike the single-character handwriting path — alternative
    /// candidates are noise here, not choices to offer.
    private static func fragments(
        from observations: [VNRecognizedTextObservation]
    ) -> [RecognizedTextFragment] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedTextFragment(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: Double(candidate.confidence)
            )
        }
    }
}
#endif

// MARK: - Text Recognition Service

/// Reads Japanese text off a photo, on the device.
///
/// The service owns the product decisions — what counts as « nothing was
/// recognised », and in which order the page is read — so both are testable in
/// one place with a fake provider. The provider only reports what the engine
/// saw.
public struct TextRecognitionService: Sendable {

    private let provider: any TextRecognitionProvider

    public init(provider: any TextRecognitionProvider) {
        self.provider = provider
    }

    #if canImport(Vision)
    public init() {
        self.provider = VisionTextRecognitionProvider()
    }
    #endif

    /// Recognise the text of an image.
    /// - Parameters:
    ///   - image: the photographed or picked page.
    ///   - orientation: how the pixels sit relative to the framing. Defaults to
    ///     `.up`; pass the real one for anything coming out of a camera, or use
    ///     ``recognizeText(in:)-(Data)``, which reads it from the file itself.
    /// - Returns: the page in reading order.
    /// - Throws: ``TextRecognitionError/noHorizontalTextFound`` when the engine
    ///   read nothing usable — the case the vertical-text message hangs on.
    public func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> RecognizedText {
        let fragments = try await provider.recognizeFragments(in: image, orientation: orientation)

        // Blank fragments are the same emptiness as no fragments at all: the
        // learner must not be shown an empty « result ».
        let usable = fragments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let kept = Self.subject(of: usable)
        guard !kept.isEmpty else {
            Logger.content.info("Text recognition returned nothing usable (likely vertical text)")
            throw TextRecognitionError.noHorizontalTextFound
        }

        var recognized = RecognizedText.assemble(from: kept)
        recognized.discardedFragmentCount = usable.count - kept.count
        let discarded = recognized.discardedFragmentCount
        Logger.content.info(
            "Text recognition read \(recognized.lines.count) line(s), \(discarded) set aside")
        return recognized
    }

    // MARK: - What the learner actually pointed the camera at

    /// Narrows what the engine read down to the text that is plausibly the
    /// **subject** of the photo.
    ///
    /// Vision reads a picture, not an intention. Photograph a street sign on a
    /// screen and it returns the sign *and* the browser chrome, the article
    /// title, the share buttons, the thumbnail captions — measured on a real
    /// capture (2026-08-20): 12 lines, of which the 2 the learner wanted.
    /// Faithful, and useless: they then delete eleven lines by hand, on a
    /// phone.
    ///
    /// ## Layout, not script
    ///
    /// The first version of this filtered on *character class* — keep what
    /// carries kana or kanji — and it worked on that capture **by accident**:
    /// the interface around the sign happened to be in French and English.
    /// Photograph a Japanese website, or a phone set to Japanese, and it filters
    /// nothing at all.
    ///
    /// So the work is done by **layout analysis** instead. Fragments are
    /// grouped into blocks by geometry — adjacency, alignment, comparable text
    /// size — and the dominant block wins. A sign is one block; the chrome is
    /// another; each thumbnail caption is its own. That reasoning does not care
    /// what alphabet anything is in, which is exactly why it survives a
    /// Japanese interface.
    ///
    /// The script test survives as a **secondary** guard, applied to blocks
    /// rather than to fragments: a block with no Japanese in it is not what a
    /// learner of Japanese pointed a camera at. It can no longer split a
    /// sentence, because it now judges whole blocks.
    static func subject(of fragments: [RecognizedTextFragment]) -> [RecognizedTextFragment] {
        let blocks = textBlocks(of: fragments)
        let japanese = blocks.filter { block in block.contains { carriesJapanese($0.text) } }
        let candidates = japanese.isEmpty ? [] : japanese
        guard let dominant = candidates.max(by: { weight(of: $0) < weight(of: $1) }) else {
            return []
        }
        // Un bloc voisin de poids comparable fait partie du même sujet : une
        // affiche a un titre et un corps, un panneau deux lignes séparées par
        // un trait. On ne garde pas QUE le maximum, on garde ce qui joue dans
        // la même catégorie.
        let threshold = weight(of: dominant) * siblingRatio
        return candidates.filter { weight(of: $0) >= threshold }.flatMap { $0 }
    }

    /// How much of the frame a block occupies — the sum of its fragments'
    /// areas, not its bounding box.
    ///
    /// The bounding box would reward a block whose pieces are scattered across
    /// the screen, which is precisely what a row of interface buttons is. Ink
    /// rewards the one that actually fills the frame.
    static func weight(of block: [RecognizedTextFragment]) -> Double {
        block.reduce(0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
    }

    /// How light a block may be, relative to the heaviest, and still count as
    /// part of the same subject.
    static let siblingRatio: Double = 0.35

    /// Groups fragments into visual blocks.
    ///
    /// Two fragments belong together when they read as one piece of text: their
    /// text is of comparable size, they overlap horizontally (so they sit in
    /// the same column), and the vertical gap between them is no more than a
    /// couple of lines. Transitive — a block is a chain, so a five-line
    /// paragraph is one block, not four pairs.
    static func textBlocks(of fragments: [RecognizedTextFragment]) -> [[RecognizedTextFragment]] {
        var remaining = fragments
        var blocks: [[RecognizedTextFragment]] = []

        while let seed = remaining.first {
            remaining.removeFirst()
            var block = [seed]
            var grew = true
            while grew {
                grew = false
                for (index, candidate) in remaining.enumerated().reversed()
                where block.contains(where: { belongTogether($0, candidate) }) {
                    block.append(candidate)
                    remaining.remove(at: index)
                    grew = true
                }
            }
            blocks.append(block)
        }
        return blocks
    }

    /// Whether two fragments read as part of the same block.
    static func belongTogether(_ left: RecognizedTextFragment,
                               _ right: RecognizedTextFragment) -> Bool {
        let a = left.boundingBox, b = right.boundingBox
        guard a.height > 0, b.height > 0 else { return false }

        // Taille comparable : un titre et une légende ne sont pas le même bloc.
        let sizeRatio = max(a.height, b.height) / min(a.height, b.height)
        guard sizeRatio <= 2.0 else { return false }

        // Même colonne : les boîtes doivent se recouvrir horizontalement.
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        guard overlap > 0 else { return false }

        // Et se suivre : au plus deux interlignes d'écart vertical.
        let gap = max(a.minY, b.minY) - min(a.maxY, b.maxY)
        return gap <= max(a.height, b.height) * 2.0
    }

    /// Whether a fragment carries actual Japanese — kana or a CJK ideograph.
    ///
    /// Punctuation does not count. Vision happily returns 「：」 or a box glyph
    /// as its own fragment, and those would otherwise vouch for a block that is
    /// pure interface.
    static func carriesJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)      // hiragana
                || (0x30A0...0x30FF).contains(scalar.value)  // katakana
                || (0x4E00...0x9FFF).contains(scalar.value)  // CJK unifié
                || (0x3400...0x4DBF).contains(scalar.value)  // extension A
        }
    }

    /// Recognise the text of an encoded picture — what a camera or a photo
    /// library actually hands over.
    ///
    /// This overload exists so the orientation is never lost on the way in.
    /// Decoding with `UIImage(data:)?.cgImage` drops the rotation a phone
    /// records in metadata, and Vision then reads a portrait photo sideways:
    /// zero characters, and the app blaming « vertical text » for a horizontal
    /// page. Here the orientation is read off the file and passed on.
    ///
    /// - Parameter data: the encoded picture (JPEG, HEIC, PNG…).
    /// - Returns: the page in reading order.
    /// - Throws: ``TextRecognitionError/imageUnreadable`` when the bytes are not
    ///   a decodable picture, otherwise the same errors as
    ///   ``recognizeText(in:orientation:)``.
    public func recognizeText(in data: Data) async throws -> RecognizedText {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Logger.content.error("Text recognition could not decode the image data")
            throw TextRecognitionError.imageUnreadable
        }
        return try await recognizeText(in: image, orientation: Self.orientation(of: source))
    }

    /// The orientation recorded in the file, or `.up` when it says nothing.
    ///
    /// The tag is an integer 1…8 (EXIF); anything outside that range is treated
    /// as absent rather than trusted.
    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return .up
        }
        return orientation
    }
}
