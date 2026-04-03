import Testing
import Foundation
@testable import IkeruCore

@Suite("PronunciationScorer")
struct PronunciationScorerTests {

    // MARK: - Normalization Tests

    @Suite("Normalization")
    struct NormalizationTests {

        @Test("Converts katakana to hiragana")
        func katakanaToHiragana() {
            let result = PronunciationScorer.normalize("カタカナ")
            #expect(result == "かたかな")
        }

        @Test("Strips whitespace")
        func stripsWhitespace() {
            let result = PronunciationScorer.normalize("こん にち は")
            #expect(result == "こんにちは")
        }

        @Test("Strips Japanese punctuation")
        func stripsJapanesePunctuation() {
            let result = PronunciationScorer.normalize("こんにちは。")
            #expect(result == "こんにちは")
        }

        @Test("Normalizes mixed katakana and hiragana")
        func mixedKatakanaHiragana() {
            let result = PronunciationScorer.normalize("ネコ が すき")
            #expect(result == "ねこがすき")
        }

        @Test("Empty string normalizes to empty")
        func emptyString() {
            let result = PronunciationScorer.normalize("")
            #expect(result == "")
        }
    }

    // MARK: - Scoring Tests

    @Suite("Scoring")
    struct ScoringTests {

        @Test("Exact match gives 1.0 accuracy")
        func exactMatch() {
            let result = PronunciationScorer.score(
                recognized: "こんにちは",
                expected: "こんにちは"
            )
            #expect(result.accuracy == 1.0)
        }

        @Test("Exact match with katakana vs hiragana gives 1.0 accuracy")
        func katakanaHiraganaMatch() {
            let result = PronunciationScorer.score(
                recognized: "コンニチハ",
                expected: "こんにちは"
            )
            #expect(result.accuracy == 1.0)
        }

        @Test("Partial match gives proportional accuracy")
        func partialMatch() {
            let result = PronunciationScorer.score(
                recognized: "こんにち",
                expected: "こんにちは"
            )
            // 4 out of 5 characters match
            #expect(result.accuracy > 0.7)
            #expect(result.accuracy < 1.0)
        }

        @Test("No match gives 0.0 accuracy")
        func noMatch() {
            let result = PronunciationScorer.score(
                recognized: "あいうえお",
                expected: "かきくけこ"
            )
            #expect(result.accuracy == 0.0)
        }

        @Test("Empty recognized gives 0.0 accuracy")
        func emptyRecognized() {
            let result = PronunciationScorer.score(
                recognized: "",
                expected: "こんにちは"
            )
            #expect(result.accuracy == 0.0)
        }

        @Test("Both empty gives 1.0 accuracy")
        func bothEmpty() {
            let result = PronunciationScorer.score(
                recognized: "",
                expected: ""
            )
            #expect(result.accuracy == 1.0)
        }

        @Test("Empty expected with non-empty recognized gives 0.0 accuracy")
        func emptyExpected() {
            let result = PronunciationScorer.score(
                recognized: "こんにちは",
                expected: ""
            )
            #expect(result.accuracy == 0.0)
        }

        @Test("Accuracy is clamped between 0.0 and 1.0")
        func accuracyClamped() {
            let result = PronunciationScorer.score(
                recognized: "ねこ",
                expected: "ねこ"
            )
            #expect(result.accuracy >= 0.0)
            #expect(result.accuracy <= 1.0)
        }

        @Test("Punctuation differences do not affect accuracy")
        func punctuationIgnored() {
            let result = PronunciationScorer.score(
                recognized: "こんにちは",
                expected: "こんにちは。"
            )
            #expect(result.accuracy == 1.0)
        }

        @Test("Whitespace differences do not affect accuracy")
        func whitespaceIgnored() {
            let result = PronunciationScorer.score(
                recognized: "こんにちは",
                expected: "こん にち は"
            )
            #expect(result.accuracy == 1.0)
        }
    }

    // MARK: - Diff Segment Tests

    @Suite("DiffSegments")
    struct DiffSegmentTests {

        @Test("Exact match produces only match segments")
        func exactMatchSegments() {
            let result = PronunciationScorer.score(
                recognized: "ねこ",
                expected: "ねこ"
            )
            #expect(result.diffSegments.count == 1)
            if case .match(let text) = result.diffSegments.first {
                #expect(text == "ねこ")
            } else {
                Issue.record("Expected match segment")
            }
        }

        @Test("Missing character produces missing segment")
        func missingCharacterSegments() {
            let result = PronunciationScorer.score(
                recognized: "ねこ",
                expected: "ねこだ"
            )
            let hasMissing = result.diffSegments.contains { segment in
                if case .missing = segment { return true }
                return false
            }
            #expect(hasMissing)
        }

        @Test("Extra character produces extra segment")
        func extraCharacterSegments() {
            let result = PronunciationScorer.score(
                recognized: "ねこだ",
                expected: "ねこ"
            )
            let hasExtra = result.diffSegments.contains { segment in
                if case .extra = segment { return true }
                return false
            }
            #expect(hasExtra)
        }

        @Test("No match produces missing and extra segments")
        func noMatchSegments() {
            let result = PronunciationScorer.score(
                recognized: "あ",
                expected: "か"
            )
            let hasMissing = result.diffSegments.contains { segment in
                if case .missing = segment { return true }
                return false
            }
            let hasExtra = result.diffSegments.contains { segment in
                if case .extra = segment { return true }
                return false
            }
            #expect(hasMissing)
            #expect(hasExtra)
        }
    }

    // MARK: - LCS Tests

    @Suite("LongestCommonSubsequence")
    struct LCSTests {

        @Test("LCS of identical strings returns all characters")
        func identicalStrings() {
            let expected = Array("ねこ")
            let recognized = Array("ねこ")
            let lcs = PronunciationScorer.longestCommonSubsequence(expected, recognized)
            #expect(lcs.count == 2)
        }

        @Test("LCS of completely different strings returns empty")
        func completelyDifferent() {
            let expected = Array("あい")
            let recognized = Array("かき")
            let lcs = PronunciationScorer.longestCommonSubsequence(expected, recognized)
            #expect(lcs.isEmpty)
        }

        @Test("LCS with partial overlap returns correct length")
        func partialOverlap() {
            let expected = Array("あいう")
            let recognized = Array("あえう")
            let lcs = PronunciationScorer.longestCommonSubsequence(expected, recognized)
            #expect(lcs.count == 2) // あ and う
        }
    }
}
