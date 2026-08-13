import SwiftUI
import WatchKit
import IkeruCore

// MARK: - HapticPitchDrillView

/// Watch drill that teaches pitch accent patterns through haptic feedback.
/// Taps high/low pitch contours on the wrist using different haptic intensities.
/// 頭高 = strong then weak, 中高 = weak-strong-weak. 尾高 and 平板 sound identical on the word
/// alone (both weak-strong…strong) — they only diverge on the mora right after the word, so
/// every word is shown and tapped out together with a trailing が: 尾高 drops on that が
/// (weak), 平板 stays strong on it.
struct HapticPitchDrillView: View {

    @State private var viewModel = HapticPitchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.isComplete {
                completionView
            } else {
                drillContent
            }
        }
        .onAppear {
            viewModel.startSession()
        }
    }

    // MARK: - Drill Content

    private var drillContent: some View {
        VStack(spacing: 6) {
            // Pattern type label
            Text(viewModel.currentPatternLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Word display, followed by the particle that reveals odaka vs. heiban.
            // 尾高 and 平板 sound identical on the word alone — the accent drop (or lack of
            // one) only shows up on the mora right after, so the particle has to be shown too.
            HStack(spacing: 2) {
                Text(viewModel.currentWord)
                    .foregroundStyle(.white)
                Text(viewModel.currentParticle)
                    .foregroundStyle(IkeruPlatformTheme.gold)
            }
            .font(.system(size: 24, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            // Pitch visualization (dots showing high/low), one dot per mora plus one for
            // the trailing particle mora — with a small gap marking where the particle starts.
            HStack(spacing: 4) {
                ForEach(Array(viewModel.currentMoraHighLow.enumerated()), id: \.offset) { index, isHigh in
                    Circle()
                        .fill(isHigh ? IkeruPlatformTheme.gold : Color.gray)
                        .frame(width: 10, height: 10)
                        .offset(y: isHigh ? -4 : 4)
                        .padding(.leading, index == viewModel.particleMoraIndex ? 6 : 0)
                }
            }
            .frame(height: 20)

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    viewModel.playHapticPattern()
                } label: {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .tint(IkeruPlatformTheme.gold)

                Button {
                    viewModel.nextWord()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .tint(IkeruPlatformTheme.gold)
            }

            // Progress
            Text("\(viewModel.currentIndex + 1)/\(viewModel.totalWords)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("Pitch Training Done!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Button("Again") {
                viewModel.startSession()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - HapticPitchViewModel

@MainActor
@Observable
final class HapticPitchViewModel {

    // MARK: - State

    private(set) var currentIndex: Int = 0
    /// Set once per session by `startSession()` to `words.count` — kept in sync with however
    /// many words `selectSessionWords` actually returns, so it can never drift from the pool
    /// it's sampled from (see the regression this fixes: it used to be a hardcoded `8` while
    /// the sample pool had grown to 10 entries).
    private(set) var totalWords: Int = 0

    private(set) var currentWord: String = ""
    /// The particle shown after the word (が). Odaka and heiban are indistinguishable on the
    /// word alone, so the drill always appends a particle and includes its mora in the
    /// pitch/haptic pattern — see `PitchAccentPattern.moraHighLowWithTrailingParticle`.
    private(set) var currentParticle: String = HapticPitchViewModel.drillParticle
    private(set) var currentPatternLabel: String = ""
    private(set) var currentMoraHighLow: [Bool] = []

    /// Index of the trailing particle mora within `currentMoraHighLow` — always the last one.
    var particleMoraIndex: Int {
        currentMoraHighLow.count - 1
    }

    var isComplete: Bool {
        // `!words.isEmpty` guards the brief window before `onAppear` calls `startSession()`,
        // when `totalWords` still holds its `0` initial value — without it,
        // `currentIndex (0) >= totalWords (0)` would flash the completion screen first.
        !words.isEmpty && currentIndex >= totalWords
    }

    private var words: [(word: String, pattern: PitchAccentPattern)] = []

    /// Number of words drawn per session.
    private static let wordsPerSession = 8

    /// The particle appended after every drill word so odaka's accent drop (which lands on
    /// the particle, not the word) has something to land on.
    private static let drillParticle = "が"

    // MARK: - Sample Words

    /// Sample words with known pitch patterns for haptic training.
    ///
    /// Each word is filed under the section matching its TRUE pattern (verified against
    /// NHK/OJAD accent dictionaries). See `HapticPitchDrillSampleWordsTests` in
    /// `IkeruCore/Tests/Models/Content` for a regression guard that recomputes the pattern
    /// from `(moraCount, accentPosition)` and checks it matches the declared section.
    private static let sampleWords: [(word: String, moraCount: Int, accentPosition: Int)] = [
        // 平板 (heiban) — flat
        ("さくら", 3, 0),    // sakura
        ("ともだち", 4, 0),  // tomodachi
        // 頭高 (atamadaka) — accent on first
        ("ねこ", 2, 1),      // neko — cat
        ("カメラ", 3, 1),    // kamera
        // 中高 (nakadaka) — accent in middle
        ("たまご", 3, 2),    // tamago
        ("せんせい", 4, 3),  // sensei — teacher
        // 尾高 (odaka) — accent on last
        ("あたま", 3, 3),    // atama
        ("おとうと", 4, 4),  // otouto
        ("いぬ", 2, 2),      // inu — dog (was mis-filed under atamadaka; true pattern is odaka)
        ("おとこ", 3, 3),    // otoko — man (was mis-filed under nakadaka; true pattern is odaka)
    ]

    // MARK: - Session

    func startSession() {
        words = Self.selectSessionWords(from: Self.sampleWords, count: Self.wordsPerSession).map { sample in
            let pattern = PitchAccentPattern.make(
                moraCount: sample.moraCount,
                accentPosition: sample.accentPosition
            )
            return (word: sample.word, pattern: pattern)
        }
        totalWords = words.count
        currentIndex = 0
        loadCurrentWord()
    }

    /// Samples `count` words from `pool`, guaranteeing at least one word per pitch accent
    /// pattern type before filling the remainder at random.
    ///
    /// A plain `pool.shuffled().prefix(count)` can — and, with heiban having only 2 of the 10
    /// sample words, regularly does — produce a session with zero examples of some pattern
    /// type. That's a session the learner can't fully practice no matter what they do.
    private static func selectSessionWords(
        from pool: [(word: String, moraCount: Int, accentPosition: Int)],
        count: Int
    ) -> [(word: String, moraCount: Int, accentPosition: Int)] {
        guard count < pool.count else { return pool.shuffled() }

        let grouped = Dictionary(grouping: pool) { sample in
            PitchAccentPattern.classifyType(moraCount: sample.moraCount, accentPosition: sample.accentPosition)
        }

        let guaranteed = PitchAccentType.allCases.compactMap { type in
            grouped[type]?.randomElement()
        }
        let guaranteedWords = Set(guaranteed.map(\.word))

        let remainingPool = pool.filter { !guaranteedWords.contains($0.word) }
        let fillCount = max(0, count - guaranteed.count)
        let filler = remainingPool.shuffled().prefix(fillCount)

        return (guaranteed + filler).shuffled()
    }

    func nextWord() {
        currentIndex += 1
        if !isComplete {
            loadCurrentWord()
        } else {
            WKInterfaceDevice.current().play(.notification)
            // Deliberately NOT graded through `CardRepository.gradeCard`
            // (chantier #46, arbitrage "b" scoped to this drill only — the
            // kana quiz took arbitrage "a", see `WatchQuizViewModel`). This
            // drill never asks the learner to answer anything: `nextWord()`
            // only advances a haptic playback, so `correctCount` is always
            // `totalWords` regardless of what the learner did or didn't do.
            // There is no correctness signal to grade and no `Card` this
            // maps to (pitch accent isn't a card type in the SRS deck), so
            // producing a `ReviewLog` here would fabricate a review that
            // never happened. It stays an XP-only exposure exercise via the
            // legacy aggregate `WatchSessionResult` path — see
            // `WatchConnectivityManager.processWatchResult`, which
            // deliberately does NOT bump `RPGState.totalReviewsCompleted`
            // for `.pitchAccent` for the same reason.
            let result = WatchSessionResult(
                correctCount: totalWords,
                totalQuestions: totalWords,
                drillType: .pitchAccent,
                xpEarned: totalWords * 3
            )
            WatchSessionManager.shared.sendSessionResult(result)
        }
    }

    /// Plays the haptic pattern for the current word's pitch accent.
    /// Maps mora high/low to haptic intensities:
    /// - High mora: `.click` (strong tap)
    /// - Low mora: `.directionDown` (soft tap)
    func playHapticPattern() {
        guard currentIndex < words.count else { return }
        let pattern = words[currentIndex].pattern
        let device = WKInterfaceDevice.current()

        Task { @MainActor in
            for (index, isHigh) in pattern.moraHighLowWithTrailingParticle.enumerated() {
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                if isHigh {
                    device.play(.click)
                } else {
                    device.play(.directionDown)
                }
            }
        }
    }

    // MARK: - Private

    private func loadCurrentWord() {
        guard currentIndex < words.count else { return }
        let entry = words[currentIndex]
        currentWord = entry.word
        currentParticle = Self.drillParticle
        currentPatternLabel = entry.pattern.type.displayLabel
        currentMoraHighLow = entry.pattern.moraHighLowWithTrailingParticle
    }
}

#Preview {
    HapticPitchDrillView()
}
