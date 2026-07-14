import SwiftUI
import SwiftData
import IkeruCore

// MARK: - LootBoxChallengeView

/// Full-screen challenge that must be completed to open a lootbox.
/// Features a timed quiz with infinite retries — failure only delays, never punishes.
///
/// The quiz draws real questions from the user's own due/learned cards
/// (`CardRepository.dueCards(before:)`, falling back to any learned card) so
/// the challenge reinforces actual SRS content instead of a fixed filler
/// pool. Only when the learner has no cards yet does it fall back to a
/// generic kana-reading quiz.
struct LootBoxChallengeView: View {

    let lootBox: LootBox
    let cardRepository: CardRepository
    var onComplete: (([LootItem]) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var score: Int = 0
    @State private var timeRemaining: Int
    @State private var isTimerRunning = false
    @State private var challengeState: ChallengeState = .ready
    @State private var hapticCorrect = false
    @State private var hapticIncorrect = false
    @State private var timerTask: Task<Void, Never>?
    @State private var currentQuestion = DisplayQuestion.placeholder
    @State private var cardPool: [CardDTO] = []

    init(
        lootBox: LootBox,
        cardRepository: CardRepository,
        onComplete: (([LootItem]) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.lootBox = lootBox
        self.cardRepository = cardRepository
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self._timeRemaining = State(initialValue: lootBox.challengeType.timeLimitSeconds)
    }

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.lg) {
                switch challengeState {
                case .ready:
                    readyContent
                case .active:
                    activeContent
                case .failed:
                    failedContent
                case .completed:
                    EmptyView() // Transition to LootRevealView handled by parent
                }
            }
            .padding(IkeruTheme.Spacing.lg)
        }
        .sensoryFeedback(.success, trigger: hapticCorrect)
        .sensoryFeedback(.warning, trigger: hapticIncorrect)
        .task { await loadCardPool() }
        .onDisappear {
            // Defensive: stop the countdown loop if the view is dismissed
            // mid-challenge (parent pop / failed-state onDismiss).
            timerTask?.cancel()
            isTimerRunning = false
        }
    }

    // MARK: - Ready State

    private var readyContent: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.epic))

            Text("Lootbox Challenge!")
                .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: lootBox.challengeType.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Text(lootBox.challengeType.localizedName)
                    .font(.ikeruHeading2)
                    .foregroundStyle(.white)

                Text(lootBox.challengeType.localizedDescription)
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .multilineTextAlignment(.center)

                Text("Score \(lootBox.requiredScore) in \(lootBox.challengeType.timeLimitSeconds)s")
                    .font(.ikeruStats)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .ikeruCard(.standard)

            Spacer()

            Button {
                Task { await startChallenge() }
            } label: {
                Text("Start Challenge")
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Active State

    private var activeContent: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            HStack {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Image(systemName: "clock.fill")
                    Text("\(timeRemaining)s")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                }
                .foregroundStyle(timeRemaining <= 10 ? Color.ikeruError : .ikeruTextSecondary)

                Spacer()

                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Text("Score: \(score)/\(lootBox.requiredScore)")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                    Image(systemName: "star.fill")
                }
                .foregroundStyle(Color.ikeruPrimaryAccent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.ikeruSurface)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geometry.size.width * progressFraction)
                        .animation(.spring(duration: 0.3), value: score)
                }
            }
            .frame(height: 8)

            Spacer()

            challengeButtons

            Spacer()
        }
    }

    private var challengeButtons: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text(verbatim: currentQuestion.prompt)
                .font(.system(size: IkeruTheme.Typography.Size.kanjiMedium))
                .foregroundStyle(.white)

            questionCaption
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: IkeruTheme.Spacing.md) {
                ForEach(Array(currentQuestion.choices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        handleAnswer(choice)
                    } label: {
                        Text(verbatim: choice)
                            .font(.ikeruBodyLarge)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    // All options share the same style so the layout never
                    // leaks the answer — feedback comes after answering (haptics).
                    .ikeruButtonStyle(.secondary)
                    .accessibilityLabel(Text(verbatim: choice))
                }
            }
        }
    }

    @ViewBuilder
    private var questionCaption: some View {
        switch currentQuestion.kind {
        case .meaning:
            Text("What does this word mean?")
        case .kanaReading:
            Text("Which kana matches this reading?")
        }
    }

    // MARK: - Failed State

    private var failedContent: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.ikeruTextSecondary)

            Text("Time's Up!")
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            Text("Score: \(score)/\(lootBox.requiredScore)")
                .font(.ikeruHeading3)
                .foregroundStyle(.ikeruTextSecondary)

            Text("No worries — try again!")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruPrimaryAccent)

            Spacer()

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Button {
                    retryChallenge()
                } label: {
                    Text("Retry")
                }
                .ikeruButtonStyle(.primary)

                Button {
                    onDismiss?()
                } label: {
                    Text("Later")
                }
                .ikeruButtonStyle(.secondary)
            }
        }
    }

    // MARK: - Logic

    private var progressFraction: Double {
        guard lootBox.requiredScore > 0 else { return 0 }
        return min(1.0, Double(score) / Double(lootBox.requiredScore))
    }

    /// Loads the quiz card pool: due cards first (the most relevant "review
    /// this now" set), falling back to any card the user has already
    /// learned (`reps > 0`) if nothing is currently due. An empty result
    /// (fresh install, no cards yet) is handled gracefully by
    /// `makeQuestion()` falling back to the static kana pool.
    private func loadCardPool() async {
        let due = await cardRepository.dueCards(before: Date())
        if !due.isEmpty {
            cardPool = due
            return
        }
        cardPool = await cardRepository.allCards().filter { $0.fsrsState.reps > 0 }
    }

    /// Builds one question, preferring a real card from `cardPool` and
    /// falling back to the generic kana-reading quiz only when the pool
    /// can't supply a meaningful multiple-choice question (no cards yet, or
    /// too few distinct answers).
    private func makeQuestion() -> DisplayQuestion {
        var rng = SystemRandomNumberGenerator()
        if let real = LootBoxQuizService.makeQuestion(from: cardPool, rng: &rng) {
            return DisplayQuestion(
                kind: .meaning,
                prompt: real.prompt,
                correctAnswer: real.correctAnswer,
                choices: real.choices
            )
        }
        return kanaFallbackQuestion(rng: &rng)
    }

    /// Generic quiz used only when the user has no usable cards yet: one
    /// kana-reading target plus up to 3 plausible distractors (same row or
    /// same vowel column when possible).
    private func kanaFallbackQuestion(rng: inout some RandomNumberGenerator) -> DisplayQuestion {
        let pool = KanaData.hiragana
        guard let target = pool.randomElement(using: &rng) else {
            // The static table is never empty; this only satisfies the compiler.
            return DisplayQuestion(kind: .kanaReading, prompt: "a", correctAnswer: "あ", choices: ["あ"])
        }
        let others = pool.filter { $0.id != target.id && $0.romanization != target.romanization }
        let vowel = String(target.romanization.suffix(1))
        let row = String(target.romanization.dropLast())
        var candidates = others.filter { entry in
            entry.romanization.hasSuffix(vowel) || (!row.isEmpty && entry.romanization.hasPrefix(row))
        }.shuffled(using: &rng)
        if candidates.count < 3 {
            let usedIDs = Set(candidates.map(\.id))
            candidates += others.filter { !usedIDs.contains($0.id) }.shuffled(using: &rng)
        }
        let distractors = Array(candidates.prefix(3))
        let choices = (distractors + [target]).map(\.character).shuffled(using: &rng)
        return DisplayQuestion(
            kind: .kanaReading,
            prompt: target.romanization,
            correctAnswer: target.character,
            choices: choices
        )
    }

    private func startChallenge() async {
        if cardPool.isEmpty {
            await loadCardPool()
        }
        score = 0
        currentQuestion = makeQuestion()
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        challengeState = .active
        startTimer()
    }

    private func retryChallenge() {
        score = 0
        currentQuestion = makeQuestion()
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        challengeState = .active
        startTimer()
    }

    private func handleAnswer(_ choice: String) {
        if choice == currentQuestion.correctAnswer {
            score += 1
            hapticCorrect.toggle()

            if score >= lootBox.requiredScore {
                challengeState = .completed
                isTimerRunning = false
                onComplete?(lootBox.rewards)
                return
            }
        } else {
            hapticIncorrect.toggle()
        }
        // New question either way, so a wrong tap can't be used to
        // eliminate options on the same question.
        currentQuestion = makeQuestion()
    }

    private func startTimer() {
        timerTask?.cancel()
        isTimerRunning = true
        timerTask = Task { @MainActor in
            while isTimerRunning && timeRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard isTimerRunning else { break }
                timeRemaining -= 1
            }
            if timeRemaining <= 0 && challengeState == .active {
                challengeState = .failed
                isTimerRunning = false
            }
        }
    }

    // MARK: - State

    enum ChallengeState {
        case ready
        case active
        case failed
        case completed
    }
}

// MARK: - DisplayQuestion

/// One rendered question: a big verbatim prompt (Japanese card content or a
/// kana romanization — never translated), a caption explaining what to do
/// (localized), and a set of identically-styled choice buttons.
private struct DisplayQuestion: Equatable {
    enum Kind: Equatable {
        case meaning
        case kanaReading
    }

    let kind: Kind
    let prompt: String
    let correctAnswer: String
    let choices: [String]

    static let placeholder = DisplayQuestion(kind: .meaning, prompt: "", correctAnswer: "", choices: [])
}

// MARK: - ChallengeType Localization

/// `LootBox.ChallengeType.displayName`/`.description` return plain `String`s
/// (IkeruCore stays SwiftUI-free, so it can't expose `LocalizedStringKey`
/// directly). These mirror the exact same copy as `LocalizedStringKey`
/// literals so `Text` performs a real catalogue lookup instead of the
/// `verbatim:` fallback `Text(String)` would use.
private extension LootBox.ChallengeType {
    var localizedName: LocalizedStringKey {
        switch self {
        case .kanjiSpeed: "Kanji Speed"
        case .vocabMatch: "Vocab Match"
        case .kanaBlitz: "Kana Blitz"
        case .grammarRush: "Grammar Rush"
        }
    }

    var localizedDescription: LocalizedStringKey {
        switch self {
        case .kanjiSpeed: "Read kanji correctly as fast as you can!"
        case .vocabMatch: "Match vocabulary to their meanings!"
        case .kanaBlitz: "Identify kana in rapid succession!"
        case .grammarRush: "Answer grammar questions correctly!"
        }
    }
}

// MARK: - Preview

#Preview("LootBoxChallengeView") {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)

    if let container = try? ModelContainer(for: schema, configurations: [config]) {
        LootBoxChallengeView(
            lootBox: LootBox(
                challengeType: .kanjiSpeed,
                requiredScore: 5,
                rewards: [
                    LootItem(category: .badge, rarity: .epic, name: "Dragon Scale", iconName: "shield.lefthalf.filled"),
                    LootItem(category: .scroll, rarity: .rare, name: "Proverb Scroll", iconName: "scroll.fill"),
                ]
            ),
            cardRepository: CardRepository(modelContainer: container)
        )
        .preferredColorScheme(.dark)
    } else {
        Text(verbatim: "Preview container unavailable")
    }
}
