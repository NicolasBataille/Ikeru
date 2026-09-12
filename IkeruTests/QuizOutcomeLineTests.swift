import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("QuizOutcomeLine")
struct QuizOutcomeLineTests {

    /// OBS2-015 : le nom de la note suit la langue de l'INTERFACE. Les deux
    /// langues sont demandées dans le même process, donc quelle que soit la
    /// langue du simulateur l'une des deux prouve que c'est bien `locale`
    /// qui décide, pas `Bundle.main`.
    @Test
    func gradeNameFollowsTheInterfaceLocaleNotTheDevice() {
        let french = Locale(identifier: "fr")
        let english = Locale(identifier: "en")
        #expect(QuizOutcomeLine.gradeName(.hard, locale: french) == "Difficile")
        #expect(QuizOutcomeLine.gradeName(.hard, locale: english) == "Hard")
        #expect(QuizOutcomeLine.gradeName(.again, locale: french) == "Encore")
        #expect(QuizOutcomeLine.gradeName(.again, locale: english) == "Again")
    }
}
