import Testing
import Foundation
@testable import IkeruCore

@Suite("JLPTBackfillService")
struct JLPTBackfillServiceTests {

    // MARK: - Tagging

    @Test("Vocabulary card matching N5 seed gets tagged .n5")
    func n5VocabTagged() {
        let card = makeCard(front: "本", type: .vocabulary)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == .n5)
    }

    @Test("Common N5 vocab fronts are recognised", arguments: [
        "学校", "先生", "学生", "日本", "今日", "明日", "昨日"
    ])
    func commonN5Vocab(front: String) {
        let card = makeCard(front: front, type: .vocabulary)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == .n5, "expected '\(front)' to be tagged .n5")
    }

    @Test("Kanji-typed card matching N5 kanji seed gets tagged .n5")
    func n5KanjiTagged() {
        let card = makeCard(front: "日", type: .kanji)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == .n5)
    }

    // MARK: - Skips

    @Test("Kana-only vocab card stays nil (kana is pre-N5)")
    func kanaStaysNil() {
        let card = makeCard(front: "あ", type: .vocabulary)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == nil)
    }

    @Test("Card not in seed dictionary stays nil")
    func unknownStaysNil() {
        let card = makeCard(front: "made-up-string-not-in-seed", type: .vocabulary)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == nil)
    }

    @Test("Grammar cards are not tagged via this service")
    func grammarStaysNil() {
        let card = makeCard(front: "本", type: .grammar)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == nil)
    }

    @Test("Listening cards are not tagged via this service")
    func listeningStaysNil() {
        let card = makeCard(front: "本", type: .listening)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == nil)
    }

    // MARK: - Idempotency

    @Test("Already-tagged card is left untouched (no overwrite)")
    func alreadyTaggedNoOverwrite() {
        let card = makeCard(front: "本", type: .vocabulary, jlptLevel: .n3)
        let result = JLPTBackfillService.tag(cards: [card])
        #expect(result.first?.jlptLevel == .n3)
    }

    @Test("Mixed batch tags only matching, untagged cards")
    func mixedBatch() {
        let cards: [CardDTO] = [
            makeCard(front: "本", type: .vocabulary),               // tag .n5
            makeCard(front: "あ", type: .vocabulary),               // skip (kana)
            makeCard(front: "日", type: .kanji),                     // tag .n5
            makeCard(front: "本", type: .vocabulary, jlptLevel: .n2) // keep .n2
        ]
        let result = JLPTBackfillService.tag(cards: cards)
        #expect(result[0].jlptLevel == .n5)
        #expect(result[1].jlptLevel == nil)
        #expect(result[2].jlptLevel == .n5)
        #expect(result[3].jlptLevel == .n2)
    }

    @Test("Returns same count as input")
    func preservesCardCount() {
        let cards = (0..<10).map { i in makeCard(front: "x\(i)", type: .vocabulary) }
        let result = JLPTBackfillService.tag(cards: cards)
        #expect(result.count == cards.count)
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
