import Foundation
import os

// MARK: - GeminiProvider

/// AI provider for Google Gemini free tier via REST API.
/// API key is retrieved from iOS Keychain at runtime -- never hardcoded.
public final class GeminiProvider: AIProvider, @unchecked Sendable {

    public let name = "Gemini"
    public let tier = AITier.gemini

    private let keychainStore: any KeychainStore
    private let networkChecker: any NetworkChecker
    private let urlSession: any URLSessionProvider
    private let timeoutSeconds: Double

    /// Model used for conversation. `gemini-2.5-flash` is Google's current
    /// default free-tier flash model; older IDs like `gemini-2.0-flash` can have
    /// a free-tier quota of 0 on some projects. Bump this when the model is
    /// retired (see ListModels: generativelanguage.googleapis.com/v1beta/models).
    private static let model = "gemini-2.5-flash"
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    public init(
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 10
    ) {
        self.keychainStore = keychainStore
        self.networkChecker = networkChecker
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
    }

    public var isAvailable: Bool {
        get async {
            guard networkChecker.isOnline else { return false }
            do {
                let key = try keychainStore.load(key: KeychainKeys.geminiAPIKey)
                return key != nil && !(key?.isEmpty ?? true)
            } catch {
                return false
            }
        }
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let start = ContinuousClock.now

        // Retrieve API key
        guard let apiKey = try? keychainStore.load(key: KeychainKeys.geminiAPIKey),
              !apiKey.isEmpty else {
            throw AIError.keyNotFound(KeychainKeys.geminiAPIKey)
        }

        // Build request
        let request = try buildRequest(prompt: prompt, apiKey: apiKey)

        // Execute with timeout
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw AIError.timeout(.gemini)
        } catch {
            Logger.ai.error("Gemini network error: \(error.localizedDescription)")
            throw AIError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            Logger.ai.warning("Gemini rate limited")
            throw AIError.rateLimited(.gemini)
        }

        // A configured-but-rejected key surfaces as 401/403, or as 400 with an
        // API_KEY_INVALID body. Map these to `invalidKey` so the UI can tell the
        // user to fix their key instead of showing a generic failure.
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403
            || (httpResponse.statusCode == 400 && Self.bodyIndicatesInvalidKey(data)) {
            Logger.ai.error("Gemini rejected the API key (HTTP \(httpResponse.statusCode))")
            throw AIError.invalidKey(.gemini)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Logger.ai.error("Gemini HTTP error: \(httpResponse.statusCode)")
            throw AIError.invalidResponse
        }

        // Parse response
        let content = try parseResponse(data: data)

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        Logger.ai.info("Gemini generated response in \(latencyMs)ms")

        return AIResponse(
            content: content,
            tier: .gemini,
            latencyMs: latencyMs
        )
    }

    // MARK: - Private Helpers

    /// True when a 400 response body is Google's "API key not valid" error, so
    /// we can distinguish a bad key from a genuinely malformed request.
    private static func bodyIndicatesInvalidKey(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("API_KEY_INVALID") || text.contains("API key not valid")
    }

    private func buildRequest(prompt: AIPrompt, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: Self.baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = timeoutSeconds

        request.httpBody = try Self.encodeRequestBody(
            systemPrompt: prompt.systemPrompt,
            messages: prompt.messages
        )
        return request
    }

    /// Builds Gemini's `generateContent` JSON body from a system prompt and an
    /// ordered multi-turn conversation. The system prompt goes into
    /// `system_instruction`; every turn maps to a `contents` entry with Gemini's
    /// role vocabulary (`user`, and `model` for the assistant). Pure and
    /// `static` so the multi-turn shape can be unit-tested without the network.
    static func encodeRequestBody(systemPrompt: String, messages: [AIMessage]) throws -> Data {
        let body = GeminiRequestBody(
            systemInstruction: GeminiContent(
                role: nil,
                parts: [GeminiPart(text: systemPrompt)]
            ),
            contents: messages.map { message in
                GeminiContent(
                    role: message.role == .user ? "user" : "model",
                    parts: [GeminiPart(text: message.text)]
                )
            }
        )
        return try JSONEncoder().encode(body)
    }

    private func parseResponse(data: Data) throws -> String {
        let decoded: GeminiResponseBody
        do {
            decoded = try JSONDecoder().decode(GeminiResponseBody.self, from: data)
        } catch {
            Logger.ai.error("Gemini response parsing failed")
            throw AIError.invalidResponse
        }

        guard let text = decoded.candidates?.first?.content?.parts?.first?.text else {
            Logger.ai.error("Gemini response missing text content")
            throw AIError.invalidResponse
        }

        return text
    }
}

// MARK: - Gemini API Data Types

private struct GeminiRequestBody: Encodable {
    let systemInstruction: GeminiContent?
    let contents: [GeminiContent]

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
    }
}

private struct GeminiContent: Codable {
    /// Gemini's role for a turn: `user` or `model`. Omitted (nil) for
    /// `system_instruction`, which is roleless.
    let role: String?
    let parts: [GeminiPart]?
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiResponseBody: Decodable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent?
}
