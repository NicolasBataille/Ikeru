import Testing
import Foundation
@testable import IkeruCore

// MARK: - ConversationMessage Tests

@Suite("ConversationMessage")
struct ConversationMessageTests {

    @Test("Creates user message with defaults")
    func userMessageDefaults() {
        let message = ConversationMessage(role: .user, content: "Hello")

        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(message.corrections.isEmpty)
        #expect(message.vocabularyHints.isEmpty)
    }

    @Test("Creates assistant message with corrections and hints")
    func assistantMessageWithExtras() {
        let correction = Correction(
            original: "食べます",
            corrected: "食べました",
            explanation: "Past tense needed"
        )
        let hint = VocabularyHint(word: "散歩", reading: "さんぽ", meaning: "walk")

        let message = ConversationMessage(
            role: .assistant,
            content: "いいですね！",
            corrections: [correction],
            vocabularyHints: [hint]
        )

        #expect(message.role == .assistant)
        #expect(message.corrections.count == 1)
        #expect(message.corrections[0].original == "食べます")
        #expect(message.corrections[0].corrected == "食べました")
        #expect(message.vocabularyHints.count == 1)
        #expect(message.vocabularyHints[0].word == "散歩")
    }

    @Test("Messages have unique IDs")
    func uniqueIds() {
        let message1 = ConversationMessage(role: .user, content: "Hello")
        let message2 = ConversationMessage(role: .user, content: "Hello")

        #expect(message1.id != message2.id)
    }

    @Test("Messages are Equatable")
    func equatable() {
        let id = UUID()
        let date = Date()
        let message1 = ConversationMessage(id: id, role: .user, content: "Hi", timestamp: date)
        let message2 = ConversationMessage(id: id, role: .user, content: "Hi", timestamp: date)

        #expect(message1 == message2)
    }
}

// MARK: - JLPTLevel Tests

@Suite("JLPTLevel Conversation Extensions")
struct JLPTLevelConversationTests {

    @Test("All levels have rawValues", arguments: JLPTLevel.allCases)
    func rawValues(level: JLPTLevel) {
        #expect(!level.rawValue.isEmpty)
        #expect(!level.complexityDescription.isEmpty)
    }

    @Test("N5 is beginner")
    func n5Description() {
        #expect(JLPTLevel.n5.complexityDescription.contains("simple"))
    }

    @Test("N1 is advanced")
    func n1Description() {
        #expect(JLPTLevel.n1.complexityDescription.contains("native"))
    }
}

// MARK: - MessageRole Tests

@Suite("MessageRole")
struct MessageRoleTests {

    @Test("Roles encode to expected strings", arguments: [
        (MessageRole.user, "user"),
        (MessageRole.assistant, "assistant"),
        (MessageRole.system, "system")
    ])
    func rawValues(role: MessageRole, expected: String) {
        #expect(role.rawValue == expected)
    }
}
