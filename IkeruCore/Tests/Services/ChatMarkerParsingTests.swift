import Testing
import Foundation
@testable import IkeruCore

// MARK: - ChatMarkerParser Tests

/// Exercises `ChatMarkerParser.parse` directly (no mock AI provider needed —
/// the parser is pure). Covers the tolerance requirements from remediation
/// item 6.4: markers recognized anywhere in the text (not just whole-line),
/// tolerant separators (ASCII/fullwidth arrows, pipes, equals, colons,
/// parens), and the no-raw-leak guarantee for both parseable and
/// unparseable sentinel markers.
@Suite("ChatMarkerParsing")
struct ChatMarkerParsingTests {

    // MARK: - Canonical Whole-Line Markers

    @Test("Canonical CORRECTION on its own line parses and content is prose only")
    func canonicalCorrectionOwnLine() {
        let text = """
        いいですね！
        [CORRECTION: 食べます → 食べました | Past tense needed here]
        """
        let result = ChatMarkerParser.parse(text)

        #expect(result.content == "いいですね！")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "食べます")
        #expect(result.corrections[0].corrected == "食べました")
        #expect(result.corrections[0].explanation == "Past tense needed here")
        #expect(result.vocabularyHints.isEmpty)
    }

    @Test("Canonical VOCAB with reading parses; VOCAB without reading yields empty reading")
    func canonicalVocab() {
        let withReading = ChatMarkerParser.parse("散歩しましょう！\n[VOCAB: 散歩(さんぽ) = walk]")
        #expect(withReading.content == "散歩しましょう！")
        #expect(withReading.vocabularyHints.count == 1)
        #expect(withReading.vocabularyHints[0].word == "散歩")
        #expect(withReading.vocabularyHints[0].reading == "さんぽ")
        #expect(withReading.vocabularyHints[0].meaning == "walk")

        let withoutReading = ChatMarkerParser.parse("水を飲みます。\n[VOCAB: 水 = water]")
        #expect(withoutReading.vocabularyHints.count == 1)
        #expect(withoutReading.vocabularyHints[0].word == "水")
        #expect(withoutReading.vocabularyHints[0].reading == "")
        #expect(withoutReading.vocabularyHints[0].meaning == "water")
    }

    // MARK: - Inline Markers

    @Test("Inline marker with leading prose on the same line strips cleanly, no raw leak")
    func inlineMarkerSameLine() {
        let result = ChatMarkerParser.parse("Nice! [CORRECTION: 食べます → 食べました | past tense]")

        #expect(result.content == "Nice!")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "食べます")
        #expect(result.corrections[0].corrected == "食べました")
        #expect(result.corrections[0].explanation == "past tense")
        #expect(!result.content.contains("["))
    }

    // MARK: - Arrow Variants

    @Test("Arrow variant -> parses")
    func arrowVariantAsciiArrow() {
        let result = ChatMarkerParser.parse("[CORRECTION: 食べます -> 食べました | past tense]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "食べます")
        #expect(result.corrections[0].corrected == "食べました")
    }

    @Test("Arrow variant => parses")
    func arrowVariantFatArrow() {
        let result = ChatMarkerParser.parse("[CORRECTION: 食べます => 食べました | past tense]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "食べます")
        #expect(result.corrections[0].corrected == "食べました")
    }

    @Test("Arrow variant ⇒ parses")
    func arrowVariantDoubleArrow() {
        let result = ChatMarkerParser.parse("[CORRECTION: 食べます ⇒ 食べました | past tense]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].corrected == "食べました")
    }

    // MARK: - Missing Spaces

    @Test("Missing spaces around all separators still parses (CORRECTION and VOCAB)")
    func missingSpacesAroundSeparators() {
        let correction = ChatMarkerParser.parse("[CORRECTION:食べます→食べました|past]")
        #expect(correction.corrections.count == 1)
        #expect(correction.corrections[0].original == "食べます")
        #expect(correction.corrections[0].corrected == "食べました")
        #expect(correction.corrections[0].explanation == "past")

        let vocab = ChatMarkerParser.parse("[VOCAB:公園(こうえん)=park]")
        #expect(vocab.vocabularyHints.count == 1)
        #expect(vocab.vocabularyHints[0].word == "公園")
        #expect(vocab.vocabularyHints[0].reading == "こうえん")
        #expect(vocab.vocabularyHints[0].meaning == "park")
    }

    // MARK: - Fullwidth Separators

    @Test("Fullwidth colon/arrow/pipe parse for CORRECTION")
    func fullwidthCorrectionSeparators() {
        let result = ChatMarkerParser.parse("[CORRECTION：食べます→食べました｜past]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "食べます")
        #expect(result.corrections[0].corrected == "食べました")
        #expect(result.corrections[0].explanation == "past")
    }

    @Test("Fullwidth colon/equals parse for VOCAB")
    func fullwidthVocabSeparators() {
        let result = ChatMarkerParser.parse("[VOCAB：水＝water]")
        #expect(result.vocabularyHints.count == 1)
        #expect(result.vocabularyHints[0].word == "水")
        #expect(result.vocabularyHints[0].reading == "")
        #expect(result.vocabularyHints[0].meaning == "water")
    }

    // MARK: - Lowercase Tag

    @Test("Lowercase tag name parses")
    func lowercaseTagName() {
        let result = ChatMarkerParser.parse("[correction: a → b]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "a")
        #expect(result.corrections[0].corrected == "b")
    }

    // MARK: - Multiple Markers Per Line

    @Test("Two markers on one line both parse and both are stripped from content")
    func twoMarkersOneLine() {
        let result = ChatMarkerParser.parse("Great! [CORRECTION: a → b] and [VOCAB: c = d]")

        #expect(result.content == "Great! and")
        #expect(result.corrections.count == 1)
        #expect(result.vocabularyHints.count == 1)
        #expect(!result.content.contains("["))
    }

    // MARK: - Optional Explanation

    @Test("CORRECTION without explanation yields empty explanation")
    func correctionWithoutExplanation() {
        let result = ChatMarkerParser.parse("[CORRECTION: 食べます → 食べました]")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].explanation == "")
    }

    // MARK: - Unparseable Sentinel

    @Test("Unparseable CORRECTION (no arrow) yields zero corrections and no raw leak")
    func unparseableCorrectionNoArrow() {
        let result = ChatMarkerParser.parse("[CORRECTION: no arrow here]")

        #expect(result.corrections.isEmpty)
        #expect(!result.content.contains("[CORRECTION"))
        #expect(!result.content.contains("no arrow here") || result.content.isEmpty)
    }

    @Test("Unparseable VOCAB (no equals) yields zero hints and no raw leak")
    func unparseableVocabNoEquals() {
        let result = ChatMarkerParser.parse("Some text [VOCAB: no equals here] more text")

        #expect(result.vocabularyHints.isEmpty)
        #expect(!result.content.contains("[VOCAB"))
        #expect(result.content == "Some text more text")
    }

    // MARK: - Non-Sentinel Brackets Preserved

    @Test("Non-sentinel bracketed text is left untouched")
    func nonSentinelBracketsPreserved() {
        let result = ChatMarkerParser.parse("He said [laughs] hello")

        #expect(result.content == "He said [laughs] hello")
        #expect(result.corrections.isEmpty)
        #expect(result.vocabularyHints.isEmpty)
    }

    @Test("Bracketed numeric footnote is left untouched")
    func numericBracketPreserved() {
        let result = ChatMarkerParser.parse("He said [1] left")

        #expect(result.content == "He said [1] left")
        #expect(result.corrections.isEmpty)
        #expect(result.vocabularyHints.isEmpty)
    }

    // MARK: - Mixed Content

    @Test("Multiple corrections and hints mixed with prose all parse; content is clean prose")
    func multipleMarkersMixedWithProse() {
        let text = """
        そうですか！楽しかったですか？
        [CORRECTION: 行きます → 行きました | Use past tense for completed actions]
        今日は公園に行きましょう。
        [VOCAB: 映画(えいが) = movie]
        [VOCAB: 公園(こうえん) = park]
        """
        let result = ChatMarkerParser.parse(text)

        #expect(result.content == "そうですか！楽しかったですか？\n今日は公園に行きましょう。")
        #expect(result.corrections.count == 1)
        #expect(result.corrections[0].original == "行きます")
        #expect(result.vocabularyHints.count == 2)
        #expect(result.vocabularyHints[0].word == "映画")
        #expect(result.vocabularyHints[1].word == "公園")
        #expect(!result.content.contains("[CORRECTION"))
        #expect(!result.content.contains("[VOCAB"))
    }

    // MARK: - No Raw Leak (General)

    @Test("Recognized markers never leak raw bracket syntax into content, case-insensitively")
    func noRawLeakAcrossCases() {
        let inputs = [
            "[CORRECTION: a → b | c]",
            "[correction: a → b | c]",
            "[Correction: a → b | c]",
            "[VOCAB: a(b) = c]",
            "[vocab: a(b) = c]",
            "[Vocab: a(b) = c]"
        ]

        for input in inputs {
            let result = ChatMarkerParser.parse(input)
            #expect(!result.content.contains("[CORRECTION"))
            #expect(!result.content.contains("[VOCAB"))
            #expect(!result.content.contains("[correction"))
            #expect(!result.content.contains("[vocab"))
        }
    }
}
