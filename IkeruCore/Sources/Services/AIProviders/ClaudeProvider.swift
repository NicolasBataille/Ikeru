import Foundation
import os

// MARK: - ClaudeProvider

/// AI provider for Anthropic Claude via REST API.
/// Session token is retrieved from iOS Keychain at runtime -- never hardcoded.
public final class ClaudeProvider: AIProvider, @unchecked Sendable {

    public let name = "Claude"
    public let tier = AITier.claude

    private let keychainStore: any KeychainStore
    private let networkChecker: any NetworkChecker
    private let urlSession: any URLSessionProvider
    private let timeoutSeconds: Double
    private let model: String

    private static let baseURL = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"

    public init(
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 15,
        model: String = "claude-sonnet-4-20250514"
    ) {
        self.keychainStore = keychainStore
        self.networkChecker = networkChecker
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
        self.model = model
    }

    public var isAvailable: Bool {
        get async {
            guard networkChecker.isOnline else { return false }
            do {
                let token = try keychainStore.load(key: KeychainKeys.claudeSessionToken)
                return token != nil && !(token?.isEmpty ?? true)
            } catch {
                return false
            }
        }
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let start = ContinuousClock.now

        // Retrieve session token
        guard let token = try? keychainStore.load(key: KeychainKeys.claudeSessionToken),
              !token.isEmpty else {
            throw AIError.keyNotFound(KeychainKeys.claudeSessionToken)
        }

        // Build request
        let request = try buildRequest(prompt: prompt, token: token)

        // Execute
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw AIError.timeout(.claude)
        } catch {
            Logger.ai.error("Claude network error: \(error.localizedDescription)")
            throw AIError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            Logger.ai.warning("Claude rate limited")
            throw AIError.rateLimited(.claude)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Logger.ai.error("Claude HTTP error: \(httpResponse.statusCode)")
            throw AIError.invalidResponse
        }

        // Parse response
        let (content, usage) = try parseResponse(data: data)

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        Logger.ai.info("Claude generated response in \(latencyMs)ms")

        return AIResponse(
            content: content,
            tier: .claude,
            latencyMs: latencyMs,
            tokenCount: usage
        )
    }

    // MARK: - Private Helpers

    private func buildRequest(prompt: AIPrompt, token: String) throws -> URLRequest {
        guard let url = URL(string: Self.baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(token, forHTTPHeaderField: "x-api-key")
        request.addValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeoutSeconds

        let body = ClaudeRequestBody(
            model: model,
            maxTokens: 1024,
            system: prompt.systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: prompt.userMessage)
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func parseResponse(data: Data) throws -> (String, Int?) {
        let decoded: ClaudeResponseBody
        do {
            decoded = try JSONDecoder().decode(ClaudeResponseBody.self, from: data)
        } catch {
            Logger.ai.error("Claude response parsing failed")
            throw AIError.invalidResponse
        }

        guard let textBlock = decoded.content?.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            Logger.ai.error("Claude response missing text content")
            throw AIError.invalidResponse
        }

        let totalTokens: Int?
        if let usage = decoded.usage {
            totalTokens = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
        } else {
            totalTokens = nil
        }

        return (text, totalTokens)
    }
}

// MARK: - Claude API Data Types

private struct ClaudeRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeResponseBody: Decodable {
    let content: [ClaudeContentBlock]?
    let usage: ClaudeUsage?
}

private struct ClaudeContentBlock: Decodable {
    let type: String?
    let text: String?
}

private struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
