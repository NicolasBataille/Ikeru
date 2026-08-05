import Testing
import Foundation
@testable import IkeruCore

/// Unit coverage for the `ContentRepository.Vocabulary` → `VocabularyItem`
/// field adapter that feeds the Shadowing / Listening drill pools (Phase 4.1
/// Tier-2, blueprint §1.4).
@Suite("VocabularyItemMapper")
struct VocabularyItemMapperTests {

    private func vocab(
        id: Int = 1,
        word: String = "猫",
        reading: String = "ねこ",
        meaning: String = "cat",
        kanjiCharacter: String? = "猫",
        jlptLevel: JLPTLevel = .n5,
        exampleSentences: [String] = ["猫が好きです。"]
    ) -> Vocabulary {
        Vocabulary(
            id: id,
            word: word,
            reading: reading,
            meaning: meaning,
            kanjiCharacter: kanjiCharacter,
            jlptLevel: jlptLevel,
            exampleSentences: exampleSentences
        )
    }

    @Test("Maps the learning payload field-for-field")
    func mapsFields() {
        let item = VocabularyItemMapper.map(vocab())
        // Vocabulary.word → VocabularyItem.japanese (the field rename the adapter exists for).
        #expect(item.japanese == "猫")
        #expect(item.reading == "ねこ")
        #expect(item.meaning == "cat")
        #expect(item.jlptLevel == .n5)
    }

    @Test("Preserves the JLPT level so pool filtering stays correct")
    func preservesLevel() {
        #expect(VocabularyItemMapper.map(vocab(jlptLevel: .n4)).jlptLevel == .n4)
        #expect(VocabularyItemMapper.map(vocab(jlptLevel: .n3)).jlptLevel == .n3)
    }

    @Test("Assigns a fresh non-nil UUID per item (content rows carry only Int ids)")
    func assignsFreshUUID() {
        let a = VocabularyItemMapper.map(vocab(id: 42))
        let b = VocabularyItemMapper.map(vocab(id: 42))
        // Same source row, but each mapped item gets its own UUID — the drills
        // never resolve items by id, so stability is neither provided nor needed.
        #expect(a.id != b.id)
    }

    @Test("Batch map preserves order and count")
    func batchPreservesOrder() {
        let source = [
            vocab(id: 1, word: "一", reading: "いち", meaning: "one"),
            vocab(id: 2, word: "二", reading: "に", meaning: "two"),
            vocab(id: 3, word: "三", reading: "さん", meaning: "three")
        ]
        let mapped = VocabularyItemMapper.map(source)
        #expect(mapped.count == 3)
        #expect(mapped.map(\.japanese) == ["一", "二", "三"])
        #expect(mapped.map(\.meaning) == ["one", "two", "three"])
    }

    @Test("Empty input maps to empty output")
    func emptyMapsEmpty() {
        #expect(VocabularyItemMapper.map([Vocabulary]()).isEmpty)
    }
}
