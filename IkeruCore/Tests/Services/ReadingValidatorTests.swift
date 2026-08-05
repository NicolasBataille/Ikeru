import Testing
import Foundation
@testable import IkeruCore

// MARK: - ReadingValidator Tests

@Suite("ReadingValidator")
struct ReadingValidatorTests {

    @Test("Word not in bundle leaves hint unchanged")
    func wordNotInBundleUnchanged() {
        let hint = VocabularyHint(word: "散歩", reading: "さんぽ", meaning: "walk")

        let result = ReadingValidator.reconcile(hint, against: [:])

        #expect(result.corrected == false)
        #expect(result.hint == hint)
    }

    @Test("Matching AI and bundle readings leave hint unchanged")
    func matchingReadingUnchanged() {
        let hint = VocabularyHint(word: "日本", reading: "にほん", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": "にほん"])

        #expect(result.corrected == false)
        #expect(result.hint == hint)
    }

    @Test("Differing AI reading is corrected to the bundle reading")
    func differingReadingCorrected() {
        let hint = VocabularyHint(word: "日本", reading: "にっぽん", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": "にほん"])

        #expect(result.corrected == true)
        #expect(result.hint.reading == "にほん")
    }

    @Test("Empty AI reading is filled from the bundle (enrichment)")
    func emptyAIReadingFilled() {
        let hint = VocabularyHint(word: "日本", reading: "", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": "にほん"])

        #expect(result.corrected == true)
        #expect(result.hint.reading == "にほん")
    }

    @Test("Empty bundle reading is treated as not-usable and leaves hint unchanged")
    func emptyBundleReadingUnchanged() {
        let hint = VocabularyHint(word: "日本", reading: "にっぽん", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": ""])

        #expect(result.corrected == false)
        #expect(result.hint == hint)
    }

    @Test("Identifier and meaning are preserved on correction")
    func identifierAndMeaningPreservedOnCorrection() {
        let hint = VocabularyHint(word: "日本", reading: "にっぽん", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": "にほん"])

        #expect(result.hint.id == hint.id)
        #expect(result.hint.word == hint.word)
        #expect(result.hint.meaning == hint.meaning)
    }

    @Test("Whitespace-only difference is treated as a match")
    func whitespaceOnlyDifferenceIsMatch() {
        let hint = VocabularyHint(word: "日本", reading: " にほん ", meaning: "Japan")

        let result = ReadingValidator.reconcile(hint, against: ["日本": "にほん"])

        #expect(result.corrected == false)
        #expect(result.hint == hint)
    }
}
