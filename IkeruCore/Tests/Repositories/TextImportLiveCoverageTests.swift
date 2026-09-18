import Testing
import Foundation
@testable import IkeruCore

@Suite("Journal de lecture — la couverture bouge avec ce que l'apprenant apprend (OBS2-062)")
struct TextImportLiveCoverageTests {

    private func noun(_ id: Int, _ form: String) -> AnalyzedToken {
        AnalyzedToken(
            id: id, surface: form, isWord: true, dictionaryForm: form,
            entry: DictionaryEntry(id: id, reading: form, partsOfSpeech: ["n"],
                                   glossFR: nil, glossEN: form, isCommon: true)
        )
    }

    private func importOf(_ content: String, storedCoverage: Double?) -> TextImportDTO {
        TextImportDTO(id: UUID(), title: content, content: content, source: .paste,
                      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                      coverage: storedCoverage, entryIDs: [])
    }

    /// Un faux analyseur : chaque texte est deux noms, « 猫 » et « 犬 ».
    private func analyze(_ text: String) async -> AnalyzedText {
        AnalyzedText(source: text, tokens: [noun(1, "猫"), noun(2, "犬")])
    }

    @Test("La couverture stockée à l'import est remplacée par celle d'aujourd'hui")
    func storedCoverageIsReplacedByTodays() async {
        let item = importOf("猫と犬", storedCoverage: 0)
        let before = await TextImportLiveCoverage.refresh([item], known: ["猫"], analyze: analyze)
        #expect(before.first?.coverage == 0.5, "un mot sur deux connu aujourd'hui, quoi que dise l'instantané")
        let after = await TextImportLiveCoverage.refresh([item], known: ["猫", "犬"], analyze: analyze)
        #expect(after.first?.coverage == 1.0, "le second mot appris, la couverture suit")
    }

    @Test("Un texte sans mot apprenable garde une couverture nil, pas zéro")
    func noLearnableWordMeansNil() async {
        let item = importOf("…", storedCoverage: 0.4)
        let refreshed = await TextImportLiveCoverage.refresh([item], known: ["猫"]) { text in
            AnalyzedText(source: text, tokens: [])
        }
        #expect(refreshed.first?.coverage == nil)
    }

    @Test("L'ordre et le reste de l'import sont gardés")
    func orderAndFieldsSurvive() async {
        let first = importOf("a", storedCoverage: nil)
        let second = importOf("b", storedCoverage: 0.1)
        let refreshed = await TextImportLiveCoverage.refresh([first, second], known: [], analyze: analyze)
        #expect(refreshed.map(\.id) == [first.id, second.id])
        #expect(refreshed.map(\.coverage) == [0.0, 0.0])
        #expect(refreshed[1].title == "b" && refreshed[1].createdAt == second.createdAt)
    }
}
