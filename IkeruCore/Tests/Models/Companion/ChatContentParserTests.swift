import Testing
@testable import IkeruCore

// MARK: - ChatContentParser Tests

@Suite("ChatContentParser")
struct ChatContentParserTests {

    // MARK: - Plain Text

    @Test("Parses plain text without tags")
    func parsesPlainText() {
        let blocks = ChatContentParser.parse("Hello, how are you?")
        #expect(blocks.count == 1)

        if case .text(let value) = blocks.first {
            #expect(value == "Hello, how are you?")
        } else {
            #expect(Bool(false), "Expected .text block")
        }
    }

    @Test("Parses empty string")
    func parsesEmptyString() {
        let blocks = ChatContentParser.parse("")
        #expect(blocks.isEmpty)
    }

    // MARK: - Kanji Tag

    @Test("Parses single kanji tag")
    func parsesSingleKanji() {
        let blocks = ChatContentParser.parse("[KANJI:食]")
        #expect(blocks.count == 1)

        if case .kanji(let character) = blocks.first {
            #expect(character == "食")
        } else {
            #expect(Bool(false), "Expected .kanji block")
        }
    }

    @Test("Parses kanji tag with surrounding text")
    func parsesKanjiWithText() {
        let blocks = ChatContentParser.parse("Look at this: [KANJI:日] it means sun!")
        #expect(blocks.count == 3)

        if case .text(let value) = blocks[0] {
            #expect(value == "Look at this: ")
        } else {
            #expect(Bool(false), "Expected leading .text block")
        }

        if case .kanji(let character) = blocks[1] {
            #expect(character == "日")
        } else {
            #expect(Bool(false), "Expected .kanji block")
        }

        if case .text(let value) = blocks[2] {
            #expect(value == " it means sun!")
        } else {
            #expect(Bool(false), "Expected trailing .text block")
        }
    }

    // MARK: - Mnemonic Tag

    @Test("Parses mnemonic tag")
    func parsesMnemonic() {
        let blocks = ChatContentParser.parse("[MNEMONIC:食|A person eating from a tray]")
        #expect(blocks.count == 1)

        if case .mnemonic(let character, let hint) = blocks.first {
            #expect(character == "食")
            #expect(hint == "A person eating from a tray")
        } else {
            #expect(Bool(false), "Expected .mnemonic block")
        }
    }

    // MARK: - Quiz Tag

    @Test("Parses quiz tag with three options")
    func parsesQuiz() {
        let blocks = ChatContentParser.parse("[QUIZ:食|to eat|to drink|to read]")
        #expect(blocks.count == 1)

        if case .quiz(let character, let correct, let options) = blocks.first {
            #expect(character == "食")
            #expect(correct == "to eat")
            #expect(options.count == 3)
            #expect(options.contains("to eat"))
            #expect(options.contains("to drink"))
            #expect(options.contains("to read"))
        } else {
            #expect(Bool(false), "Expected .quiz block")
        }
    }

    // MARK: - Mixed Content

    @Test("Parses mixed content with multiple tags")
    func parsesMixedContent() {
        let input = "Here is [KANJI:食] and a trick: [MNEMONIC:食|Person eating]"
        let blocks = ChatContentParser.parse(input)
        #expect(blocks.count == 4)

        if case .text = blocks[0] {} else {
            #expect(Bool(false), "Expected .text at index 0")
        }
        if case .kanji = blocks[1] {} else {
            #expect(Bool(false), "Expected .kanji at index 1")
        }
        if case .text = blocks[2] {} else {
            #expect(Bool(false), "Expected .text at index 2")
        }
        if case .mnemonic = blocks[3] {} else {
            #expect(Bool(false), "Expected .mnemonic at index 3")
        }
    }

    // MARK: - Malformed Tags

    @Test("Treats unknown tag type as plain text")
    func unknownTagAsText() {
        let blocks = ChatContentParser.parse("[UNKNOWN:value]")
        #expect(blocks.count == 1)

        if case .text(let value) = blocks.first {
            #expect(value == "[UNKNOWN:value]")
        } else {
            #expect(Bool(false), "Expected .text block for unknown tag")
        }
    }

    @Test("Treats unclosed bracket as plain text")
    func unclosedBracketAsText() {
        let blocks = ChatContentParser.parse("Hello [KANJI:食")
        #expect(blocks.count == 2)

        if case .text(let value) = blocks[1] {
            #expect(value == "[KANJI:食")
        } else {
            #expect(Bool(false), "Expected .text block for unclosed bracket")
        }
    }

    @Test("Handles mnemonic with missing pipe as nil")
    func mnemonicMissingPipe() {
        let blocks = ChatContentParser.parse("[MNEMONIC:食]")
        #expect(blocks.count == 1)

        // Should fall through as text since no pipe separator
        if case .text = blocks.first {} else {
            #expect(Bool(false), "Expected .text block for malformed mnemonic")
        }
    }
}
