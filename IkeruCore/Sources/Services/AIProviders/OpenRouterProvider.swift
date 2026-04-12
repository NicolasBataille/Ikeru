import Foundation

// MARK: - OpenRouterProvider
//
// OpenRouter aggregates many models behind a single OpenAI-compatible endpoint.
// We default to a free Llama 3.3 70B model. Users can override per-request later
// once the router supports model selection.
//
// Get a free key: https://openrouter.ai/keys

public final class OpenRouterProvider: AIProvider, @unchecked Sendable {

    public let name = "OpenRouter"
    public let tier = AITier.openRouter

    private let transport: OpenAICompatibleTransport

    public init(
        model: String = "meta-llama/llama-3.3-70b-instruct:free",
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 10
    ) {
        self.transport = OpenAICompatibleTransport(
            providerName: "OpenRouter",
            tier: .openRouter,
            endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            model: model,
            keychainKey: KeychainKeys.openRouterAPIKey,
            keychainStore: keychainStore,
            networkChecker: networkChecker,
            urlSession: urlSession,
            timeoutSeconds: timeoutSeconds
        )
    }

    public var isAvailable: Bool {
        get async { await transport.isAvailable }
    }

    public func generate(prompt: AIPrompt) async throws -> AIResponse {
        try await transport.generate(prompt: prompt)
    }
}
