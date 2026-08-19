import Testing
import Foundation
@testable import IkeruCore

/// Le journal de lecture énonce des chiffres sur l'apprenant. Une moyenne
/// fausse n'est pas un bug d'affichage, c'est une phrase fausse sur quelqu'un.
@Suite("Journal de lecture — les chiffres")
struct TextImportSummaryTests {

    private func item(_ words: Int, _ coverage: Double?, daysAgo: Int = 0) -> TextImportDTO {
        TextImportDTO(id: UUID(), title: "t", content: "c", source: .paste,
                      createdAt: Date(timeIntervalSince1970: 1_787_000_000 - Double(daysAgo) * 86_400),
                      coverage: coverage,
                      entryIDs: (0..<words).map { _ in UUID() })
    }

    @Test("Rien lu, rien à dire")
    func emptyIsEmpty() {
        let summary = TextImportSummary.make(from: [])
        #expect(summary.isEmpty)
        #expect(summary.wordCount == 0)
        #expect(summary.averageCoverage == nil)
    }

    @Test("Textes et mots s'additionnent")
    func countsAddUp() {
        let summary = TextImportSummary.make(from: [item(3, 0.5), item(4, 0.9), item(0, 0.7)])
        #expect(summary.textCount == 3)
        #expect(summary.wordCount == 7)
    }

    /// Un texte sans couverture mesurable — photo illisible, texte sans mot de
    /// contenu — est EXCLU de la moyenne, pas compté zéro. Le compter zéro
    /// dirait à l'apprenant qu'il régresse.
    @Test("Un texte sans couverture ne tire pas la moyenne vers le bas")
    func unmeasuredTextsAreExcludedFromTheMean() {
        let withNil = TextImportSummary.make(from: [item(1, 0.8), item(1, nil), item(1, 0.6)])
        let withoutNil = TextImportSummary.make(from: [item(1, 0.8), item(1, 0.6)])
        #expect(withNil.averageCoverage == withoutNil.averageCoverage)
        #expect(withNil.averageCoverage.map { abs($0 - 0.7) < 0.0001 } == true)
        // Il compte quand même comme un TEXTE lu : on l'a lu, on ne l'a pas mesuré.
        #expect(withNil.textCount == 3)
    }

    @Test("Aucune couverture mesurable du tout rend nil, pas zéro")
    func noCoverageAtAllIsNil() {
        #expect(TextImportSummary.make(from: [item(2, nil), item(1, nil)]).averageCoverage == nil)
    }

    @Test("La fenêtre écarte ce qui la précède")
    func windowExcludesOlderTexts() {
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let summary = TextImportSummary.make(
            from: [item(2, 0.5), item(3, 0.5, daysAgo: 40)],
            since: now.addingTimeInterval(-10 * 86_400))
        #expect(summary.textCount == 1)
        #expect(summary.wordCount == 2)
    }

    @Test("Le début du mois est celui du calendrier de l'apprenant")
    func startOfMonthUsesTheLearnersCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let august19 = Date(timeIntervalSince1970: 1_787_000_000)
        let start = TextImportSummary.startOfMonth(containing: august19, calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour], from: start)
        #expect(parts.day == 1)
        #expect(parts.hour == 0)
    }
}
