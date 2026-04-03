import SwiftUI
import IkeruCore

// MARK: - LootBoxChallengeView

/// Full-screen challenge that must be completed to open a lootbox.
/// Features a timed quiz with infinite retries — failure only delays, never punishes.
struct LootBoxChallengeView: View {

    let lootBox: LootBox
    var onComplete: (([LootItem]) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var score: Int = 0
    @State private var timeRemaining: Int
    @State private var isTimerRunning = false
    @State private var challengeState: ChallengeState = .ready
    @State private var currentQuestionIndex: Int = 0
    @State private var hapticCorrect = false
    @State private var hapticIncorrect = false

    init(lootBox: LootBox, onComplete: (([LootItem]) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.lootBox = lootBox
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
    }

    // MARK: - Ready State

    private var readyContent: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            // Lootbox icon
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.Rarity.epic))

            Text("Lootbox Challenge!")
                .font(.system(size: IkeruTheme.Typography.Size.heading1, weight: .bold))
                .foregroundStyle(.white)

            // Challenge description
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: lootBox.challengeType.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Text(lootBox.challengeType.displayName)
                    .font(.ikeruHeading2)
                    .foregroundStyle(.white)

                Text(lootBox.challengeType.description)
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .multilineTextAlignment(.center)

                Text("Score \(lootBox.requiredScore) in \(lootBox.challengeType.timeLimitSeconds)s")
                    .font(.ikeruStats)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .ikeruCard(.standard)

            Spacer()

            Button("Start Challenge") {
                startChallenge()
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Active State

    private var activeContent: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            // Timer and score header
            HStack {
                // Timer
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Image(systemName: "clock.fill")
                    Text("\(timeRemaining)s")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                }
                .foregroundStyle(timeRemaining <= 10 ? Color.ikeruError : .ikeruTextSecondary)

                Spacer()

                // Score
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Text("\(score)/\(lootBox.requiredScore)")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                    Image(systemName: "star.fill")
                }
                .foregroundStyle(Color.ikeruPrimaryAccent)
            }

            // Progress bar
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

            // Quick-tap challenge area
            challengeButtons

            Spacer()
        }
    }

    private var challengeButtons: some View {
        // Simplified challenge: 4 answer buttons, tap the correct one
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text("Tap the correct answer!")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: IkeruTheme.Spacing.md) {
                ForEach(0..<4, id: \.self) { index in
                    Button {
                        handleAnswer(index: index)
                    } label: {
                        Text(answerText(for: index))
                            .font(.system(size: IkeruTheme.Typography.Size.kanjiMedium))
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    .ikeruButtonStyle(index == correctAnswerIndex ? .primary : .secondary)
                }
            }
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
                Button("Retry") {
                    retryChallenge()
                }
                .ikeruButtonStyle(.primary)

                Button("Later") {
                    onDismiss?()
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

    private var correctAnswerIndex: Int {
        // Rotate correct answer position
        currentQuestionIndex % 4
    }

    private func answerText(for index: Int) -> String {
        // Simplified: use kana for visual variety
        let kana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ",
                     "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と"]
        let offset = (currentQuestionIndex * 4 + index) % kana.count
        return kana[offset]
    }

    private func startChallenge() {
        score = 0
        currentQuestionIndex = 0
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        challengeState = .active
        startTimer()
    }

    private func retryChallenge() {
        score = 0
        currentQuestionIndex = 0
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        challengeState = .active
        startTimer()
    }

    private func handleAnswer(index: Int) {
        if index == correctAnswerIndex {
            score += 1
            hapticCorrect.toggle()
            currentQuestionIndex += 1

            if score >= lootBox.requiredScore {
                challengeState = .completed
                isTimerRunning = false
                onComplete?(lootBox.rewards)
            }
        } else {
            hapticIncorrect.toggle()
        }
    }

    private func startTimer() {
        isTimerRunning = true
        Task { @MainActor in
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

// MARK: - Preview

#Preview("LootBoxChallengeView") {
    LootBoxChallengeView(
        lootBox: LootBox(
            challengeType: .kanjiSpeed,
            requiredScore: 5,
            rewards: [
                LootItem(category: .badge, rarity: .epic, name: "Dragon Scale", iconName: "shield.lefthalf.filled"),
                LootItem(category: .scroll, rarity: .rare, name: "Proverb Scroll", iconName: "scroll.fill"),
            ]
        )
    )
    .preferredColorScheme(.dark)
}
