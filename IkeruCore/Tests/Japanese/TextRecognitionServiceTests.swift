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

    /// Where the orientation actually handed to the engine is recorded.
    ///
    /// A reference box rather than a `var`: the provider is a `Sendable`
    /// struct, so it cannot mutate itself. Without this the doc comment below
    /// was a promise nothing kept — the orientation parameter existed, and no
    /// test ever proved it arrived.
    let seen = OrientationLog()

    /// Records what it was handed, so a test can assert the orientation read
    /// off the file actually reaches the engine — the point of the parameter.
    func recognizeFragments(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [RecognizedTextFragment] {
        seen.record(orientation)
        if let error { throw error }
        return fragments
    }
}

/// Thread-safe one-slot recorder for the orientation the provider received.
private final class OrientationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CGImagePropertyOrientation?

    func record(_ orientation: CGImagePropertyOrientation) {
        lock.lock()
        defer { lock.unlock() }
        value = orientation
    }

    var last: CGImagePropertyOrientation? {
        lock.lock()
        defer { lock.unlock() }
        return value
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

/// Encode a real 8×8 JPEG, optionally stamped with an EXIF orientation tag.
///
/// The bytes matter: the point of ``TextRecognitionService/recognizeText(in:)``
/// taking `Data` is that it reads the tag off the file. A fixture built from a
/// bare `CGImage` could not tell a working implementation from one that
/// hardcodes `.up`.
private func makeJPEGData(orientation: UInt32?) -> Data? {
    guard let context = CGContext(
        data: nil,
        width: 8,
        height: 8,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    guard let image = context.makeImage() else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, "public.jpeg" as CFString, 1, nil
    ) else { return nil }

    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
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

    // MARK: Encoded pictures — the orientation must survive the way in

    @Test("The EXIF orientation of the file reaches the engine")
    func exifOrientationReachesTheEngine() async throws {
        // Tag 6 is « rotate 90° clockwise » — what a phone writes for a shot
        // framed in portrait. Handing those pixels over as `.up` makes
        // horizontal Japanese arrive sideways, Vision read nothing, and the
        // screen blame « vertical text » for a perfectly horizontal page.
        let data = try #require(makeJPEGData(orientation: 6))
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("横書き", x: 0.05, y: 0.80)
        ])
        let service = TextRecognitionService(provider: provider)

        _ = try await service.recognizeText(in: data)

        #expect(provider.seen.last == .right)
    }

    @Test("A file with no orientation tag is read upright, not guessed")
    func missingOrientationDefaultsToUp() async throws {
        let data = try #require(makeJPEGData(orientation: nil))
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("横書き", x: 0.05, y: 0.80)
        ])
        let service = TextRecognitionService(provider: provider)

        _ = try await service.recognizeText(in: data)

        #expect(provider.seen.last == .up)
    }

    @Test("Bytes that are not a picture say so, instead of blaming vertical text")
    func undecodableDataIsNamedForWhatItIs() async throws {
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("横書き", x: 0.05, y: 0.80)
        ])
        let service = TextRecognitionService(provider: provider)

        await #expect(throws: TextRecognitionError.imageUnreadable) {
            _ = try await service.recognizeText(in: Data("not a picture".utf8))
        }
        // And the engine was never asked: there was nothing to read.
        #expect(provider.seen.last == nil)
    }

    @Test("The text of an encoded picture comes back in reading order")
    func encodedPictureIsReadInOrder() async throws {
        let data = try #require(makeJPEGData(orientation: 1))
        let provider = FakeTextRecognitionProvider(fragments: [
            fragment("二行目", x: 0.05, y: 0.60),
            fragment("一行目", x: 0.05, y: 0.80)
        ])
        let service = TextRecognitionService(provider: provider)

        let recognized = try await service.recognizeText(in: data)

        #expect(recognized.text == "一行目\n二行目")
    }
}

// MARK: - Ce que la photo visait

/// Rejoue la capture réelle du 2026-08-20 : un panneau japonais photographié
/// **sur un écran**, donc entouré du chrome du navigateur, du titre de
/// l'article en anglais, des boutons de partage et de trois vignettes.
///
/// Vision avait tout ramassé — douze lignes, dont les deux voulues. Fidèle, et
/// inutilisable : il fallait en effacer onze à la main, sur un téléphone.
@Suite("OCR — ne garder que le sujet de la photo")
struct TextRecognitionSubjectTests {

    /// Un fragment placé dans le cadre, en convention Vision (origine en bas).
    ///
    /// `x` et `width` comptent autant que la hauteur : ce sont eux qui disent
    /// si deux morceaux sont dans la même colonne. Une première version les
    /// figeait, et trois boutons d'une barre d'outils — côte à côte dans la
    /// réalité — se retrouvaient empilés dans un même bloc.
    private func fragment(_ text: String, height: Double, y: Double = 0.5,
                          x: Double = 0.1, width: Double = 0.5)
        -> RecognizedTextFragment {
        RecognizedTextFragment(text: text,
                               boundingBox: CGRect(x: x, y: y, width: width, height: height),
                               confidence: 0.9)
    }

    /// L'écran réel, reconstitué : le panneau en grand, tout le reste petit.
    private var screenshotFragments: [RecognizedTextFragment] {
        [
            fragment("Enregistrements", height: 0.02, y: 0.96, x: 0.70, width: 0.25),
            fragment("Kanji characters", height: 0.02, y: 0.92, x: 0.15, width: 0.25),
            fragment("Traffic signs", height: 0.02, y: 0.92, x: 0.55, width: 0.20),
            fragment("JapanesePod101", height: 0.02, y: 0.84, x: 0.12, width: 0.25),
            fragment("：", height: 0.015, y: 0.83, x: 0.85, width: 0.02),
            fragment("自転車を除く", height: 0.055, y: 0.66),
            fragment("一方通行", height: 0.055, y: 0.60),
            fragment("Learn Japanese Kanji — Everyday Kanji", height: 0.018, y: 0.36,
                     x: 0.08, width: 0.55),
            fragment("Partager", height: 0.015, y: 0.31, x: 0.15, width: 0.15),
            fragment("Enregistrer", height: 0.015, y: 0.31, x: 0.60, width: 0.15),
            fragment("止まれ", height: 0.012, y: 0.18, x: 0.40, width: 0.10),
            fragment("歩行者", height: 0.012, y: 0.16, x: 0.12, width: 0.12),
        ]
    }

    @Test("Le panneau survit, l'interface autour disparaît")
    func onlyTheSignSurvives() {
        let kept = TextRecognitionService.subject(of: screenshotFragments).map(\.text)
        #expect(kept == ["自転車を除く", "一方通行"], "gardé : \(kept)")
    }

    /// Un bloc SÉPARÉ, sans un mot de japonais, n'est pas ce qu'un apprenant de
    /// japonais a visé — même s'il occupe plus de place.
    @Test("Un bloc sans japonais est écarté, même volumineux")
    func latinOnlyBlocksAreRefusedWhateverTheirSize() {
        let kept = TextRecognitionService.subject(of: [
            fragment("BREAKING NEWS", height: 0.10, y: 0.85),
            fragment("Subscribe today", height: 0.10, y: 0.72),
            fragment("お知らせ", height: 0.08, y: 0.30),
        ]).map(\.text)
        #expect(kept == ["お知らせ"], "gardé : \(kept)")
    }

    /// Le pendant, et c'est le gain du passage aux blocs : un titre bilingue
    /// est UN texte. L'ancien filtre, qui jugeait fragment par fragment,
    /// l'aurait coupé en deux.
    @Test("Un bloc bilingue reste entier")
    func aBilingualBlockStaysWhole() {
        let kept = TextRecognitionService.subject(of: [
            fragment("Bicycle", height: 0.05, y: 0.70),
            fragment("自転車", height: 0.05, y: 0.64),
        ]).map(\.text)
        #expect(kept.count == 2, "gardé : \(kept)")
    }

    /// Le cas où le filtre par écriture était aveugle, et où la mise en page
    /// tranche : le décor autour de la photo est LUI AUSSI en japonais.
    @Test("Une interface en japonais autour du sujet est quand même écartée")
    func aJapaneseInterfaceAroundTheSubjectIsStillDropped() {
        let kept = TextRecognitionService.subject(of: [
            // Barre d'application, en japonais, en haut et en petit.
            fragment("設定", height: 0.018, y: 0.96, x: 0.05, width: 0.10),
            fragment("共有", height: 0.018, y: 0.96, x: 0.45, width: 0.10),
            fragment("保存", height: 0.018, y: 0.96, x: 0.80, width: 0.10),
            // Le panneau visé.
            fragment("自転車を除く", height: 0.055, y: 0.66),
            fragment("一方通行", height: 0.055, y: 0.60),
            // Légende d'une vignette, en japonais elle aussi.
            fragment("駐車禁止の標識", height: 0.012, y: 0.16, x: 0.60, width: 0.25),
        ]).map(\.text)
        #expect(kept == ["自転車を除く", "一方通行"], "gardé : \(kept)")
    }

    /// La règle ne peut pas être « écarter tout ce qui contient du latin » :
    /// un vrai texte japonais porte des URL, des noms, des mots empruntés.
    @Test("Un japonais mêlé de latin reste intact")
    func mixedScriptSurvives() {
        let kept = TextRecognitionService.subject(of: [
            fragment("今日のライブ最高だった🎉 https://example.com", height: 0.05),
            fragment("@friend_jp またね〜", height: 0.05),
        ]).map(\.text)
        #expect(kept.count == 2)
    }

    /// Le seuil de proéminence ne doit mordre QUE quand un texte domine
    /// vraiment. Sur une page de texte courant, toutes les lignes se valent.
    @Test("Une page de texte uniforme ne perd aucune ligne")
    func uniformPagesKeepEveryLine() {
        let page = (0..<20).map { fragment("行\($0)です。", height: 0.028 + Double($0 % 3) * 0.002) }
        #expect(TextRecognitionService.subject(of: page).count == 20)
    }

    /// Le cas que la vision nomme explicitement — « un menu photographié à
    /// Kyōto ». Les plats font environ la moitié du titre et doivent rester.
    @Test("Sur un menu, les plats survivent au titre")
    func menuItemsSurviveTheTitle() {
        let kept = TextRecognitionService.subject(of: [
            fragment("本日のおすすめ", height: 0.08, y: 0.80),
            fragment("鶏の唐揚げ定食", height: 0.042, y: 0.70),
            fragment("季節の野菜天ぷら", height: 0.040, y: 0.64),
            fragment("冷やし中華", height: 0.038, y: 0.58),
        ]).map(\.text)
        #expect(kept.count == 4, "gardé : \(kept)")
    }

    /// Le défaut constaté sur device le 2026-08-20, deuxième passe : Vision a
    /// lu une icône de partage comme 「山」, et ce seul caractère cautionnait
    /// tout un bloc d'interface anglaise. Tester la PRÉSENCE de japonais ne
    /// suffit pas ; il faut sa PROPORTION.
    @Test("Un idéogramme parasite ne cautionne pas un bloc d'interface")
    func oneStrayGlyphDoesNotVouchForAnEnglishBlock() {
        let kept = TextRecognitionService.subject(of: [
            fragment("自転車を除く", height: 0.055, y: 0.66),
            fragment("一方通行", height: 0.055, y: 0.60),
            // Le titre de l'article et la barre de partage, fusionnés en un
            // bloc par leur disposition — et 山 est une icône mal lue.
            fragment("Learn Japanese Kanji — Everyday Kanji（Traffic", height: 0.018,
                     y: 0.38, x: 0.08, width: 0.60),
            fragment("Signs pt. 1) - JapanesePod101.com Blog", height: 0.018,
                     y: 0.35, x: 0.08, width: 0.60),
            fragment("山 Partager", height: 0.016, y: 0.32, x: 0.10, width: 0.20),
        ]).map(\.text)
        #expect(kept == ["自転車を除く", "一方通行"], "gardé : \(kept)")
    }

    /// Le seuil doit rester bas : ce sont exactement les textes que la feature
    /// existe pour lire.
    @Test("Un japonais minoritaire mais réel passe quand même")
    func genuineJapaneseSurvivesEvenWhenOutnumbered() {
        // Un panneau bilingue : trois kanji pour sept lettres.
        #expect(TextRecognitionService.isJapaneseBlock([
            fragment("Bicycle", height: 0.05, y: 0.70),
            fragment("自転車", height: 0.05, y: 0.64),
        ]))
        // Un tweet avec une mention et un lien.
        #expect(TextRecognitionService.isJapaneseBlock([
            fragment("@friend_jp 今日のライブ最高だった", height: 0.03),
        ]))
    }

    @Test("Un bloc purement latin n'est jamais japonais")
    func latinBlocksAreNeverJapanese() {
        #expect(!TextRecognitionService.isJapaneseBlock([
            fragment("Learn Japanese Kanji — Everyday Kanji", height: 0.02),
        ]))
        #expect(!TextRecognitionService.isJapaneseBlock([]))
    }

    @Test("La ponctuation seule ne compte pas comme du japonais")
    func punctuationIsNotJapanese() {
        #expect(!TextRecognitionService.carriesJapanese("：〜「」…"))
        #expect(!TextRecognitionService.carriesJapanese("■ □ ●"))
        #expect(!TextRecognitionService.carriesJapanese("Traffic signs"))
        #expect(TextRecognitionService.carriesJapanese("あ"))
        #expect(TextRecognitionService.carriesJapanese("ア"))
        #expect(TextRecognitionService.carriesJapanese("山"))
    }

    /// Un filtre invisible est un filtre incorrigible : l'apprenant
    /// rephotographierait le même panneau sans jamais comprendre qu'on a
    /// écarté la légende en dessous.
    @Test("Ce qui a été mis de côté est compté, pour pouvoir le dire")
    func discardedFragmentsAreCounted() async throws {
        let image = try #require(makeStubImage())
        let service = TextRecognitionService(
            provider: FakeTextRecognitionProvider(fragments: screenshotFragments))
        let recognized = try await service.recognizeText(in: image)
        #expect(recognized.text == "自転車を除く\n一方通行")
        #expect(recognized.discardedFragmentCount == 10)
    }

    /// Une photo où rien n'est japonais est la même impasse qu'une photo
    /// illisible : on le dit, on ne rend pas un résultat vide.
    @Test("Une image sans un mot de japonais lève l'erreur nommée")
    func aPhotoWithNoJapaneseIsNamedAsSuch() async throws {
        let image = try #require(makeStubImage())
        let service = TextRecognitionService(provider: FakeTextRecognitionProvider(fragments: [
            fragment("BREAKING NEWS", height: 0.3),
            fragment("Subscribe now", height: 0.2),
        ]))
        await #expect(throws: TextRecognitionError.noHorizontalTextFound) {
            _ = try await service.recognizeText(in: image)
        }
    }
}
