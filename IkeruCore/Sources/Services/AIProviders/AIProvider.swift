import Foundation

// MARK: - AITier

/// Represents the AI provider tiers in priority order.
/// Comparable conformance reflects tier escalation order.
public enum AITier: Int, Comparable, Sendable, CaseIterable {
    case onDevice = 0
    case gemini = 1
    case claude = 2
    case localGPU = 3

    public static func < (lhs: AITier, rhs: AITier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - PromptComplexity

/// Classifies the complexity of an AI prompt to determine tier routing.
public enum PromptComplexity: Sendable {
    case simple
    case medium
    case complex
    case batch
}

// MARK: - AIPrompt

/// A structured prompt sent to an AI provider.
public struct AIPrompt: Sendable {
    /// System-level instructions for the AI model.
    public let systemPrompt: String

    /// The user's actual message or question.
    public let userMessage: String

    /// Additional context such as learner level, recent errors, etc.
    public let context: [String: String]

    /// Complexity classification for tier routing.
    public let complexity: PromptComplexity

    public init(
        systemPrompt: String,
        userMessage: String,
        context: [String: String] = [:],
        complexity: PromptComplexity = .simple
    ) {
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.context = context
        self.complexity = complexity
    }
}

// MARK: - AIResponse

/// The response from an AI provider.
public struct AIResponse: Sendable {
    /// The generated text content.
    public let content: String

    /// Which tier actually served this response.
    public let tier: AITier

    /// Response latency in milliseconds.
    public let latencyMs: Int

    /// Token count (optional, not all providers report this).
    public let tokenCount: Int?

    public init(
        content: String,
        tier: AITier,
        latencyMs: Int,
        tokenCount: Int? = nil
    ) {
        self.content = content
        self.tier = tier
        self.latencyMs = latencyMs
        self.tokenCount = tokenCount
    }
}

// MARK: - AIError

/// Errors that can occur during AI provider operations.
/// Uses @unchecked Sendable because `networkError` contains `any Error` which
/// is not inherently Sendable, but we accept the risk for ergonomic error propagation.
public enum AIError: Error, @unchecked Sendable {
    /// The provider for the given tier is not available.
    case providerUnavailable(AITier)
    /// The request to the given tier timed out.
    case timeout(AITier)
    /// The provider returned a rate limiting response.
    case rateLimited(AITier)
    /// The provider returned an unparseable response.
    case invalidResponse
    /// A network-level error occurred.
    case networkError(any Error)
    /// A required API key or token was not found in the Keychain.
    case keyNotFound(String)
    /// All providers in the fallback chain were exhausted.
    case allProvidersExhausted
}

// MARK: - ProviderStatus

/// The current operational status of an AI provider.
public enum ProviderStatus: Sendable {
    case available
    case unavailable
    case degraded
}

// MARK: - AIProvider Protocol

/// Common interface for all AI tier implementations.
public protocol AIProvider: Sendable {
    /// Human-readable name for this provider.
    var name: String { get }

    /// The tier this provider represents.
    var tier: AITier { get }

    /// Whether this provider is currently available.
    var isAvailable: Bool { get async }

    /// Generate a response for the given prompt.
    /// - Parameter prompt: The structured prompt to send.
    /// - Returns: The AI-generated response.
    /// - Throws: AIError on failure.
    func generate(prompt: AIPrompt) async throws -> AIResponse
}
