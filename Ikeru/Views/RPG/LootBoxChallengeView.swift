import SwiftUI
import IkeruCore

// MARK: - KanjiQuestion

/// A single question used in the Kanji Speed challenge.
private struct KanjiQuestion: Sendable {
    /// The kanji or kana glyph the player must read.
    let prompt: String
    /// The correct reading (hiragana/katakana).
    let correctReading: String
    /// Three distractor readings that look plausible but are wrong.
    let distractors: [String]

    /// Returns the four answer options in a deterministically shuffled order
    /// based on the provided seed, so options never change until the question
    /// advances.
    func shuffledOptions(seed: Int) -> [String] {
        var pool = distractors + [correctReading]
        // Fisher-Yates with a seeded LCG so the shuffle is stable for a
        // given seed but changes each question.
        var rng = SeededRNG(seed: seed)
        for i in stride(from: pool.count - 1, through: 1, by: -1) {
            let j = rng.next() % (i + 1)
            pool.swapAt(i, j)
        }
        return pool
    }
}

// MARK: - SeededRNG (simple LCG, view-local only)

private struct SeededRNG {
    var state: Int
    init(seed: Int) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }
    mutating func next() -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return abs(state)
    }
}

// MARK: - Question Bank

// kanjiSpeedBank: ~20 N5 kanji with unambiguous single target readings.
// Each kanji is chosen so its correctReading is the ONE dominant reading in N5
// context, and no distractor is a valid reading of that kanji.
private let kanjiSpeedBank: [KanjiQuestion] = [
    // 山 kun: やま only (さん is N5 on-reading but not listed as distractor)
    KanjiQuestion(prompt: "山", correctReading: "やま", distractors: ["かわ", "うみ", "もり"]),
    // 川 kun: かわ only
    KanjiQuestion(prompt: "川", correctReading: "かわ", distractors: ["やま", "みち", "はな"]),
    // 月 kun: つき (moon); がつ/げつ are on-readings not given as options
    KanjiQuestion(prompt: "月", correctReading: "つき", distractors: ["ほし", "そら", "くも"]),
    // 雨 kun: あめ only (N5)
    KanjiQuestion(prompt: "雨", correctReading: "あめ", distractors: ["かぜ", "ゆき", "くも"]),
    // 車 kun: くるま only (N5)
    KanjiQuestion(prompt: "車", correctReading: "くるま", distractors: ["ふね", "とり", "むし"]),
    // 電 on: でん — standalone prompt forces on; kun irrelevant standalone
    KanjiQuestion(prompt: "電", correctReading: "でん", distractors: ["かぜ", "みず", "ひ"]),
    // 駅 on: えき only
    KanjiQuestion(prompt: "駅", correctReading: "えき", distractors: ["まち", "みち", "しろ"]),
    // 円 on: えん only (N5 currency)
    KanjiQuestion(prompt: "円", correctReading: "えん", distractors: ["いし", "かね", "ぎん"]),
    // 年 on: ねん — unambiguous in N5
    KanjiQuestion(prompt: "年", correctReading: "ねん", distractors: ["つき", "にち", "しゅう"]),
    // 時 on: じ — unambiguous in N5
    KanjiQuestion(prompt: "時", correctReading: "じ",   distractors: ["ふん", "びょう", "ねん"]),
    // 分 on: ふん (minutes, N5 primary reading)
    KanjiQuestion(prompt: "分", correctReading: "ふん", distractors: ["じ", "びょう", "ねん"]),
    // 母 kun: はは only (N5)
    KanjiQuestion(prompt: "母", correctReading: "はは", distractors: ["ちち", "あね", "いもうと"]),
    // 父 kun: ちち only (N5)
    KanjiQuestion(prompt: "父", correctReading: "ちち", distractors: ["はは", "あに", "おとうと"]),
    // 友 kun: とも only (N5)
    KanjiQuestion(prompt: "友", correctReading: "とも", distractors: ["ひと", "こ", "かた"]),
    // 先 kun: さき — N5 primary standalone
    KanjiQuestion(prompt: "先", correctReading: "さき", distractors: ["あと", "なか", "よこ"]),
    // 校 on: こう only (N5, 学校)
    KanjiQuestion(prompt: "校", correctReading: "こう", distractors: ["がく", "もん", "じゅく"]),
    // 語 on: ご only (N5, 日本語)
    KanjiQuestion(prompt: "語", correctReading: "ご",   distractors: ["じ", "もじ", "かん"]),
    // 本 kun: ほん (book/origin, N5 primary)
    KanjiQuestion(prompt: "本", correctReading: "ほん", distractors: ["もん", "しろ", "いわ"]),
    // 口 kun: くち only (N5)
    KanjiQuestion(prompt: "口", correctReading: "くち", distractors: ["め", "みみ", "はな"]),
    // 手 kun: て only (N5)
    KanjiQuestion(prompt: "手", correctReading: "て",   distractors: ["あし", "かお", "かた"]),
]

// kanaBlitzBank: all romanizations in standard Hepburn (shi/chi/tsu/fu/n).
private let kanaBlitzBank: [KanjiQuestion] = [
    KanjiQuestion(prompt: "あ", correctReading: "a",   distractors: ["i", "u", "e"]),
    KanjiQuestion(prompt: "い", correctReading: "i",   distractors: ["a", "u", "o"]),
    KanjiQuestion(prompt: "う", correctReading: "u",   distractors: ["a", "i", "e"]),
    KanjiQuestion(prompt: "え", correctReading: "e",   distractors: ["a", "o", "u"]),
    KanjiQuestion(prompt: "お", correctReading: "o",   distractors: ["a", "i", "e"]),
    KanjiQuestion(prompt: "か", correctReading: "ka",  distractors: ["ki", "ku", "ke"]),
    KanjiQuestion(prompt: "き", correctReading: "ki",  distractors: ["ka", "ku", "ko"]),
    KanjiQuestion(prompt: "く", correctReading: "ku",  distractors: ["ka", "ki", "ke"]),
    KanjiQuestion(prompt: "け", correctReading: "ke",  distractors: ["ka", "ki", "ko"]),
    KanjiQuestion(prompt: "こ", correctReading: "ko",  distractors: ["ka", "ki", "ku"]),
    KanjiQuestion(prompt: "さ", correctReading: "sa",  distractors: ["shi", "su", "se"]),
    KanjiQuestion(prompt: "し", correctReading: "shi", distractors: ["sa", "su", "so"]),
    KanjiQuestion(prompt: "た", correctReading: "ta",  distractors: ["chi", "tsu", "te"]),
    KanjiQuestion(prompt: "ち", correctReading: "chi", distractors: ["ta", "tsu", "te"]),
    KanjiQuestion(prompt: "つ", correctReading: "tsu", distractors: ["ta", "chi", "to"]),
    KanjiQuestion(prompt: "な", correctReading: "na",  distractors: ["ni", "nu", "ne"]),
    KanjiQuestion(prompt: "は", correctReading: "ha",  distractors: ["hi", "fu", "he"]),
    KanjiQuestion(prompt: "ふ", correctReading: "fu",  distractors: ["ha", "hi", "ho"]),
    KanjiQuestion(prompt: "ん", correctReading: "n",   distractors: ["mu", "no", "nu"]),
    KanjiQuestion(prompt: "ア", correctReading: "a",   distractors: ["i", "u", "e"]),
]

// vocabMatchBank: prompt = kanji/kana word, options = short English meanings.
private let vocabMatchBank: [KanjiQuestion] = [
    KanjiQuestion(prompt: "水",   correctReading: "water",    distractors: ["fire", "tree", "mountain"]),
    KanjiQuestion(prompt: "火",   correctReading: "fire",     distractors: ["water", "wind", "earth"]),
    KanjiQuestion(prompt: "木",   correctReading: "tree",     distractors: ["flower", "grass", "stone"]),
    KanjiQuestion(prompt: "山",   correctReading: "mountain", distractors: ["river", "sea", "sky"]),
    KanjiQuestion(prompt: "川",   correctReading: "river",    distractors: ["lake", "sea", "rain"]),
    KanjiQuestion(prompt: "雨",   correctReading: "rain",     distractors: ["snow", "wind", "cloud"]),
    KanjiQuestion(prompt: "車",   correctReading: "car",      distractors: ["train", "ship", "plane"]),
    KanjiQuestion(prompt: "本",   correctReading: "book",     distractors: ["pen", "paper", "desk"]),
    KanjiQuestion(prompt: "母",   correctReading: "mother",   distractors: ["father", "sister", "friend"]),
    KanjiQuestion(prompt: "父",   correctReading: "father",   distractors: ["mother", "brother", "teacher"]),
    KanjiQuestion(prompt: "犬",   correctReading: "dog",      distractors: ["cat", "bird", "fish"]),
    KanjiQuestion(prompt: "ねこ", correctReading: "cat",      distractors: ["dog", "rabbit", "horse"]),
]

// grammarRushBank: choose the correct particle or verb form to fill the gap.
// Prompt uses __ as a blank; options are short grammatical choices.
private let grammarRushBank: [KanjiQuestion] = [
    // Location に with います
    KanjiQuestion(prompt: "猫がそこ__ います", correctReading: "に",   distractors: ["を", "が", "で"]),
    // Destination に with 行きます
    KanjiQuestion(prompt: "学校__ 行きます", correctReading: "に",    distractors: ["を", "が", "で"]),
    // Object marker を
    KanjiQuestion(prompt: "りんご__ 食べます", correctReading: "を",   distractors: ["に", "が", "は"]),
    // Topic marker は (introducing a topic in a statement)
    KanjiQuestion(prompt: "わたし__ 学生です", correctReading: "は",   distractors: ["を", "に", "で"]),
    // Subject marker が with あります (standard N5 existential)
    KanjiQuestion(prompt: "つくえの上に本__ あります", correctReading: "が", distractors: ["を", "に", "で"]),
    // Instrument/means で
    KanjiQuestion(prompt: "バス__ 来ます", correctReading: "で",       distractors: ["に", "が", "を"]),
    // Te-form て with ください
    KanjiQuestion(prompt: "食べ__ ください", correctReading: "て",     distractors: ["た", "る", "ない"]),
    // Past tense た
    KanjiQuestion(prompt: "昨日、映画を見__", correctReading: "た",    distractors: ["て", "る", "ない"]),
    // Negative ない with でください
    KanjiQuestion(prompt: "ここで話さ__ でください", correctReading: "ない", distractors: ["て", "た", "ます"]),
    // Reason から
    KanjiQuestion(prompt: "雨__ 傘を持ちます", correctReading: "から", distractors: ["ので", "でも", "が"]),
]

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
    @State private var timerTask: Task<Void, Never>?
    /// Index of the correct answer inside the current question's shuffled options.
    @State private var correctOptionIndex: Int = 0
    /// Index tapped by the player, nil until they tap something.
    @State private var selectedOptionIndex: Int? = nil
    /// Whether we are displaying post-tap feedback (brief flash).
    @State private var showingFeedback: Bool = false

    init(lootBox: LootBox, onComplete: (([LootItem]) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.lootBox = lootBox
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self._timeRemaining = State(initialValue: lootBox.challengeType.timeLimitSeconds)
    }

    var body: some View {
        ZStack {
            MarbleBackground(variant: .rpg)
                .ignoresSafeArea()
            Color.ikeruBackground.opacity(0.55).ignoresSafeArea()

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

            // Hero: torii gate with challenge kanji stamp
            ZStack {
                ToriiFrame(color: .ikeruPrimaryAccent, lineWidth: 3) {
                    HankoStamp(kanji: challengeHeroKanji, size: 44)
                }
                .frame(width: 96, height: 96)
            }

            // Challenge name + description
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text(LocalizedStringKey(lootBox.challengeType.displayName))
                    .font(.ikeruHeading2)
                    .foregroundStyle(.white)

                Text(LocalizedStringKey(lootBox.challengeType.description))
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .multilineTextAlignment(.center)

                Text(String(format: String(localized: "Score %lld to open"), lootBox.requiredScore))
                    .font(.ikeruStats)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .tatamiRoom(.standard)

            Spacer()

            Button("Begin Challenge") {
                startChallenge()
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Active State

    private var activeContent: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Timer and score header
            HStack {
                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .light))
                    Text("\(timeRemaining)s")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                }
                .foregroundStyle(timeRemaining <= 10 ? Color.ikeruError : .ikeruTextSecondary)

                Spacer()

                HStack(spacing: IkeruTheme.Spacing.xs) {
                    Text("\(score)/\(lootBox.requiredScore)")
                        .font(.ikeruHeading3)
                        .monospacedDigit()
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.ikeruPrimaryAccent)
            }

            // Progress rail — 2pt gold FusumaRail style
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TatamiTokens.goldDim.opacity(0.25))
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(width: geometry.size.width * progressFraction, height: 2)
                        .animation(.spring(duration: 0.3), value: score)
                }
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 2)

            Spacer()

            // Question prompt
            questionPromptCard

            // Answer grid
            answerGrid

            Spacer()
        }
    }

    /// Large card showing the character/word to identify.
    private var questionPromptCard: some View {
        let question = currentQuestion
        return VStack(spacing: IkeruTheme.Spacing.xs) {
            Text("Tap the correct reading!")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            Text(question.prompt)
                .font(.system(size: IkeruTheme.Typography.Size.kanjiDisplay, weight: .light, design: .serif))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, IkeruTheme.Spacing.lg)
        }
        .tatamiRoom(.glass)
    }

    private var answerGrid: some View {
        let question = currentQuestion
        let options = question.shuffledOptions(seed: currentQuestionIndex)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: IkeruTheme.Spacing.sm) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    guard !showingFeedback else { return }
                    handleAnswer(index: index, options: options, question: question)
                } label: {
                    Text(options[index])
                        .font(.system(size: IkeruTheme.Typography.Size.kanjiMedium, weight: .light))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(answerForeground(for: index))
                        .background(answerBackground(for: index))
                        .sumiCorners(color: answerCornerColor(for: index), size: 8, weight: 1.2)
                }
                .disabled(showingFeedback)
            }
        }
    }

    // MARK: - Failed State

    private var failedContent: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            // Dim torii (challenge not yet won)
            ToriiFrame(color: TatamiTokens.goldDim, lineWidth: 2.5, dashed: true) {
                Text("又")
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .frame(width: 80, height: 80)
            .opacity(0.7)

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text("Time's Up!")
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)

                Text("Score: \(score)/\(lootBox.requiredScore)")
                    .font(.ikeruHeading3)
                    .foregroundStyle(.ikeruTextSecondary)

                Text("No worries — try again!")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .tatamiRoom(.standard)

            Spacer()

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Button("Try Again") {
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

    // MARK: - Answer Button Appearance

    /// The foreground colour for an answer button at `index`, post-tap aware.
    private func answerForeground(for index: Int) -> Color {
        guard showingFeedback, let selected = selectedOptionIndex else {
            return .white
        }
        if index == correctOptionIndex { return Color(red: 0.102, green: 0.078, blue: 0.055) } // dark on gold
        if index == selected { return .white }
        return Color.white.opacity(0.35)
    }

    /// Background for an answer button at `index`.
    @ViewBuilder
    private func answerBackground(for index: Int) -> some View {
        if showingFeedback {
            if index == correctOptionIndex {
                // Gold fill — correct answer
                LinearGradient.ikeruGold
            } else if index == selectedOptionIndex {
                // Wrong answer chosen: terracotta tint
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.ikeruError.opacity(0.22))
                }
            } else {
                // Dim other options
                Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.45)
            }
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.6))
            }
        }
    }

    private func answerCornerColor(for index: Int) -> Color {
        guard showingFeedback else { return TatamiTokens.goldDim }
        if index == correctOptionIndex { return .ikeruPrimaryAccent }
        if index == selectedOptionIndex { return Color.ikeruError.opacity(0.7) }
        return TatamiTokens.goldDim.opacity(0.3)
    }

    // MARK: - Logic

    private var progressFraction: Double {
        guard lootBox.requiredScore > 0 else { return 0 }
        return min(1.0, Double(score) / Double(lootBox.requiredScore))
    }

    /// The question currently displayed.
    private var currentQuestion: KanjiQuestion {
        let bank = questionBank
        guard !bank.isEmpty else {
            return KanjiQuestion(prompt: "?", correctReading: "?", distractors: ["a", "b", "c"])
        }
        return bank[currentQuestionIndex % bank.count]
    }

    private var questionBank: [KanjiQuestion] {
        switch lootBox.challengeType {
        case .kanjiSpeed:  return kanjiSpeedBank
        case .kanaBlitz:   return kanaBlitzBank
        case .vocabMatch:  return vocabMatchBank
        case .grammarRush: return grammarRushBank
        }
    }

    /// The kanji shown inside the ToriiFrame / HankoStamp on the ready screen.
    private var challengeHeroKanji: String {
        switch lootBox.challengeType {
        case .kanjiSpeed:  return "読"
        case .vocabMatch:  return "語"
        case .kanaBlitz:   return "仮"
        case .grammarRush: return "文"
        }
    }

    private func startChallenge() {
        score = 0
        currentQuestionIndex = 0
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        selectedOptionIndex = nil
        showingFeedback = false
        challengeState = .active
        refreshCorrectIndex()
        startTimer()
    }

    private func retryChallenge() {
        score = 0
        currentQuestionIndex = 0
        timeRemaining = lootBox.challengeType.timeLimitSeconds
        selectedOptionIndex = nil
        showingFeedback = false
        challengeState = .active
        refreshCorrectIndex()
        startTimer()
    }

    /// Recomputes which shuffled-option slot holds the correct answer for the
    /// current question.  Must be called after `currentQuestionIndex` changes.
    private func refreshCorrectIndex() {
        let question = currentQuestion
        let options = question.shuffledOptions(seed: currentQuestionIndex)
        correctOptionIndex = options.firstIndex(of: question.correctReading) ?? 0
    }

    private func handleAnswer(index: Int, options: [String], question: KanjiQuestion) {
        selectedOptionIndex = index
        showingFeedback = true

        let isCorrect = (index == correctOptionIndex)

        if isCorrect {
            hapticCorrect.toggle()
        } else {
            hapticIncorrect.toggle()
        }

        // Brief feedback window, then advance
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            showingFeedback = false
            selectedOptionIndex = nil

            if isCorrect {
                score += 1
                if score >= lootBox.requiredScore {
                    challengeState = .completed
                    isTimerRunning = false
                    timerTask?.cancel()
                    onComplete?(lootBox.rewards)
                    return
                }
            }
            currentQuestionIndex += 1
            refreshCorrectIndex()
        }
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
