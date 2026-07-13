import Foundation

// MARK: - AITier

/// Represents the AI provider tiers in priority order.
/// Comparable conformance reflects tier escalation order.
///
/// `gemini`, `cerebras`, `groq`, `openRouter`, and `githubModels` are all free-tier
/// cloud providers that share the OpenAI-compatible chat completion shape.
/// `claude` remains in the enum for users who opt in to a paid Anthropic API key.
/// `localGPU` is reserved for the future ikeru-rig bridge (Story 7.3 / 7.4).
public enum AITier: Int, Comparable, Sendable, CaseIterable {
    case onDevice = 0
    case gemini = 1
    case cerebras = 2
    case groq = 3
    case openRouter = 4
    case githubModels = 5
    case claude = 6
    case localGPU = 7

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

// MARK: - AIMessage

/// A single role-tagged turn in a multi-turn conversation sent to a provider.
///
/// Only `user` and `assistant` roles are modelled here: the system prompt is
/// carried separately on `AIPrompt.systemPrompt` because most provider APIs put
/// it in a dedicated field (`system_instruction` / `system`) rather than inline
/// in the turn array.
public struct AIMessage: Sendable, Equatable {

    /// The author of a conversation turn.
    public enum Role: String, Sendable, Equatable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

// MARK: - AIPrompt

/// A structured prompt sent to an AI provider.
public struct AIPrompt: Sendable {
    /// System-level instructions for the AI model.
    public let systemPrompt: String

    /// The user's actual (latest) message or question.
    public let userMessage: String

    /// Prior conversation turns (oldest first), NOT including the latest
    /// `userMessage`. Empty for single-shot prompts (mnemonics, one-off
    /// generations). Providers that support multi-turn map `messages` to their
    /// native role array so Sakura remembers earlier turns instead of receiving
    /// a single flattened blob.
    public let history: [AIMessage]

    /// Additional context such as learner level, recent errors, etc.
    public let context: [String: String]

    /// Complexity classification for tier routing.
    public let complexity: PromptComplexity

    public init(
        systemPrompt: String,
        userMessage: String,
        history: [AIMessage] = [],
        context: [String: String] = [:],
        complexity: PromptComplexity = .simple
    ) {
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.history = history
        self.context = context
        self.complexity = complexity
    }

    /// The full ordered conversation: prior turns followed by the latest user
    /// message as a trailing `user` turn. This is the single source of truth
    /// that providers map to their native multi-turn request shape.
    public var messages: [AIMessage] {
        history + [AIMessage(role: .user, text: userMessage)]
    }

    /// A flattened, role-labelled rendering of the conversation for providers
    /// whose API only accepts a single string (on-device FoundationModels, the
    /// local GPU bridge). When there is no prior history this is just the raw
    /// `userMessage`, preserving single-shot behaviour; otherwise earlier turns
    /// are prefixed as labelled context so history is not silently dropped.
    public var flattenedConversation: String {
        guard !history.isEmpty else { return userMessage }

        var lines: [String] = []
        for message in history {
            let label = message.role == .user ? "User" : "Assistant"
            lines.append("\(label): \(message.text)")
        }
        lines.append(userMessage)
        return lines.joined(separator: "\n")
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
    /// The provider rejected the configured API key (e.g. HTTP 400
    /// API_KEY_INVALID, 401, or 403). Distinct from `keyNotFound`: a key IS
    /// configured, but the service refused it — so the UI can tell the user to
    /// fix the key rather than showing a generic "couldn't reply".
    case invalidKey(AITier)
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
