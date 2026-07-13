import Foundation

// MARK: - Shared OpenAI-Compatible Chat Codec
//
// OpenRouter, Groq, Cerebras, and GitHub Models all expose an OpenAI-compatible
// chat completion endpoint. This file centralises the request/response shape so
// the four providers stay DRY without forcing inheritance.

/// Builds the JSON body for an OpenAI-compatible chat completion request.
public enum OpenAIChatCodec {

    /// Encodes a system prompt plus an ordered multi-turn conversation into the
    /// standard chat-completion JSON body. The system prompt leads, followed by
    /// each conversation turn in order with its role mapped to OpenAI's
    /// `"user"` / `"assistant"` vocabulary.
    public static func encodeRequest(
        model: String,
        systemPrompt: String,
        messages: [AIMessage],
        maxTokens: Int = 1024,
        temperature: Double = 0.7
    ) throws -> Data {
        var wire = [OpenAIChatMessage(role: "system", content: systemPrompt)]
        wire.append(contentsOf: messages.map { message in
            OpenAIChatMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.text
            )
        })

        let body = OpenAIChatRequest(
            model: model,
            messages: wire,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try JSONEncoder().encode(body)
    }

    /// Convenience for single-turn callers: a system prompt + one user message.
    public static func encodeRequest(
        model: String,
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 1024,
        temperature: Double = 0.7
    ) throws -> Data {
        try encodeRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: [AIMessage(role: .user, text: userMessage)],
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    /// Decodes the OpenAI-compatible chat completion response and returns the
    /// assistant content of the first choice. Throws `AIError.invalidResponse`
    /// when the payload is missing or malformed.
    public static func decodeResponse(_ data: Data) throws -> String {
        let decoded: OpenAIChatResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }

        guard let content = decoded.choices?.first?.message?.content,
              !content.isEmpty else {
            throw AIError.invalidResponse
        }
        return content
    }
}

// MARK: - Wire Types

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChatChoice]?
}

private struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatMessage?
}
