import Foundation
import IkeruCore
import os

#if canImport(Speech)
import Speech
#endif

// MARK: - Conversation Topic

/// A suggested conversation topic that can seed the chat with an opening message.
public struct ConversationTopic: Hashable, Sendable {
    /// Japanese title shown in the topic list (e.g. "自己紹介").
    public let japanese: String
    /// English label shown below the Japanese title.
    public let english: String
    /// JLPT difficulty tag shown in the topic row badge.
    public let jlptLevel: String

    public init(japanese: String, english: String, jlptLevel: String) {
        self.japanese = japanese
        self.english = english
        self.jlptLevel = jlptLevel
    }
}

// MARK: - Conversation ViewModel

@MainActor
@Observable
public final class ConversationViewModel: Identifiable {

    /// Stable identity so `ConversationView` can be presented via
    /// `.fullScreenCover(item:)` — which guarantees a non-nil value in the
    /// cover content (the `isPresented:` + optional `if let` pattern raced and
    /// presented an empty/black screen).
    public let id = UUID()

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

    /// Whether the device is currently offline. Checked independently of
    /// `isAIAvailable` (each cloud provider's own availability check already
    /// folds in reachability) so the "no AI" fallback can tell "you have no
    /// key configured" apart from "you have no internet" — nagging an offline
    /// user to go set up an AI key would be a dark pattern.
    public private(set) var isOffline: Bool = false

    /// Error message to display, if any.
    public private(set) var errorMessage: String?

    /// The learner's JLPT level for this conversation. Mutable so the toolbar
    /// level picker can change Sakura's reply difficulty for subsequent sends;
    /// @Observable tracks the change and re-renders the badge + starters.
    public var jlptLevel: JLPTLevel

    /// A topic to seed when the conversation starts. Set before presenting
    /// ConversationView; consumed (and cleared) on first appear.
    public var seedTopic: ConversationTopic?

    /// The learner's app interface language (FR/EN), read from the `\.locale`
    /// environment by `ConversationView` and mirrored here so it can be
    /// forwarded to `ConversationService.sendMessage` — Sakura writes
    /// translations/corrections in this language instead of guessing from
    /// what the learner types. Defaults to `.current` so a view model built
    /// without the wiring (tests, previews) still behaves reasonably.
    public var interfaceLocale: Locale = .current

    // MARK: - Computed

    /// Whether the send button should be enabled.
    public var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    /// Whether to show the welcome state (no messages yet and no pending seed).
    public var showWelcome: Bool {
        messages.isEmpty && !isLoading && seedTopic == nil
    }

    // MARK: - Dependencies

    private let conversationService: ConversationService
    private let speechDelegate: SpeechRecognitionDelegate?
    private let vocabularyRepository: VocabularyRepository?
    private let contentRepository: ContentRepository?
    private let networkChecker: any NetworkChecker

    /// `word(reading)` tokens for the words the learner has saved to their
    /// dictionary, fetched once on appear and passed to Sakura as a SOFT
    /// preference (reuse only when natural — never forced). Capped so the
    /// system prompt stays bounded no matter how large the dictionary grows.
    private var knownVocabulary: [String] = []
    private static let maxKnownVocabulary = 40

    /// `word -> reading` lookup from the curated content bundle, fetched once
    /// on appear and passed to `conversationService.sendMessage` so AI vocab
    /// hints can be reconciled against authoritative readings (see
    /// `ReadingValidator`). Empty when `contentRepository` is nil — the
    /// feature is then a no-op and hints pass through unvalidated.
    private var bundleReadings: [String: String] = [:]

    // MARK: - Init

    /// Le prénom donné à l'onboarding, transmis à Sakura comme préférence
    /// souple (OBS2-028). Vide par défaut : les `#Preview` et les tests
    /// construisent le modèle sans profil, et le prompt reste alors
    /// rigoureusement inchangé.
    private let learnerName: String

    public init(
        conversationService: ConversationService,
        jlptLevel: JLPTLevel = .n5,
        speechDelegate: SpeechRecognitionDelegate? = nil,
        vocabularyRepository: VocabularyRepository? = nil,
        contentRepository: ContentRepository? = nil,
        learnerName: String = "",
        networkChecker: any NetworkChecker = NWPathNetworkChecker()
    ) {
        self.learnerName = learnerName
        self.conversationService = conversationService
        self.jlptLevel = jlptLevel
        self.speechDelegate = speechDelegate
        self.vocabularyRepository = vocabularyRepository
        self.contentRepository = contentRepository
        self.networkChecker = networkChecker
    }

    // MARK: - Lifecycle

    /// Check AI availability on appear. If a seedTopic is pending, starts the
    /// conversation on that topic once availability is confirmed.
    public func onAppear() async {
        await conversationService.aiRouter.refreshTierStatuses()
        let statuses = conversationService.aiRouter.tierStatuses
        isAIAvailable = statuses.values.contains { $0 == .available }
        isOffline = await Self.confirmOffline(networkChecker)

        await loadKnownVocabulary()
        bundleReadings = await contentRepository?.readingLookup(for: jlptLevel) ?? [:]

        if let topic = seedTopic, isAIAvailable, messages.isEmpty {
            seedTopic = nil
            await startWithTopic(topic)
        }
    }

    /// `NWPathNetworkChecker` reports `isOnline == false` until its
    /// NWPathMonitor delivers the first path update — a freshly created
    /// checker read too early would misclassify an online user as offline
    /// (and hide the key-setup CTA behind the offline notice). An "online"
    /// answer is always trustworthy; an "offline" answer must survive a
    /// short grace re-check before we believe it.
    private static func confirmOffline(_ checker: any NetworkChecker) async -> Bool {
        if checker.isOnline { return false }
        try? await Task.sleep(for: .milliseconds(400))
        return !checker.isOnline
    }

    /// Fetches the learner's saved dictionary words once and caches them as
    /// `word(reading)` tokens, ranked most-mastered first so the capped slice
    /// favours words worth reinforcing. Whole-array replacement — no mutation.
    private func loadKnownVocabulary() async {
        guard let repo = vocabularyRepository else { return }
        let entries = await repo.allEntries()
        knownVocabulary = entries
            .sorted { ($0.mastery.rawValue, $0.encounterCount) > ($1.mastery.rawValue, $1.encounterCount) }
            .prefix(Self.maxKnownVocabulary)
            .map { $0.reading.isEmpty ? $0.word : "\($0.word)(\($0.reading))" }
    }

    // MARK: - Topic Seeding

    /// Start a conversation seeded on a suggested topic. Posts an opening
    /// user message in the topic language and immediately requests Sakura's reply.
    /// Call this only when isAIAvailable is true; if AI is offline the method
    /// is a no-op so the existing "Sakura offline" banner remains visible.
    public func startWithTopic(_ topic: ConversationTopic) async {
        guard isAIAvailable, messages.isEmpty else { return }
        // Opening line: use the Japanese topic title as a natural conversation
        // starter so Sakura's first reply is contextual.
        let opening = topic.japanese
        await sendMessage(opening)
    }

    // MARK: - Send Message

    /// Send the current input text as a user message.
    public func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        messages.append(ConversationMessage(role: .user, content: text))
        inputText = ""
        await generateReply(to: text)
    }

    /// Send a specific text as a message (used by voice input and starter chips).
    public func sendMessage(_ text: String) async {
        inputText = text
        await sendMessage()
    }

    /// Re-request Sakura's reply to the most recent user message after a
    /// transient failure — used by the inline error "Retry" button. Does not
    /// append a duplicate user bubble and never collapses the chat surface.
    public func retryLastMessage() async {
        guard !isLoading,
              let lastUser = messages.last(where: { $0.role == .user })
        else { return }
        await generateReply(to: lastUser.content)
    }

    /// Request Sakura's reply for `userText` against the current history.
    /// Shared by sendMessage and retryLastMessage so both surface the same
    /// inline, retryable error instead of the full "offline" screen on a
    /// recoverable failure.
    private func generateReply(to userText: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await conversationService.sendMessage(
                userText,
                history: messages,
                jlptLevel: jlptLevel,
                knownVocabulary: knownVocabulary,
                learnerName: learnerName,
                bundleReadings: bundleReadings,
                interfaceLocale: interfaceLocale
            )
            messages.append(response)
            await logVocabularyEncounters(response)
            Logger.ui.info("Conversation message sent and response received")
        } catch {
            Logger.ai.error("Conversation error: \(error.localizedDescription)")
            handleError(error)
        }
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
            errorMessage = "Sakura.Error.VoiceUnavailable"
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
        // A single recoverable send failure must NOT collapse the chat to the
        // full "Sakura offline" screen — availability was already confirmed on
        // appear, and on devices without on-device AI (e.g. A16) one failed
        // call would otherwise hide the chat and the user's typed message.
        // Instead we surface an inline, retryable error and leave isAIAvailable
        // untouched. errorMessage holds a catalogue KEY so the view resolves it
        // against the in-app language via Text(LocalizedStringKey:) — which
        // String(localized:) here would not honour (it ignores the AppLocale
        // override).
        if let aiError = error as? AIError {
            switch aiError {
            case .providerUnavailable:
                errorMessage = "Sakura.Error.Unavailable"
            case .rateLimited:
                errorMessage = "Sakura.Error.RateLimited"
            case .timeout:
                errorMessage = "Sakura.Error.Timeout"
            case .networkError:
                errorMessage = "Sakura.Error.Network"
            case .invalidResponse:
                errorMessage = "Sakura.Error.InvalidResponse"
            case .invalidKey:
                errorMessage = "Sakura.Error.KeyInvalid"
            case .keyNotFound:
                errorMessage = "Sakura.Error.KeyMissing"
            case .allProvidersExhausted:
                errorMessage = "Sakura.Error.AllProvidersFailed"
            }
        } else {
            errorMessage = "Sakura.Error.Generic"
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
