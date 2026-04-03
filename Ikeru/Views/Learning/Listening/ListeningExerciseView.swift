import SwiftUI
import IkeruCore

// MARK: - ListeningExerciseView

/// Displays a listening exercise with play/pause button, playback rate selector,
/// and multiple-choice comprehension questions.
struct ListeningExerciseView: View {

    @Bindable var viewModel: ListeningViewModel

    @State private var hapticCorrect = false
    @State private var hapticIncorrect = false

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            audioControls
            exerciseContent
        }
        .ikeruCard(.interactive)
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

                // Play Again button (visible after answering)
                if viewModel.exerciseResult != nil {
                    Button {
                        Task {
                            await viewModel.playAudio()
                        }
                    } label: {
                        Label("Play Again", systemImage: "arrow.clockwise")
                    }
                    .ikeruButtonStyle(.secondary)
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
                    .foregroundStyle(.white)

                Spacer()

                if isAnswered && isCorrectChoice {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.ikeruSuccess)
                } else if isAnswered && isSelected && !isCorrectChoice {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ikeruSecondaryAccent)
                }
            }
            .padding(IkeruTheme.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                    .fill(answerBackgroundColor(
                        isSelected: isSelected,
                        isAnswered: isAnswered,
                        isCorrectChoice: isCorrectChoice
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                    .strokeBorder(
                        answerBorderColor(
                            isSelected: isSelected,
                            isAnswered: isAnswered,
                            isCorrectChoice: isCorrectChoice
                        ),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    // MARK: - Answer Colors

    private func answerBackgroundColor(
        isSelected: Bool,
        isAnswered: Bool,
        isCorrectChoice: Bool
    ) -> Color {
        guard isAnswered else {
            return Color.ikeruSurface.opacity(0.5)
        }
        if isCorrectChoice {
            return Color.ikeruSuccess.opacity(0.15)
        }
        if isSelected {
            return Color.ikeruSecondaryAccent.opacity(0.15)
        }
        return Color.ikeruSurface.opacity(0.3)
    }

    private func answerBorderColor(
        isSelected: Bool,
        isAnswered: Bool,
        isCorrectChoice: Bool
    ) -> Color {
        guard isAnswered else {
            return Color.white.opacity(0.1)
        }
        if isCorrectChoice {
            return Color.ikeruSuccess
        }
        if isSelected {
            return Color.ikeruSecondaryAccent
        }
        return Color.white.opacity(0.05)
    }
}

// MARK: - WaveformBar

/// Animated waveform bar for audio playback indicator.
private struct WaveformBar: View {
    let index: Int
    let isAnimating: Bool

    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
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
