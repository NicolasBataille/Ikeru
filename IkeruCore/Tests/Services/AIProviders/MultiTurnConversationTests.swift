import Testing
import Foundation
@testable import IkeruCore

// MARK: - MultiTurnConversation
//
// Pins remediation 6.5: Sakura must send the REAL multi-turn conversation
// (system + ordered prior user/assistant turns + new user message) to the
// provider, not a single flattened blob. These tests assert the request-shaping
// pipeline end to end WITHOUT touching the network:
//   1. AIPrompt.messages exposes the ordered role-tagged array.
//   2. ConversationService.buildPrompt maps [ConversationMessage] history into
//      that array (deduping the trailing user turn the app already appended).
//   3. Each provider's pure request-body builder emits the ordered turns with
//      the provider's native role vocabulary.

@Suite("MultiTurnConversation")
@MainActor
struct MultiTurnConversationTests {

    // MARK: - AIPrompt.messages

    @Test("AIPrompt.messages appends the latest user turn after history, in order")
    func promptMessagesOrder() {
        let prompt = AIPrompt(
            systemPrompt: "sys",
            userMessage: "C",
            history: [
                AIMessage(role: .user, text: "A"),
                AIMessage(role: .assistant, text: "B"),
            ]
        )

        #expect(prompt.messages == [
            AIMessage(role: .user, text: "A"),
            AIMessage(role: .assistant, text: "B"),
            AIMessage(role: .user, text: "C"),
        ])
    }

    @Test("AIPrompt.messages is a single user turn for single-shot prompts")
    func promptMessagesSingleShot() {
        let prompt = AIPrompt(systemPrompt: "sys", userMessage: "hi")
        #expect(prompt.messages == [AIMessage(role: .user, text: "hi")])
    }

    @Test("flattenedConversation is raw userMessage when there is no history")
    func flattenedSingleShot() {
        let prompt = AIPrompt(systemPrompt: "sys", userMessage: "hi")
        #expect(prompt.flattenedConversation == "hi")
    }

    // MARK: - ConversationService.buildPrompt

    @Test("buildPrompt keeps prior turns as ordered roles and dedupes the trailing user turn")
    func buildPromptDedupesTrailingUser() {
        let service = ConversationService(aiRouter: AIRouterService(providers: [:]))

        // The app appends the new user bubble to `messages` before calling, so
        // history already ends with the latest user turn.
        let history = [
            ConversationMessage(role: .user, content: "Bonjour"),
            ConversationMessage(role: .assistant, content: "こんにちは"),
            ConversationMessage(role: .user, content: "元気です"),
        ]

        let prompt = service.buildPrompt(
            userMessage: "元気です",
            history: history,
            jlptLevel: .n5
        )

        // history carried = prior turns WITHOUT the duplicated latest user turn
        #expect(prompt.history == [
            AIMessage(role: .user, text: "Bonjour"),
            AIMessage(role: .assistant, text: "こんにちは"),
        ])
        // full conversation ends with the latest user message exactly once
        #expect(prompt.messages == [
            AIMessage(role: .user, text: "Bonjour"),
            AIMessage(role: .assistant, text: "こんにちは"),
            AIMessage(role: .user, text: "元気です"),
        ])
        #expect(prompt.complexity == .medium)
    }

    @Test("buildPrompt appends the user turn when history does not already contain it")
    func buildPromptAppendsWhenNotDuplicated() {
        let service = ConversationService(aiRouter: AIRouterService(providers: [:]))
        let history = [
            ConversationMessage(role: .user, content: "First"),
            ConversationMessage(role: .assistant, content: "Reply"),
        ]

        let prompt = service.buildPrompt(
            userMessage: "Second",
            history: history,
            jlptLevel: .n5
        )

        #expect(prompt.messages == [
            AIMessage(role: .user, text: "First"),
            AIMessage(role: .assistant, text: "Reply"),
            AIMessage(role: .user, text: "Second"),
        ])
    }

    @Test("buildPrompt caps carried history to the most recent turns")
    func buildPromptCapsHistory() {
        let service = ConversationService(aiRouter: AIRouterService(providers: [:]))
        // 30 alternating turns; last is a user turn equal to the new message.
        var history: [ConversationMessage] = []
        for index in 0..<29 {
            let role: MessageRole = index.isMultiple(of: 2) ? .user : .assistant
            history.append(ConversationMessage(role: role, content: "m\(index)"))
        }
        history.append(ConversationMessage(role: .user, content: "latest"))

        let prompt = service.buildPrompt(
            userMessage: "latest",
            history: history,
            jlptLevel: .n5
        )

        // 20-turn window, minus the deduped trailing user turn = 19 prior turns.
        #expect(prompt.history.count == 19)
        #expect(prompt.messages.last == AIMessage(role: .user, text: "latest"))
    }

    // MARK: - Gemini request body

    @Test("Gemini body maps the conversation to ordered contents with user/model roles")
    func geminiBodyMultiTurn() throws {
        let messages = [
            AIMessage(role: .user, text: "A"),
            AIMessage(role: .assistant, text: "B"),
            AIMessage(role: .user, text: "C"),
        ]
        let data = try GeminiProvider.encodeRequestBody(systemPrompt: "SYS", messages: messages)
        let decoded = try JSONDecoder().decode(DecodedGeminiBody.self, from: data)

        #expect(decoded.systemInstruction?.parts?.first?.text == "SYS")
        #expect(decoded.contents.map { $0.role } == ["user", "model", "user"])
        #expect(decoded.contents.map { $0.parts?.first?.text } == ["A", "B", "C"])
    }

    // MARK: - OpenAI-compatible request body

    @Test("OpenAI body leads with system then ordered user/assistant turns")
    func openAIBodyMultiTurn() throws {
        let messages = [
            AIMessage(role: .user, text: "A"),
            AIMessage(role: .assistant, text: "B"),
            AIMessage(role: .user, text: "C"),
        ]
        let data = try OpenAIChatCodec.encodeRequest(
            model: "m",
            systemPrompt: "SYS",
            messages: messages
        )
        let decoded = try JSONDecoder().decode(DecodedOpenAIBody.self, from: data)

        #expect(decoded.messages.map { $0.role } == ["system", "user", "assistant", "user"])
        #expect(decoded.messages.map { $0.content } == ["SYS", "A", "B", "C"])
    }
}

// MARK: - Decoding Helpers (mirror the providers' wire shapes)

private struct DecodedGeminiBody: Decodable {
    let systemInstruction: DecodedGeminiContent?
    let contents: [DecodedGeminiContent]

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
    }
}

private struct DecodedGeminiContent: Decodable {
    let role: String?
    let parts: [DecodedGeminiPart]?
}

private struct DecodedGeminiPart: Decodable {
    let text: String?
}

private struct DecodedOpenAIBody: Decodable {
    let messages: [DecodedOpenAIMessage]
}

private struct DecodedOpenAIMessage: Decodable {
    let role: String
    let content: String
}
