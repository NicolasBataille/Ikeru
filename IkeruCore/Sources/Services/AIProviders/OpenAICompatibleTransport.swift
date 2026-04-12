import Foundation
import os

// MARK: - OpenAICompatibleTransport
//
// Shared HTTP transport for OpenAI-compatible chat completion providers.
// Encapsulates: keychain lookup, request build, network call, status code mapping,
// timeout handling, latency measurement, and response parsing. Each concrete
// provider (OpenRouter / Groq / Cerebras / GitHub Models) only supplies its
// endpoint URL, model id, keychain key, and tier.

public struct OpenAICompatibleTransport: Sendable {

    public let providerName: String
    public let tier: AITier
    public let endpoint: URL
    public let model: String
    public let keychainKey: String

    private let keychainStore: any KeychainStore
    private let networkChecker: any NetworkChecker
    private let urlSession: any URLSessionProvider
    private let timeoutSeconds: Double

    public init(
        providerName: String,
        tier: AITier,
        endpoint: URL,
        model: String,
        keychainKey: String,
        keychainStore: any KeychainStore,
        networkChecker: any NetworkChecker,
        urlSession: any URLSessionProvider,
        timeoutSeconds: Double
    ) {
        self.providerName = providerName
        self.tier = tier
        self.endpoint = endpoint
        self.model = model
        self.keychainKey = keychainKey
        self.keychainStore = keychainStore
        self.networkChecker = networkChecker
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
    }

    /// Whether the provider has an API key in the Keychain and the device is online.
    public var isAvailable: Bool {
        get async {
            guard networkChecker.isOnline else { return false }
            do {
                let key = try keychainStore.load(key: keychainKey)
                return key != nil && !(key?.isEmpty ?? true)
            } catch {
                return false
            }
        }
    }

    /// Issues an OpenAI-compatible chat completion request and returns the parsed `AIResponse`.
    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        let start = ContinuousClock.now

        guard let apiKey = try? keychainStore.load(key: keychainKey),
              !apiKey.isEmpty else {
            throw AIError.keyNotFound(keychainKey)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try OpenAIChatCodec.encodeRequest(
            model: model,
            systemPrompt: prompt.systemPrompt,
            userMessage: prompt.userMessage
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw AIError.timeout(tier)
        } catch {
            Logger.ai.error("\(providerName) network error: \(error.localizedDescription)")
            throw AIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            Logger.ai.error("\(providerName) auth error: \(http.statusCode)")
            throw AIError.keyNotFound(keychainKey)
        case 429:
            Logger.ai.warning("\(providerName) rate limited")
            throw AIError.rateLimited(tier)
        default:
            Logger.ai.error("\(providerName) HTTP error: \(http.statusCode)")
            throw AIError.invalidResponse
        }

        let content = try OpenAIChatCodec.decodeResponse(data)

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        Logger.ai.info("\(providerName) generated response in \(latencyMs)ms")

        return AIResponse(
            content: content,
            tier: tier,
            latencyMs: latencyMs
        )
    }
}
