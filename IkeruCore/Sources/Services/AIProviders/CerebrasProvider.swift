import Foundation

// MARK: - CerebrasProvider
//
// Cerebras runs Llama on wafer-scale silicon — the fastest hosted inference
// available (1000+ tokens/s on Llama 3.3 70B). Free tier covers personal use.
//
// Get a free key: https://cloud.cerebras.ai

public final class CerebrasProvider: AIProvider, @unchecked Sendable {

    public let name = "Cerebras"
    public let tier = AITier.cerebras

    private let transport: OpenAICompatibleTransport

    public init(
        model: String = "llama-3.3-70b",
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 10
    ) {
        self.transport = OpenAICompatibleTransport(
            providerName: "Cerebras",
            tier: .cerebras,
            endpoint: URL(string: "https://api.cerebras.ai/v1/chat/completions")!,
            model: model,
            keychainKey: KeychainKeys.cerebrasAPIKey,
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
