import Foundation

// MARK: - Message Role

/// The role of a participant in a conversation.
public enum MessageRole: String, Sendable, Codable, Equatable {
    case system
    case user
    case assistant
}

// MARK: - Correction

/// A correction provided by the AI for the learner's input.
public struct Correction: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let original: String
    public let corrected: String
    public let explanation: String

    public init(
        id: UUID = UUID(),
        original: String,
        corrected: String,
        explanation: String
    ) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.explanation = explanation
    }
}

// MARK: - Vocabulary Hint

/// A vocabulary hint surfaced during conversation.
public struct VocabularyHint: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let word: String
    public let reading: String
    public let meaning: String

    public init(
        id: UUID = UUID(),
        word: String,
        reading: String,
        meaning: String
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.meaning = meaning
    }
}

// MARK: - Conversation Message

/// A single message in a conversation with the AI partner.
public struct ConversationMessage: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let corrections: [Correction]
    public let vocabularyHints: [VocabularyHint]

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        corrections: [Correction] = [],
        vocabularyHints: [VocabularyHint] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.corrections = corrections
        self.vocabularyHints = vocabularyHints
    }
}

// MARK: - JLPTLevel Conversation Extension

extension JLPTLevel {
    /// A human-readable description of the level complexity for AI prompts.
    public var complexityDescription: String {
        switch self {
        case .n5: "Very simple — basic greetings and short phrases"
        case .n4: "Simple — everyday topics with basic grammar"
        case .n3: "Intermediate — natural conversation on familiar topics"
        case .n2: "Advanced — nuanced discussion with complex grammar"
        case .n1: "Near-native — sophisticated and abstract topics"
        }
    }
}
