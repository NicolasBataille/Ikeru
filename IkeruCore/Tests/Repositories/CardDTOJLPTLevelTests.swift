import Testing
import Foundation
@testable import IkeruCore

@Suite("CardDTO.jlptLevel")
struct CardDTOJLPTLevelTests {

    @Test("Defaults to nil when unspecified")
    func nilDefault() {
        let card = makeCard(front: "あ", type: .vocabulary)
        #expect(card.jlptLevel == nil)
    }

    @Test("Stores tagged level")
    func tagged() {
        let card = makeCard(front: "本", type: .vocabulary, jlptLevel: .n5)
        #expect(card.jlptLevel == .n5)
    }

    @Test("Preserves higher levels")
    func higherLevel() {
        let card = makeCard(front: "概念", type: .vocabulary, jlptLevel: .n2)
        #expect(card.jlptLevel == .n2)
    }

    // MARK: - Fixture

    private func makeCard(
        front: String,
        type: CardType,
        jlptLevel: JLPTLevel? = nil
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "",
            type: type,
            fsrsState: FSRSState(),
            easeFactor: 2.5,
            interval: 0,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false,
            jlptLevel: jlptLevel
        )
    }
}
