import SwiftUI
import IkeruCore

// MARK: - ListeningExerciseView

/// Displays a listening exercise with play/pause button, playback rate selector,
/// and multiple-choice comprehension questions.
struct ListeningExerciseView: View {

    @Bindable var viewModel: ListeningViewModel

    /// Invoked when the learner accepts their answer and advances the session.
    /// Correctness is mapped to an FSRS `Grade` via `DrillGradeMapping.listening`
    /// (blueprint §3); listening is XP-only downstream (`listeningSubtitled` is
    /// `.perCompletion`), so the grade shapes only the completion signal, never
    /// an FSRS write. Defaults to a no-op so the standalone `#Preview` compiles.
    var onComplete: (Grade) -> Void = { _ in }

    @State private var hapticCorrect = false
    @State private var hapticIncorrect = false

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            audioControls
            exerciseContent
        }
        .tatamiRoom(.standard)
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .sensoryFeedback(.success, trigger: hapticCorrect)
        .sensoryFeedback(.warning, trigger: hapticIncorrect)
    }

    // MARK: - Audio Controls

    private var audioControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Play button with waveform indicator
            Button {
                Task {
                    await viewModel.playAudio()
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ikeruPrimaryAccent)

                    if viewModel.isPlaying {
                        waveformIndicator
                    } else {
                        Text("Tap to listen")
                            .font(.ikeruBody)
                            .foregroundStyle(.ikeruTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Playback rate selector
            PlaybackRateSelector(
                selectedRate: Binding(
                    get: { viewModel.playbackRate },
                    set: { viewModel.setPlaybackRate($0) }
                ),
                isCompact: true
            )
        }
    }

    // MARK: - Waveform Indicator

    private var waveformIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                WaveformBar(index: index, isAnimating: viewModel.isPlaying)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Exercise Content

    @ViewBuilder
    private var exerciseContent: some View {
        if let exercise = viewModel.currentExercise {
            VStack(spacing: IkeruTheme.Spacing.md) {
                // Question
                Text(exercise.question)
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Answer choices
                VStack(spacing: IkeruTheme.Spacing.sm) {
                    ForEach(exercise.allChoices, id: \.self) { choice in
                        answerButton(choice: choice, exercise: exercise)
                    }
                }

                // Play Again + Continue (visible after answering)
                if viewModel.exerciseResult != nil {
                    Button {
                        Task {
                            await viewModel.playAudio()
                        }
                    } label: {
                        Label("Play Again", systemImage: "arrow.clockwise")
                    }
                    .ikeruButtonStyle(.secondary)

                    // Continue — accept the answer and advance the session. Maps
                    // correctness → FSRS Grade (DrillGradeMapping.listening).
                    Button {
                        onComplete(DrillGradeMapping.listening(
                            isCorrect: viewModel.exerciseResult == .correct
                        ))
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .ikeruButtonStyle(.primary)
                }
            }
        } else if viewModel.loadingState.isLoading {
            ProgressView()
                .tint(Color.ikeruPrimaryAccent)
        }
    }

    // MARK: - Answer Button

    private func answerButton(choice: String, exercise: ListeningExercise) -> some View {
        let isSelected = viewModel.selectedAnswer == choice
        let isAnswered = viewModel.exerciseResult != nil
        let isCorrectChoice = choice == exercise.correctAnswer

        return Button {
            guard !isAnswered else { return }
            viewModel.submitAnswer(choice)
            if exercise.isCorrect(answer: choice) {
                hapticCorrect.toggle()
            } else {
                hapticIncorrect.toggle()
            }
        } label: {
            HStack {
                Text(choice)
                    .font(.ikeruBody)
                    .foregroundStyle(answerForeground(isSelected: isSelected, isAnswered: isAnswered, isCorrectChoice: isCorrectChoice))

                Spacer()

                if isAnswered && isCorrectChoice {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.102, green: 0.078, blue: 0.055))
                } else if isAnswered && isSelected && !isCorrectChoice {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ikeruError)
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .background {
                answerBackgroundView(
                    isSelected: isSelected,
                    isAnswered: isAnswered,
                    isCorrectChoice: isCorrectChoice
                )
            }
            .sumiCorners(
                color: answerCornerColor(
                    isSelected: isSelected,
                    isAnswered: isAnswered,
                    isCorrectChoice: isCorrectChoice
                ),
                size: 8,
                weight: 1.2
            )
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    // MARK: - Answer Appearance

    private func answerForeground(isSelected: Bool, isAnswered: Bool, isCorrectChoice: Bool) -> Color {
        guard isAnswered else { return .white }
        if isCorrectChoice { return Color(red: 0.102, green: 0.078, blue: 0.055) }
        if isSelected { return .white }
        return Color.white.opacity(0.35)
    }

    @ViewBuilder
    private func answerBackgroundView(
        isSelected: Bool,
        isAnswered: Bool,
        isCorrectChoice: Bool
    ) -> some View {
        if isAnswered {
            if isCorrectChoice {
                LinearGradient.ikeruGold
            } else if isSelected {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.ikeruError.opacity(0.22))
                }
            } else {
                Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.45)
            }
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.6))
            }
        }
    }

    private func answerCornerColor(
        isSelected: Bool,
        isAnswered: Bool,
        isCorrectChoice: Bool
    ) -> Color {
        guard isAnswered else { return TatamiTokens.goldDim }
        if isCorrectChoice { return .ikeruPrimaryAccent }
        if isSelected { return Color.ikeruError.opacity(0.7) }
        return TatamiTokens.goldDim.opacity(0.3)
    }
}

// MARK: - WaveformBar

/// Animated waveform bar for audio playback indicator.
private struct WaveformBar: View {
    let index: Int
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var height: CGFloat = 4

    /// Reduce Motion: freeze at a fixed, per-bar height instead of animating —
    /// still reads as a waveform glyph, just static.
    private static let staticHeights: [CGFloat] = [10, 18, 24, 16, 12]

    var body: some View {
        Rectangle()
            .fill(Color.ikeruPrimaryAccent)
            .frame(width: 3, height: height)
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    startAnimation()
                } else {
                    height = 4
                }
            }
    }

    private func startAnimation() {
        guard !reduceMotion else {
            height = Self.staticHeights[index % Self.staticHeights.count]
            return
        }
        let delay = Double(index) * 0.1
        withAnimation(
            .easeInOut(duration: 0.4)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            height = CGFloat.random(in: 8...24)
        }
    }
}

// MARK: - Preview

#Preview("ListeningExerciseView") {
    let audioService = AudioService()
    let vocabulary = [
        VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
        VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
        VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
        VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
    ]
    let vm = ListeningViewModel(
        audioService: audioService,
        vocabulary: vocabulary,
        passages: []
    )

    ListeningExerciseView(viewModel: vm)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
        .task {
            await vm.loadExercise(type: .wordRecognition, level: .n5)
        }
}
