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

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

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

    private func buildRequest(prompt: AIPrompt, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: Self.baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = timeoutSeconds

        let body = GeminiRequestBody(
            systemInstruction: GeminiContent(
                parts: [GeminiPart(text: prompt.systemPrompt)]
            ),
            contents: [
                GeminiContent(
                    parts: [GeminiPart(text: prompt.userMessage)]
                )
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
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
