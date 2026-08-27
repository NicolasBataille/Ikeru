import Foundation
import os

// MARK: - Conversation Service

/// Manages AI conversation for the Japanese learning partner.
/// Builds prompts adapted to the learner's JLPT level and parses
/// AI responses for corrections and vocabulary hints.
public final class ConversationService: @unchecked Sendable {

    public let aiRouter: AIRouterService

    /// Time budget used to decide whether the single silent network retry
    /// (see `generateWithSingleNetworkRetry`) is worth attempting at all: if
    /// the first attempt alone already used up this much time, the retry is
    /// skipped outright instead of doubling a slow failure into a slower
    /// one. Without this, a first attempt that burns `AIRouterService`'s own
    /// ~10s fallback budget on timeouts, followed by an unbounded second
    /// attempt doing the same, could leave a learner waiting ~20s in
    /// silence before seeing an error.
    private let timeoutSeconds: TimeInterval

    /// Source of "now" for the system prompt's time-of-day context (greeting
    /// guidance). Defaults to the real clock; injectable so a test can pin the
    /// prompt to a fixed instant instead of racing `Date()`.
    private let clock: @Sendable () -> Date

    /// Calendar used to break `clock()` down into an hour-of-day bucket.
    /// Defaults to `.current` (the device's real calendar/time zone);
    /// injectable alongside `clock` for the same reason.
    private let calendar: Calendar

    public init(
        aiRouter: AIRouterService,
        timeoutSeconds: TimeInterval = 10.0,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.aiRouter = aiRouter
        self.timeoutSeconds = timeoutSeconds
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: - Public API

    /// Send a message and get an AI response adapted to the learner's level.
    /// - Parameters:
    ///   - userMessage: The learner's message text.
    ///   - history: Previous conversation messages for context.
    ///   - jlptLevel: The learner's current JLPT level.
    ///   - knownVocabulary: Words the learner has already studied, as
    ///     `word(reading)` tokens. Passed as a SOFT preference: Sakura is
    ///     told to reuse them only when they fit naturally, never to force
    ///     them. Empty by default so existing callers are unaffected.
    ///   - bundleReadings: `word -> reading` lookup built from the curated
    ///     content bundle (see `ContentRepository.readingLookup(for:)`). The
    ///     AI's furigana is generated text and can be hallucinated; every
    ///     parsed vocabulary hint whose word is a known bundle word has its
    ///     reading reconciled against this map (bundle wins) via
    ///     `ReadingValidator`. Empty by default so existing callers are
    ///     unaffected.
    ///   - interfaceLocale: The learner's app interface language (FR/EN — see
    ///     `AppLocale` in the app target). Fixes the language Sakura writes
    ///     translations/corrections/explanations in, instead of guessing from
    ///     what the learner typed. Defaults to `.current` so existing callers
    ///     are unaffected.
    /// - Returns: A ConversationMessage from the assistant.
    @MainActor
    public func sendMessage(
        _ userMessage: String,
        history: [ConversationMessage],
        jlptLevel: JLPTLevel,
        knownVocabulary: [String] = [],
        learnerName: String = "",
        bundleReadings: [String: String] = [:],
        interfaceLocale: Locale = .current
    ) async throws -> ConversationMessage {
        let prompt = buildPrompt(
            userMessage: userMessage,
            history: history,
            jlptLevel: jlptLevel,
            knownVocabulary: knownVocabulary,
            learnerName: learnerName,
            interfaceLocale: interfaceLocale
        )

        let response = try await generateWithSingleNetworkRetry(prompt: prompt)

        Logger.ai.info("Conversation response from tier \(String(describing: response.tier)) in \(response.latencyMs)ms")

        let parsed = parseResponse(response.content)
        let reconciledHints = reconcileVocabularyHints(parsed.vocabularyHints, against: bundleReadings)

        return ConversationMessage(
            role: .assistant,
            content: parsed.content,
            corrections: parsed.corrections,
            vocabularyHints: reconciledHints
        )
    }

    // MARK: - Network Retry

    /// One short, silent retry when the whole `AIRouterService` fallback
    /// chain fails on a network-level problem — a beginner's very first
    /// Sakura message should not fail on a single flaky connection blip.
    /// Deliberately narrow: does NOT retry a rejected/missing key
    /// (`invalidKey`/`keyNotFound`) or a rate limit (`rateLimited`) —
    /// `AIRouterService` already owns cooldown/`Retry-After` handling for
    /// those (`rateLimitCooldowns`), and retrying here would contradict it.
    ///
    /// Gated by `timeoutSeconds`, because `.allProvidersExhausted` — the
    /// retryable case, see `isRetryableNetworkFailure` — covers both a fast
    /// "nothing is configured/reachable" failure (~400ms:
    /// `GeminiProvider.isAvailable` returns `false` without touching the
    /// network) AND a slow one where `AIRouterService`'s own ~10s fallback
    /// budget was burned entirely on provider timeouts. Retrying
    /// unconditionally in the slow case would silently double a ~10s
    /// failure into a ~20s one with no feedback but the typing indicator —
    /// worse than surfacing the error and letting the learner use the
    /// manual "Reessayer" button (`retryLastMessage`) that already exists
    /// for this slower case. Note this only bounds the DECISION to retry,
    /// not the retry attempt itself: in the one realistic case where the
    /// first attempt genuinely fails fast (nothing configured/reachable —
    /// a state that can't flip in the ~400ms before the retry fires), the
    /// retry re-hits the exact same fast-failing state and stays fast too.
    private func generateWithSingleNetworkRetry(prompt: AIPrompt) async throws -> AIResponse {
        let attemptStart = ContinuousClock.now
        do {
            return try await aiRouter.generate(prompt: prompt)
        } catch let error as AIError {
            guard Self.isRetryableNetworkFailure(error) else { throw error }

            let elapsed = ContinuousClock.now - attemptStart
            let remainingBudget = Duration.seconds(timeoutSeconds) - elapsed

            // The first attempt alone already ate (most of) the total
            // budget — retrying would only stretch a slow failure out
            // further. Surface the first attempt's error immediately
            // instead; requires a floor beyond the retry delay itself so a
            // retry that's doomed to add pure overhead never fires at all.
            guard remainingBudget > Self.networkRetryDelay + Self.minimumRetryWindow else {
                Logger.ai.info("Conversation retry skipped — first attempt already used the time budget")
                throw error
            }

            Logger.ai.info("Conversation request hit a network failure on the first attempt — retrying once")
            try? await Task.sleep(for: Self.networkRetryDelay)
            return try await aiRouter.generate(prompt: prompt)
        }
    }

    /// `AIRouterService.generate` only preserves an "actionable" error
    /// (`invalidKey`/`rateLimited`/`keyNotFound` — see its private
    /// `isActionable`) in `lastMeaningfulError` and rethrows that verbatim.
    /// A chain that fails purely on network errors (or on providers that were
    /// simply unavailable/timed out) does NOT surface as `.networkError` —
    /// it surfaces as the generic `.allProvidersExhausted`. So both cases are
    /// treated as retryable here; `.invalidKey`/`.rateLimited`/`.keyNotFound`
    /// always propagate as themselves and are excluded by the `default`
    /// branch. Verified by reading `AIRouterService.generate` end to end, not
    /// by exercising it live.
    private static func isRetryableNetworkFailure(_ error: AIError) -> Bool {
        switch error {
        case .networkError, .allProvidersExhausted:
            return true
        default:
            return false
        }
    }

    /// Short and silent — long enough to clear a transient blip, short
    /// enough that a genuinely offline learner isn't kept waiting twice.
    private static let networkRetryDelay: Duration = .milliseconds(400)

    /// Minimum leftover window (beyond `networkRetryDelay` itself) required
    /// before the retry is even attempted. Without this floor, a retry could
    /// fire with almost no time left in the budget — pure overhead with
    /// essentially no chance of the story actually changing before the next
    /// failure.
    private static let minimumRetryWindow: Duration = .seconds(1)

    /// Reconciles each parsed vocabulary hint's reading against the content
    /// bundle via `ReadingValidator`, logging once per correction so
    /// hallucinated readings are traceable in the console.
    private func reconcileVocabularyHints(
        _ hints: [VocabularyHint],
        against bundleReadings: [String: String]
    ) -> [VocabularyHint] {
        hints.map { hint in
            let reconciled = ReadingValidator.reconcile(hint, against: bundleReadings)
            if reconciled.corrected {
                Logger.ai.info(
                    "Corrected AI reading for \(hint.word): \(hint.reading) -> \(reconciled.hint.reading)"
                )
            }
            return reconciled.hint
        }
    }

    // MARK: - System Prompt

    /// - Parameters:
    ///   - interfaceLocale: Fixes the language Sakura writes translations,
    ///     corrections, and explanations in — the learner's app interface
    ///     language, not a guess from what they typed. Only FR is
    ///     distinguished (mirrors `AppLocale`'s FR/EN split); anything else
    ///     resolves to English.
    ///   - now: Wall-clock instant used for the time-of-day greeting
    ///     guidance. Passed in (rather than read from `clock()` here) so
    ///     `buildPrompt` is the single place that decides "now".
    ///   - isOngoing: Whether prior turns already exist in this conversation
    ///     (post history-dedup) — controls whether Sakura is told to open
    ///     with a greeting at all.
    private func buildSystemPrompt(
        for level: JLPTLevel,
        knownVocabulary: [String] = [],
        learnerName: String = "",
        interfaceLocale: Locale = .current,
        now: Date = Date(),
        isOngoing: Bool = false
    ) -> String {
        let levelGuidance = levelSpecificGuidance(for: level)
        let knownVocabSection = knownVocabularySection(knownVocabulary)
        let nameSection = learnerNameSection(learnerName)
        let isFrench = Self.isFrench(interfaceLocale)
        let languageName = Self.languageName(isFrench: isFrench)
        let timeContext = timeContextGuidance(now: now, isOngoing: isOngoing)
        let registerNote = Self.registerGuidance(isFrench: isFrench)
        let example = Self.exampleResponse(isFrench: isFrench)

        return """
        You are a friendly Japanese conversation partner for a language learner.
        Your name is Sakura (さくら). You are patient, encouraging, and helpful.

        LEARNER LEVEL: \(level.displayName) — \(level.complexityDescription)
        \(nameSection)

        \(timeContext)

        RULES:
        1. Respond bilingually. Write Japanese first, then add an inline translation \
        in \(languageName) inside parentheses on the SAME line — see EXAMPLE RESPONSE below.
        2. The learner's app interface language is \(languageName). ALWAYS write inline \
        translations, corrections, and vocabulary explanations in \(languageName) — never guess \
        the language from what the learner types, and never switch mid-conversation.
        3. \(levelGuidance)
        4. ALWAYS annotate EVERY kanji with its reading in the format 漢字(かんじ). \
        Never skip furigana for any kanji, regardless of the learner's level. This is critical \
        because the app uses these annotations to display pronunciation guides.
        5. When the learner makes a grammar or vocabulary mistake, gently correct it.
           Format corrections as: [CORRECTION: original → corrected | explanation]
        6. Naturally introduce useful vocabulary related to the topic.
           Format hints as: [VOCAB: word(reading) = meaning]
        7. Keep responses concise: 2-3 sentences typical.
        8. Be warm and conversational — use appropriate casual/polite speech for the level.
        9. Ask follow-up questions to keep the conversation going.
        10. Encourage the learner to try responding in Japanese, even partially.
        11. Follow the CURRENT CONTEXT above for greetings — only open with a time-appropriate \
        one on the first message of a conversation, never again once it's already underway.
        \(registerNote)

        \(knownVocabSection)RESPONSE FORMAT:
        Write your conversational response first (Japanese with inline translations), \
        then any corrections and vocab on separate lines.

        \(example)
        """
    }

    // MARK: - Interface Language

    /// Only FR is distinguished — mirrors the app's `LanguagePreference`
    /// (system/en/fr): anything that isn't French resolves to English, same
    /// as `AppLocale.resolveSystem`.
    private static func isFrench(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "fr"
    }

    private static func languageName(isFrench: Bool) -> String {
        isFrench ? "French" : "English"
    }

    /// French-only note: the app tutoies throughout (see CLAUDE.md / the FR
    /// strings catalogue), but a model writing formal French left to its own
    /// devices defaults to "vous" for corrections — this keeps Sakura's
    /// register consistent with the rest of the app. Empty (and silently
    /// dropped from the prompt) for English, where the tu/vous distinction
    /// doesn't apply.
    private static func registerGuidance(isFrench: Bool) -> String {
        guard isFrench else { return "" }
        return """
        REGISTER: When writing French — translations, corrections, explanations — always use \
        the informal "tu" register, never "vous". This app tutoies the learner throughout; \
        keep that consistent even inside corrections.
        """
    }

    private static func exampleResponse(isFrench: Bool) -> String {
        if isFrench {
            return """
            EXAMPLE RESPONSE for a French-speaking N5 learner who said "Bonjour":
            こんにちは！元気(げんき)ですか？(Bonjour ! Comment vas-tu ?)
            今日(きょう)は何(なに)をしましたか？(Qu'as-tu fait aujourd'hui ?)
            """
        }
        return """
        EXAMPLE RESPONSE for an English-speaking N5 learner who said "Hello":
        こんにちは！元気(げんき)ですか？(Hello! How are you?)
        今日(きょう)は何(なに)をしましたか？(What did you do today?)
        """
    }

    // MARK: - Time Context

    /// Renders the CURRENT CONTEXT paragraph: the learner's approximate
    /// local time (via `calendar`, so it respects the device's real time
    /// zone) and whether Sakura should greet at all. Without this, Sakura had
    /// no notion of time of day (fixed こんにちは regardless of hour) and no
    /// notion of whether a greeting had already happened this conversation.
    private func timeContextGuidance(now: Date, isOngoing: Bool) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 12
        let minute = components.minute ?? 0
        let timeString = String(format: "%02d:%02d", hour, minute)
        let (greetingHint, label) = Self.greetingForHour(hour)

        if isOngoing {
            return """
            CURRENT CONTEXT: It's around \(timeString) (\(label)) where the learner is, and \
            this conversation is already underway. Do NOT open with a greeting again — no \
            こんにちは/おはよう/こんばんは — just continue naturally from where you left off.
            """
        }

        return """
        CURRENT CONTEXT: It's around \(timeString) (\(label)) where the learner is, and this \
        is the first message of the conversation. If you open with a greeting, use \
        \(greetingHint); do not default to こんにちは if it isn't actually daytime there.
        """
    }

    private static func greetingForHour(_ hour: Int) -> (greeting: String, label: String) {
        switch hour {
        case 5..<11: return ("おはよう (or, more politely, おはようございます)", "morning")
        case 11..<17: return ("こんにちは", "afternoon")
        case 17..<22: return ("こんばんは", "evening")
        default: return ("no greeting at all, or at most a quiet こんばんは", "late at night")
        }
    }

    /// Builds an optional, soft-preference vocabulary block for the system
    /// prompt. Returns an empty string when the learner has no studied words
    /// (so the prompt is unchanged). When present, it lists the words and
    /// explicitly frames them as a gentle preference — Sakura must reuse them
    /// only when they fit naturally and must never force or distort the
    /// conversation to include them. Returns a trailing blank line so it slots
    /// cleanly before the RESPONSE FORMAT section.
    /// Le prénom que l'apprenant a donné au tout premier écran de
    /// l'onboarding — et que Sakura n'a jamais reçu (OBS2-028). L'app le
    /// demandait, le stockait, l'affichait sur l'accueil, puis le laissait à
    /// la porte de la seule surface conversationnelle du produit.
    ///
    /// Formulé comme une préférence SOUPLE, exactement comme
    /// `knownVocabularySection` juste en dessous : une partenaire de
    /// conversation qui place le prénom à chaque tour est plus artificielle
    /// que celle qui ne le dit jamais. Vide quand aucun prénom n'est connu,
    /// auquel cas le prompt est rigoureusement inchangé.
    private func learnerNameSection(_ learnerName: String) -> String {
        let trimmed = learnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return """

        LEARNER'S NAME: \(trimmed). Address them by name when it feels natural — greeting them, \
        praising an effort, softening a correction. This is a SOFT preference, never a requirement: \
        do NOT open every message with it, and do NOT work it into a sentence where it would sound \
        forced. Never translate or alter the spelling.
        """
    }

    private func knownVocabularySection(_ knownVocabulary: [String]) -> String {
        guard !knownVocabulary.isEmpty else { return "" }
        return """
        WORDS THE LEARNER ALREADY KNOWS (\(knownVocabulary.count)): \(knownVocabulary.joined(separator: ", ")).
        When one of these fits the conversation NATURALLY, prefer reusing it — it helps the learner \
        consolidate what they have studied. This is a SOFT preference, never a requirement: do NOT force \
        these words in, do NOT distort a sentence or steer the topic just to use one. If none of them fit \
        naturally, simply ignore this list.

        """
    }

    private func levelSpecificGuidance(for level: JLPTLevel) -> String {
        switch level {
        case .n5:
            return """
            Use only basic hiragana/katakana and the simplest kanji (数字, 日, 月, etc.). \
            Use です/ます form exclusively. Very short sentences.
            """
        case .n4:
            return """
            Use N5-N4 kanji. Use です/ます form primarily. Simple compound sentences allowed.
            """
        case .n3:
            return """
            Use kanji up to N3 level freely. \
            Mix polite and casual forms. Natural mid-length sentences.
            """
        case .n2:
            return """
            Use kanji up to N2 level freely. \
            Use natural speech patterns including casual contractions. Complex sentences OK.
            """
        case .n1:
            return """
            Use any kanji naturally. \
            Speak near-natively with idioms, nuance, and sophisticated grammar.
            """
        }
    }

    // MARK: - Prompt Building

    /// Number of most-recent history turns forwarded to the provider. Bounds
    /// token use on long conversations. Mirrors the previous flattened cap.
    private static let maxHistoryTurns = 20

    /// Assemble the `AIPrompt` for a turn as a real ordered multi-turn
    /// conversation. Prior turns become `AIMessage` values (oldest first,
    /// capped to `maxHistoryTurns`) and `userMessage` is carried as the latest
    /// user turn, so the provider receives system + prior user/assistant turns
    /// + new user message instead of one flattened string.
    ///
    /// The app view model appends the new user bubble to its `messages` before
    /// calling, so `history` typically already ends with a `.user` turn equal
    /// to `userMessage`. That trailing duplicate is dropped here so the latest
    /// user message appears exactly once (as the final turn of `prompt.messages`).
    ///
    /// `internal` rather than `private` so it can be unit-tested without the
    /// network — pinning the multi-turn shape end to end.
    ///
    /// `priorTurns` (post history-dedup) is computed BEFORE the system prompt
    /// so `buildSystemPrompt`'s `isOngoing` flag reflects turns that actually
    /// precede this one — the caller (`ConversationViewModel`) appends the new
    /// user bubble to `messages` before calling, so on the very first turn raw
    /// `history` already has one entry and `history.isEmpty` alone would be
    /// wrong here.
    func buildPrompt(
        userMessage: String,
        history: [ConversationMessage],
        jlptLevel: JLPTLevel,
        knownVocabulary: [String] = [],
        learnerName: String = "",
        interfaceLocale: Locale = .current
    ) -> AIPrompt {
        var priorTurns = history
            .suffix(Self.maxHistoryTurns)
            .compactMap { message -> AIMessage? in
                // Exhaustive over MessageRole so a future `.system` history turn
                // is never silently relabelled `assistant` and replayed to the AI
                // as if Sakura had said it. System content lives in the system
                // prompt, so any `.system` turn in the transcript is dropped here.
                switch message.role {
                case .user: return AIMessage(role: .user, text: message.content)
                case .assistant: return AIMessage(role: .assistant, text: message.content)
                case .system: return nil
                }
            }

        // Avoid duplicating the latest user message when the caller already
        // included it in `history`.
        if let last = priorTurns.last, last.role == .user, last.text == userMessage {
            priorTurns.removeLast()
        }

        let systemPrompt = buildSystemPrompt(
            for: jlptLevel,
            knownVocabulary: knownVocabulary,
            learnerName: learnerName,
            interfaceLocale: interfaceLocale,
            now: clock(),
            isOngoing: !priorTurns.isEmpty
        )

        return AIPrompt(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            history: priorTurns,
            context: ["jlpt_level": jlptLevel.rawValue],
            complexity: .medium
        )
    }

    // MARK: - Response Parsing

    private struct ParsedResponse {
        let content: String
        let corrections: [Correction]
        let vocabularyHints: [VocabularyHint]
    }

    /// Delegates to `ChatMarkerParser` for the tolerant marker parsing
    /// itself; this method just adapts its result into the service's own
    /// `ParsedResponse` shape.
    private func parseResponse(_ text: String) -> ParsedResponse {
        let result = ChatMarkerParser.parse(text)
        return ParsedResponse(
            content: result.content,
            corrections: result.corrections,
            vocabularyHints: result.vocabularyHints
        )
    }
}
