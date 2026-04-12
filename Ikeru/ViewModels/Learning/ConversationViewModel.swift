import Foundation
import IkeruCore
import os

#if canImport(Speech)
import Speech
#endif

// MARK: - Conversation ViewModel

@MainActor
@Observable
public final class ConversationViewModel {

    // MARK: - Exposed State

    /// All messages in the current conversation.
    public private(set) var messages: [ConversationMessage] = []

    /// The current text in the input field.
    public var inputText: String = ""

    /// Whether the AI is currently generating a response.
    public private(set) var isLoading: Bool = false

    /// Whether voice input mode is active.
    public private(set) var isVoiceActive: Bool = false

    /// Whether the AI service is available.
    public private(set) var isAIAvailable: Bool = false

    /// Error message to display, if any.
    public private(set) var errorMessage: String?

    /// The learner's JLPT level for this conversation.
    public let jlptLevel: JLPTLevel

    // MARK: - Computed

    /// Whether the send button should be enabled.
    public var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    /// Whether to show the welcome state (no messages yet).
    public var showWelcome: Bool {
        messages.isEmpty && !isLoading
    }

    // MARK: - Dependencies

    private let conversationService: ConversationService
    private let speechDelegate: SpeechRecognitionDelegate?
    private let vocabularyRepository: VocabularyRepository?

    // MARK: - Init

    public init(
        conversationService: ConversationService,
        jlptLevel: JLPTLevel = .n5,
        speechDelegate: SpeechRecognitionDelegate? = nil,
        vocabularyRepository: VocabularyRepository? = nil
    ) {
        self.conversationService = conversationService
        self.jlptLevel = jlptLevel
        self.speechDelegate = speechDelegate
        self.vocabularyRepository = vocabularyRepository
    }

    // MARK: - Lifecycle

    /// Check AI availability on appear.
    public func onAppear() async {
        // AI availability is managed by AIRouterService's tier status
        isAIAvailable = true
    }

    // MARK: - Send Message

    /// Send the current input text as a user message.
    public func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMessage = ConversationMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isLoading = true

        defer { isLoading = false }

        do {
            let response = try await conversationService.sendMessage(
                text,
                history: messages,
                jlptLevel: jlptLevel
            )
            messages.append(response)
            await logVocabularyEncounters(response)
            Logger.ui.info("Conversation message sent and response received")
        } catch {
            Logger.ai.error("Conversation error: \(error.localizedDescription)")
            handleError(error)
        }
    }

    /// Send a specific text as a message (used by voice input).
    public func sendMessage(_ text: String) async {
        inputText = text
        await sendMessage()
    }

    // MARK: - Voice Input

    /// Toggle voice input mode.
    public func toggleVoiceInput() {
        if isVoiceActive {
            stopVoiceInput()
        } else {
            startVoiceInput()
        }
    }

    /// Start voice recognition.
    public func startVoiceInput() {
        guard let delegate = speechDelegate else {
            errorMessage = "Voice input is not available"
            return
        }

        isVoiceActive = true
        errorMessage = nil

        delegate.startListening { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .partial(let text):
                    self.inputText = text
                case .final(let text):
                    self.inputText = text
                    self.isVoiceActive = false
                case .error(let message):
                    self.errorMessage = message
                    self.isVoiceActive = false
                }
            }
        }
    }

    /// Stop voice recognition.
    public func stopVoiceInput() {
        speechDelegate?.stopListening()
        isVoiceActive = false
    }

    // MARK: - Conversation Management

    /// Clear all messages and start fresh.
    public func clearConversation() {
        messages = []
        errorMessage = nil
    }

    // MARK: - Vocabulary Encounter Tracking

    /// Log encounters for vocabulary hints in a chat response (fire-and-forget).
    private func logVocabularyEncounters(_ message: ConversationMessage) async {
        guard let repo = vocabularyRepository, !message.vocabularyHints.isEmpty else { return }
        for hint in message.vocabularyHints {
            await repo.logEncounterByWord(
                word: hint.word,
                reading: hint.reading,
                meaning: hint.meaning,
                source: .sakuraChat,
                contextSnippet: String(message.content.prefix(120))
            )
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        if let aiError = error as? AIError {
            switch aiError {
            case .providerUnavailable:
                errorMessage = "AI is currently unavailable. Please try again later."
            case .rateLimited:
                errorMessage = "Too many requests. Please wait a moment."
            case .timeout:
                errorMessage = "Response took too long. Please try again."
            case .networkError:
                errorMessage = "Network error. Check your connection."
            case .invalidResponse:
                errorMessage = "Received an invalid response. Please try again."
            case .keyNotFound:
                errorMessage = "AI configuration missing. Check Settings."
            case .allProvidersExhausted:
                errorMessage = "No AI providers available. Try again later."
            }
        } else {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}

// MARK: - Speech Recognition Delegate

/// Protocol for speech recognition integration.
/// The app target provides the concrete implementation using Speech framework.
public enum SpeechResult: Sendable {
    case partial(String)
    case final(String)
    case error(String)
}

public protocol SpeechRecognitionDelegate: AnyObject, Sendable {
    func startListening(completion: @escaping @Sendable (SpeechResult) -> Void)
    func stopListening()
}
