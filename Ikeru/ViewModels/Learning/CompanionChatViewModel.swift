import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - CompanionChatViewModel

@MainActor
@Observable
public final class CompanionChatViewModel {

    // MARK: - Exposed State

    /// All messages in the current conversation.
    public private(set) var messages: [CompanionChatMessage] = []

    /// Current user input text.
    public var inputText: String = ""

    /// Whether the companion is "typing" a response.
    public private(set) var isTyping: Bool = false

    /// Whether there is an attention event (leech, check-in).
    public private(set) var hasAttention: Bool = false

    /// Whether the weekly check-in badge should show.
    public private(set) var showBadge: Bool = false

    // MARK: - Dependencies

    private let repository: CompanionChatRepository
    private let profileId: UUID

    // MARK: - Init

    public init(
        modelContainer: ModelContainer,
        profileId: UUID
    ) {
        self.repository = CompanionChatRepository(modelContainer: modelContainer)
        self.profileId = profileId
    }

    /// Testing initializer with injected repository.
    public init(
        repository: CompanionChatRepository,
        profileId: UUID
    ) {
        self.repository = repository
        self.profileId = profileId
    }

    // MARK: - Load History

    /// Loads persisted chat history for the current profile.
    public func loadHistory() {
        messages = repository.messages(for: profileId)

        if messages.isEmpty {
            addGreeting()
        }

        Logger.ui.info("Loaded \(self.messages.count) companion messages")
    }

    // MARK: - Send Message

    /// Sends a user message and generates a companion response.
    public func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = CompanionChatMessage(
            role: .user,
            content: text,
            profileId: profileId
        )
        repository.save(userMessage)
        messages.append(userMessage)
        inputText = ""

        generateCompanionResponse(to: text)
    }

    // MARK: - Clear History

    /// Clears all chat history for the current profile.
    public func clearHistory() {
        repository.clearHistory(for: profileId)
        messages = []
        addGreeting()
    }

    // MARK: - Attention Events

    /// Triggers an attention bounce (e.g., leech detected).
    public func triggerAttention() {
        hasAttention = true

        // Reset after animation completes
        Task {
            try? await Task.sleep(for: .seconds(1))
            hasAttention = false
        }
    }

    /// Toggles the check-in badge visibility.
    public func setBadge(_ visible: Bool) {
        showBadge = visible
    }

    // MARK: - Leech Intervention

    /// Handles a detected leech card — triggers companion attention and generates intervention.
    public func handleLeechDetected(card: CardDTO) async {
        triggerAttention()
        showBadge = true

        // Analyze confusion and generate intervention
        let confusion = LeechDetectionService.analyzeConfusion(card: card)
        let intervention = LeechInterventionService.generateIntervention(
            card: card,
            confusionPattern: confusion
        )

        // Add intervention message to chat
        let message = CompanionChatMessage(
            role: .companion,
            content: intervention.message,
            profileId: profileId
        )
        repository.save(message)
        messages.append(message)

        Logger.companion.info(
            "Leech intervention triggered for \(card.front), lapses=\(card.lapseCount)"
        )
    }

    // MARK: - Weekly Check-In

    /// Whether a weekly check-in is currently active.
    public private(set) var isCheckInActive: Bool = false

    /// Current weekly summary, available after check-in starts.
    public private(set) var currentSummary: WeeklyCheckInSummary?

    /// Starts a weekly check-in conversation.
    public func startWeeklyCheckIn(checkInService: WeeklyCheckInService) async {
        guard !isCheckInActive else { return }
        isCheckInActive = true

        let summary = await checkInService.generateWeeklySummary()
        currentSummary = summary

        let openingMessage = buildCheckInOpening(from: summary)
        let message = CompanionChatMessage(
            role: .companion,
            content: openingMessage,
            profileId: profileId
        )
        repository.save(message)
        messages.append(message)

        Logger.companion.info("Weekly check-in started")
    }

    /// Ends the check-in conversation.
    public func endCheckIn(checkInService: WeeklyCheckInService) {
        checkInService.recordCheckIn()
        isCheckInActive = false
        showBadge = false

        let closing = CompanionChatMessage(
            role: .companion,
            content: "Thanks for checking in! I've noted your feedback. Keep up the good work this week.",
            profileId: profileId
        )
        repository.save(closing)
        messages.append(closing)
    }

    private func buildCheckInOpening(from summary: WeeklyCheckInSummary) -> String {
        var parts: [String] = ["Hey! It's been a week -- let's look at how things went."]

        if summary.sessionsCompleted > 0 {
            parts.append("You completed \(summary.sessionsCompleted) session\(summary.sessionsCompleted == 1 ? "" : "s") and reviewed \(summary.cardsReviewed) card\(summary.cardsReviewed == 1 ? "" : "s").")
        } else {
            parts.append("It looks like you didn't have any study sessions this week.")
        }

        if summary.cardsReviewed > 0 {
            let pct = Int(summary.overallAccuracy * 100)
            parts.append("Your overall accuracy was \(pct)%.")
        }

        for observation in summary.observations {
            parts.append(observation)
        }

        parts.append("How do you feel about your progress this week?")
        return parts.joined(separator: " ")
    }

    // MARK: - Private

    private func addGreeting() {
        let greeting = CompanionChatMessage(
            role: .companion,
            content: "こんにちは! I'm your study companion. Ask me about any kanji like [KANJI:食] or try a quick quiz! How can I help today?",
            profileId: profileId
        )
        repository.save(greeting)
        messages.append(greeting)
    }

    private func generateCompanionResponse(to userText: String) {
        isTyping = true

        // Simulate companion thinking with a brief delay
        Task {
            try? await Task.sleep(for: .milliseconds(800))

            let response = buildResponse(for: userText)
            let companionMessage = CompanionChatMessage(
                role: .companion,
                content: response,
                profileId: profileId
            )
            repository.save(companionMessage)
            messages.append(companionMessage)
            isTyping = false
        }
    }

    /// Whether the active app locale is French. Reads the same UserDefaults
    /// key the global `AppLocale` uses, so the stub follows the in-app
    /// language picker (independent of the system locale).
    private var isFrench: Bool {
        let raw = UserDefaults.standard.string(forKey: "ikeru.uiLanguage") ?? "system"
        switch raw {
        case "fr": return true
        case "en": return false
        default:
            return Locale.preferredLanguages.contains { $0.lowercased().hasPrefix("fr") }
        }
    }

    /// Builds a contextual companion response.
    /// In a future story, this will use AIRouterService for richer responses.
    private func buildResponse(for userText: String) -> String {
        let lowered = userText.lowercased()

        if lowered.contains("kanji") || containsJapanese(userText) {
            return buildKanjiResponse(for: userText)
        }

        if lowered.contains("quiz") || lowered.contains("test") {
            return isFrench
                ? "Avec plaisir ! Essaie celui-ci : [QUIZ:食|manger|boire|lire] Que signifie ce kanji ?"
                : "Sure! Let's try this: [QUIZ:食|to eat|to drink|to read] What does this kanji mean?"
        }

        if lowered.contains("mnemonic") || lowered.contains("remember")
            || lowered.contains("mnémonique") || lowered.contains("souvenir")
        {
            return isFrench
                ? "Voici un moyen mnémotechnique : [MNEMONIC:食|Une personne assise à table avec de la nourriture — le radical du haut est un toit, et en dessous une assiette pleine] Essaie de le visualiser !"
                : "Here's a helpful trick: [MNEMONIC:食|A person sitting at a table with food - the top radical is a roof, and below is a plate of good food] Try to visualize it!"
        }

        if lowered.contains("hello") || lowered.contains("hi") || lowered.contains("hey")
            || lowered.contains("bonjour") || lowered.contains("salut")
        {
            return isFrench
                ? "Bonjour ! Prêt à apprendre du japonais ? Pose-moi une question sur un kanji, ou dis « quiz » pour un petit défi !"
                : "Hello! Ready to learn some Japanese? Try asking me about a kanji, or say 'quiz me' for a quick challenge!"
        }

        return isFrench
            ? "Intéressant ! Laisse-moi te partager quelque chose d'utile : [KANJI:学] Voici 学 (まなぶ) qui signifie « apprendre ». Continue, tu vas le maîtriser ! Demande-moi un quiz ou un moyen mnémotechnique quand tu veux."
            : "That's interesting! Let me share something helpful: [KANJI:学] This is 学 (まなぶ) meaning 'to learn'. Keep studying and you'll master it! Ask me for a quiz or mnemonic anytime."
    }

    private func buildKanjiResponse(for text: String) -> String {
        let kanjiInText = text.unicodeScalars.first { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }

        if let kanji = kanjiInText {
            let char = String(kanji)
            return isFrench
                ? "Excellente question sur [KANJI:\(char)] ! Ce kanji est fascinant. Voici un aide-mémoire : [MNEMONIC:\(char)|Décompose-le en radicaux pour mieux t'en souvenir] Veux-tu que je te questionne dessus ?"
                : "Great question about [KANJI:\(char)]! This kanji is fascinating. Here's a memory aid: [MNEMONIC:\(char)|Break it down into its radicals to remember it better] Want me to quiz you on it?"
        }

        return isFrench
            ? "Je te montre un kanji intéressant : [KANJI:日] Voici 日 (にち/ひ) qui signifie « jour » ou « soleil ». On dirait une fenêtre laissant passer la lumière du soleil ! [MNEMONIC:日|Un cadre de fenêtre avec le soleil qui brille à travers]"
            : "Let me show you an interesting kanji: [KANJI:日] This is 日 (にち/ひ) meaning 'day' or 'sun'. It looks like a window with sunlight streaming through! [MNEMONIC:日|A window frame with the sun shining through it]"
    }

    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) || // Hiragana
            (0x30A0...0x30FF).contains(scalar.value) || // Katakana
            (0x4E00...0x9FFF).contains(scalar.value)    // CJK
        }
    }
}
