import Testing
import Foundation
@testable import IkeruCore

@Suite("Gloses — résolues dans la langue de l'interface, jamais figées à la capture (OBS2-041)")
struct GlossResolverTests {

    private func dictionaryEntry(_ id: Int, reading: String, fr: String?, en: String) -> DictionaryEntry {
        DictionaryEntry(id: id, reading: reading, partsOfSpeech: ["n"], glossFR: fr, glossEN: en, isCommon: true)
    }

    private func entry(_ word: String, reading: String, meaning: String) -> VocabularyEntryDTO {
        VocabularyEntryDTO(
            id: UUID(), word: word, reading: reading, meaning: meaning, jlptLevel: nil,
            fsrsState: FSRSState(), easeFactor: 2.5, interval: 0, dueDate: Date(),
            lapseCount: 0, isInDictionary: true, createdAt: Date(), encounterCount: 0
        )
    }

    private var bike: DictionaryEntry { dictionaryEntry(1, reading: "じてんしゃ", fr: "bicyclette; vélo", en: "bicycle") }
    private var rain: DictionaryEntry { dictionaryEntry(2, reading: "あめ", fr: nil, en: "rain") }

    private func resolver() -> GlossResolver {
        let bike = self.bike, rain = self.rain
        return GlossResolver { forms in
            var table: [String: [DictionaryEntry]] = [:]
            if forms.contains("自転車") { table["自転車"] = [bike] }
            if forms.contains("雨") { table["雨"] = [rain] }
            return table
        }
    }

    @Test("Une glose capturée en français se lit en anglais quand l'interface est en anglais, et revient")
    func capturedGlossFollowsTheInterfaceLanguage() async {
        let stored = entry("自転車", reading: "じてんしゃ", meaning: "bicyclette; vélo")
        let english = await resolver().resolve(stored, into: .english)
        #expect(english.meaning == "bicycle")
        let french = await resolver().resolve(english, into: .french)
        #expect(french.meaning == "bicyclette; vélo", "le chemin inverse rend la française")
    }

    @Test("Le repli « EN — » gravé à l'import n'est plus définitif : en anglais il tombe, en français il reste")
    func englishFallbackLabelIsNotForever() async {
        let stored = entry("雨", reading: "あめ", meaning: "EN — rain")
        #expect((await resolver().resolve(stored, into: .english)).meaning == "rain")
        #expect((await resolver().resolve(stored, into: .french)).meaning == "EN — rain", "pas de française : l'étiquette dit pourquoi")
    }

    @Test("Un sens écrit par l'apprenant n'est jamais réécrit")
    func learnerAuthoredMeaningIsUntouched() async {
        let authored = entry("自転車", reading: "じてんしゃ", meaning: "le vélo de mon grand-père")
        #expect((await resolver().resolve(authored, into: .english)).meaning == "le vélo de mon grand-père")
    }

    @Test("Sans entrée de dictionnaire, le sens stocké reste")
    func noDictionaryHitKeepsStoredMeaning() async {
        let unknown = entry("〇〇", reading: "まるまる", meaning: "quelque chose")
        #expect((await resolver().resolve(unknown, into: .english)).meaning == "quelque chose")
    }

    @Test("L'ordre est gardé et les autres champs survivent")
    func orderAndFieldsSurvive() async {
        let first = entry("雨", reading: "あめ", meaning: "EN — rain")
        let second = entry("自転車", reading: "じてんしゃ", meaning: "bicyclette; vélo")
        let out = await resolver().resolve([first, second], into: .english)
        #expect(out.map(\.id) == [first.id, second.id])
        #expect(out.map(\.meaning) == ["rain", "bicycle"])
        #expect(out[1].reading == "じてんしゃ" && out[1].createdAt == second.createdAt)
    }

    @Test("La glose à stocker suit la langue : française avec repli étiqueté, ou anglaise nue")
    func captureGlossPerLanguage() {
        #expect(GlossResolver.gloss(for: bike, in: .french) == "bicyclette; vélo")
        #expect(GlossResolver.gloss(for: rain, in: .french) == "EN — rain")
        #expect(GlossResolver.gloss(for: bike, in: .english) == "bicycle")
        #expect(GlossResolver.gloss(for: rain, in: .english) == "rain")
    }

    @Test("GlossLanguage ne distingue que le français, comme AppLocale")
    func languageMirrorsAppLocale() {
        #expect(GlossLanguage(locale: Locale(identifier: "fr")) == .french)
        #expect(GlossLanguage(locale: Locale(identifier: "fr_CA")) == .french)
        #expect(GlossLanguage(locale: Locale(identifier: "en")) == .english)
        #expect(GlossLanguage(locale: Locale(identifier: "ja")) == .english)
    }
}
