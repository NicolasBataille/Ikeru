import SwiftUI
import WatchKit
import IkeruCore

// MARK: - HapticPitchDrillView

/// Watch drill that teaches pitch accent patterns through haptic feedback.
/// Taps high/low pitch contours on the wrist using different haptic intensities.
/// 頭高 = strong then weak, 中高 = weak-strong-weak, 尾高 = weak-strong, 平板 = even rhythm.
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

            // Word display
            Text(viewModel.currentWord)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            // Pitch visualization (dots showing high/low)
            HStack(spacing: 4) {
                ForEach(Array(viewModel.currentMoraHighLow.enumerated()), id: \.offset) { _, isHigh in
                    Circle()
                        .fill(isHigh ? Color.orange : Color.gray)
                        .frame(width: 10, height: 10)
                        .offset(y: isHigh ? -4 : 4)
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
                .tint(.orange)

                Button {
                    viewModel.nextWord()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .tint(.blue)
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
    let totalWords: Int = 8

    private(set) var currentWord: String = ""
    private(set) var currentPatternLabel: String = ""
    private(set) var currentMoraHighLow: [Bool] = []

    var isComplete: Bool {
        currentIndex >= totalWords
    }

    private var words: [(word: String, pattern: PitchAccentPattern)] = []

    // MARK: - Sample Words

    /// Sample words with known pitch patterns for haptic training.
    private static let sampleWords: [(word: String, moraCount: Int, accentPosition: Int)] = [
        // 平板 (heiban) — flat
        ("さくら", 3, 0),    // sakura
        ("ともだち", 4, 0),  // tomodachi
        // 頭高 (atamadaka) — accent on first
        ("いぬ", 2, 1),      // inu
        ("カメラ", 3, 1),    // kamera
        // 中高 (nakadaka) — accent in middle
        ("おとこ", 3, 2),    // otoko
        ("たまご", 3, 2),    // tamago
        // 尾高 (odaka) — accent on last
        ("あたま", 3, 3),    // atama
        ("おとうと", 4, 4),  // otouto
    ]

    // MARK: - Session

    func startSession() {
        words = Self.sampleWords.shuffled().prefix(totalWords).map { sample in
            let pattern = PitchAccentPattern.make(
                moraCount: sample.moraCount,
                accentPosition: sample.accentPosition
            )
            return (word: sample.word, pattern: pattern)
        }
        currentIndex = 0
        loadCurrentWord()
    }

    func nextWord() {
        currentIndex += 1
        if !isComplete {
            loadCurrentWord()
        } else {
            WKInterfaceDevice.current().play(.notification)
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
            for (index, isHigh) in pattern.moraHighLow.enumerated() {
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
        currentPatternLabel = entry.pattern.type.displayLabel
        currentMoraHighLow = entry.pattern.moraHighLow
    }
}

#Preview {
    HapticPitchDrillView()
}
