import Testing
import Foundation
@testable import IkeruCore

// MARK: - JLPTLevel Tests

@Suite("JLPTLevel Enum")
struct JLPTLevelTests {

    @Test("All JLPT levels have correct raw values")
    func rawValues() {
        #expect(JLPTLevel.n5.rawValue == "n5")
        #expect(JLPTLevel.n4.rawValue == "n4")
        #expect(JLPTLevel.n3.rawValue == "n3")
        #expect(JLPTLevel.n2.rawValue == "n2")
        #expect(JLPTLevel.n1.rawValue == "n1")
    }

    @Test("JLPTLevel has exactly 5 cases")
    func caseCount() {
        #expect(JLPTLevel.allCases.count == 5)
    }

    @Test("JLPTLevel is Comparable with correct ordering (n5 < n4 < n3 < n2 < n1)")
    func comparableOrdering() {
        #expect(JLPTLevel.n5 < JLPTLevel.n4)
        #expect(JLPTLevel.n4 < JLPTLevel.n3)
        #expect(JLPTLevel.n3 < JLPTLevel.n2)
        #expect(JLPTLevel.n2 < JLPTLevel.n1)
    }

    @Test("JLPTLevel n5 is the lowest level")
    func lowestLevel() {
        let sorted = JLPTLevel.allCases.sorted()
        #expect(sorted.first == .n5)
        #expect(sorted.last == .n1)
    }

    @Test("JLPTLevel is Codable - encode and decode roundtrip", arguments: JLPTLevel.allCases)
    func codableRoundtrip(level: JLPTLevel) throws {
        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(JLPTLevel.self, from: data)
        #expect(decoded == level)
    }

    @Test("JLPTLevel initializes from raw value")
    func initFromRawValue() {
        #expect(JLPTLevel(rawValue: "n5") == .n5)
        #expect(JLPTLevel(rawValue: "n1") == .n1)
        #expect(JLPTLevel(rawValue: "invalid") == nil)
    }

    @Test("JLPTLevel displayName returns human-readable format")
    func displayName() {
        #expect(JLPTLevel.n5.displayName == "N5")
        #expect(JLPTLevel.n4.displayName == "N4")
        #expect(JLPTLevel.n3.displayName == "N3")
        #expect(JLPTLevel.n2.displayName == "N2")
        #expect(JLPTLevel.n1.displayName == "N1")
    }
}

// MARK: - Kanji Tests

@Suite("Kanji Struct")
struct KanjiTests {

    @Test("Kanji initializes with all fields")
    func fullInit() {
        let kanji = Kanji(
            character: "日",
            radicals: ["一", "口"],
            onReadings: ["ニチ", "ジツ"],
            kunReadings: ["ひ", "か"],
            meanings: ["day", "sun"],
            jlptLevel: .n5,
            strokeCount: 4,
            strokeOrderSVGRef: "<svg>...</svg>"
        )
        #expect(kanji.character == "日")
        #expect(kanji.radicals == ["一", "口"])
        #expect(kanji.onReadings == ["ニチ", "ジツ"])
        #expect(kanji.kunReadings == ["ひ", "か"])
        #expect(kanji.meanings == ["day", "sun"])
        #expect(kanji.jlptLevel == .n5)
        #expect(kanji.strokeCount == 4)
        #expect(kanji.strokeOrderSVGRef == "<svg>...</svg>")
    }

    @Test("Kanji id is the character itself")
    func identifiable() {
        let kanji = Kanji(
            character: "月",
            radicals: [],
            onReadings: ["ゲツ"],
            kunReadings: ["つき"],
            meanings: ["moon"],
            jlptLevel: .n5,
            strokeCount: 4,
            strokeOrderSVGRef: nil
        )
        #expect(kanji.id == "月")
    }

    @Test("Kanji is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = Kanji(
            character: "火",
            radicals: ["人"],
            onReadings: ["カ"],
            kunReadings: ["ひ"],
            meanings: ["fire"],
            jlptLevel: .n5,
            strokeCount: 4,
            strokeOrderSVGRef: "<svg/>"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Kanji.self, from: data)
        #expect(decoded == original)
    }

    @Test("Kanji with nil strokeOrderSVGRef roundtrips correctly")
    func codableNilSVG() throws {
        let original = Kanji(
            character: "水",
            radicals: [],
            onReadings: ["スイ"],
            kunReadings: ["みず"],
            meanings: ["water"],
            jlptLevel: .n5,
            strokeCount: 4,
            strokeOrderSVGRef: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Kanji.self, from: data)
        #expect(decoded.strokeOrderSVGRef == nil)
    }
}

// MARK: - Radical Tests

@Suite("Radical Struct")
struct RadicalTests {

    @Test("Radical initializes with all fields")
    func fullInit() {
        let radical = Radical(
            character: "一",
            meaning: "one",
            strokeCount: 1
        )
        #expect(radical.character == "一")
        #expect(radical.meaning == "one")
        #expect(radical.strokeCount == 1)
    }

    @Test("Radical id is the character itself")
    func identifiable() {
        let radical = Radical(character: "口", meaning: "mouth", strokeCount: 3)
        #expect(radical.id == "口")
    }

    @Test("Radical is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = Radical(character: "口", meaning: "mouth", strokeCount: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Radical.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - KanjiRadicalEdge Tests

@Suite("KanjiRadicalEdge Struct")
struct KanjiRadicalEdgeTests {

    @Test("KanjiRadicalEdge initializes correctly")
    func fullInit() {
        let edge = KanjiRadicalEdge(radicalCharacter: "一", kanjiCharacter: "日")
        #expect(edge.radicalCharacter == "一")
        #expect(edge.kanjiCharacter == "日")
    }

    @Test("KanjiRadicalEdge is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = KanjiRadicalEdge(radicalCharacter: "口", kanjiCharacter: "日")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KanjiRadicalEdge.self, from: data)
        #expect(decoded == original)
    }

    @Test("KanjiRadicalEdge id combines radical and kanji characters")
    func identifiable() {
        let edge = KanjiRadicalEdge(radicalCharacter: "一", kanjiCharacter: "日")
        #expect(edge.id == "一→日")
    }
}

// MARK: - Vocabulary Tests

@Suite("Vocabulary Struct")
struct VocabularyTests {

    @Test("Vocabulary initializes with all fields")
    func fullInit() {
        let vocab = Vocabulary(
            id: 1,
            word: "日本",
            reading: "にほん",
            meaning: "Japan",
            kanjiCharacter: "日",
            jlptLevel: .n5,
            exampleSentences: ["日本は美しい国です。"]
        )
        #expect(vocab.id == 1)
        #expect(vocab.word == "日本")
        #expect(vocab.reading == "にほん")
        #expect(vocab.meaning == "Japan")
        #expect(vocab.kanjiCharacter == "日")
        #expect(vocab.jlptLevel == .n5)
        #expect(vocab.exampleSentences == ["日本は美しい国です。"])
    }

    @Test("Vocabulary kanjiCharacter can be nil")
    func nilKanjiCharacter() {
        let vocab = Vocabulary(
            id: 2,
            word: "おはよう",
            reading: "おはよう",
            meaning: "good morning",
            kanjiCharacter: nil,
            jlptLevel: .n5,
            exampleSentences: []
        )
        #expect(vocab.kanjiCharacter == nil)
    }

    @Test("Vocabulary is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = Vocabulary(
            id: 1,
            word: "学校",
            reading: "がっこう",
            meaning: "school",
            kanjiCharacter: "学",
            jlptLevel: .n5,
            exampleSentences: ["学校に行きます。"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Vocabulary.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - GrammarPoint Tests

@Suite("GrammarPoint Struct")
struct GrammarPointTests {

    @Test("GrammarPoint initializes with all fields")
    func fullInit() {
        let grammar = GrammarPoint(
            id: 1,
            jlptLevel: .n5,
            title: "は (Topic Marker)",
            explanation: "Marks the topic of the sentence",
            examples: ["私は学生です。", "これは本です。"]
        )
        #expect(grammar.id == 1)
        #expect(grammar.jlptLevel == .n5)
        #expect(grammar.title == "は (Topic Marker)")
        #expect(grammar.explanation == "Marks the topic of the sentence")
        #expect(grammar.examples == ["私は学生です。", "これは本です。"])
    }

    @Test("GrammarPoint is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = GrammarPoint(
            id: 1,
            jlptLevel: .n5,
            title: "です",
            explanation: "Copula",
            examples: ["学生です"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GrammarPoint.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - ListeningPassage Tests

@Suite("ListeningPassage Struct")
struct ListeningPassageTests {

    @Test("ListeningPassage initializes with all fields")
    func fullInit() {
        let passage = ListeningPassage(
            id: 1,
            jlptLevel: .n5,
            transcript: "今日はいい天気ですね。",
            audioRef: "n5_listening_001.m4a",
            difficulty: 1
        )
        #expect(passage.id == 1)
        #expect(passage.jlptLevel == .n5)
        #expect(passage.transcript == "今日はいい天気ですね。")
        #expect(passage.audioRef == "n5_listening_001.m4a")
        #expect(passage.difficulty == 1)
    }

    @Test("ListeningPassage audioRef can be nil")
    func nilAudioRef() {
        let passage = ListeningPassage(
            id: 2,
            jlptLevel: .n5,
            transcript: "すみません。",
            audioRef: nil,
            difficulty: 1
        )
        #expect(passage.audioRef == nil)
    }

    @Test("ListeningPassage is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = ListeningPassage(
            id: 1,
            jlptLevel: .n5,
            transcript: "おはようございます。",
            audioRef: "audio.m4a",
            difficulty: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ListeningPassage.self, from: data)
        #expect(decoded == original)
    }
}
