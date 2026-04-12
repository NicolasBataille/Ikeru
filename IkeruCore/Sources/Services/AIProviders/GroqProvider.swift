import Foundation

// MARK: - GroqProvider
//
// Groq runs Llama 3.3 70B on custom LPU silicon — sub-second latency, free tier
// generous enough for personal use (30 RPM / 14 400 req/day at time of writing).
//
// Get a free key: https://console.groq.com/keys

public final class GroqProvider: AIProvider, @unchecked Sendable {

    public let name = "Groq"
    public let tier = AITier.groq

    private let transport: OpenAICompatibleTransport

    public init(
        model: String = "llama-3.3-70b-versatile",
        keychainStore: any KeychainStore = KeychainHelper(),
        networkChecker: any NetworkChecker = NWPathNetworkChecker(),
        urlSession: any URLSessionProvider = URLSession.shared,
        timeoutSeconds: Double = 10
    ) {
        self.transport = OpenAICompatibleTransport(
            providerName: "Groq",
            tier: .groq,
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            model: model,
            keychainKey: KeychainKeys.groqAPIKey,
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
