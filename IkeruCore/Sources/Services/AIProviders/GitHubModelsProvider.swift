import Foundation

// MARK: - GitHubModelsProvider
//
// GitHub Models exposes a curated catalogue of LLMs (Llama, Phi, Mistral, GPT-4o-mini)
// behind an OpenAI-compatible endpoint, authenticated with a fine-grained GitHub
// Personal Access Token. Free for personal use within rate limits.
//
// Get a free PAT: https://github.com/settings/personal-access-tokens
// (No special scope required for the public Models inference endpoint.)

public final class GitHubModelsProvider: AIProvider, @unchecked Sendable {

    public let name = "GitHub Models"
    public let tier = AITier.githubModels

    private let transport: OpenAICompatibleTransport

    public init(
        model: String = "Llama-3.3-70B-Instruct",
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 10
    ) {
        self.transport = OpenAICompatibleTransport(
            providerName: "GitHub Models",
            tier: .githubModels,
            endpoint: URL(string: "https://models.inference.ai.azure.com/chat/completions")!,
            model: model,
            keychainKey: KeychainKeys.githubModelsAPIKey,
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
