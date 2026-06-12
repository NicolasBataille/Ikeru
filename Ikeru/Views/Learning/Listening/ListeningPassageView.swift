import SwiftUI
import IkeruCore

// MARK: - ListeningPassageView

/// Displays a passage-length listening exercise with audio playback,
/// comprehension questions, and progressive transcript reveal.
struct ListeningPassageView: View {

    @Bindable var viewModel: ListeningViewModel

    @State private var hapticCorrect = false
    @State private var hapticIncorrect = false

    var body: some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                passageHeader
                audioSection
                questionSection
                transcriptSection
            }
            .padding(IkeruTheme.Spacing.md)
        }
        .sensoryFeedback(.success, trigger: hapticCorrect)
        .sensoryFeedback(.warning, trigger: hapticIncorrect)
    }

    // MARK: - Passage Header

    private var passageHeader: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 32))
                .foregroundStyle(Color.ikeruPrimaryAccent)

            Text("Listening Passage")
                .font(.ikeruHeading2)
                .foregroundStyle(.white)

            if let exercise = viewModel.currentExercise {
                Text(exercise.jlptLevel.displayLabel)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, IkeruTheme.Spacing.xs)
                    .background {
                        Rectangle()
                            .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Play/Pause button
            Button {
                Task {
                    await viewModel.playAudio()
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.ikeruPrimaryAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isPlaying ? "Playing..." : "Listen to passage")
                            .font(.ikeruBody)
                            .foregroundStyle(.white)

                        Text("Tap to \(viewModel.isPlaying ? "replay" : "play")")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    }

                    Spacer()
                }
                .padding(IkeruTheme.Spacing.md)
            }
            .buttonStyle(.plain)
            .tatamiRoom(.standard)

            // Playback rate selector
            PlaybackRateSelector(
                selectedRate: Binding(
                    get: { viewModel.playbackRate },
                    set: { viewModel.setPlaybackRate($0) }
                )
            )
        }
    }

    // MARK: - Question Section

    @ViewBuilder
    private var questionSection: some View {
        if let exercise = viewModel.currentExercise {
            VStack(spacing: IkeruTheme.Spacing.md) {
                Text(exercise.question)
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: IkeruTheme.Spacing.sm) {
                    ForEach(exercise.allChoices, id: \.self) { choice in
                        passageAnswerButton(choice: choice, exercise: exercise)
                    }
                }

                // Play Again button
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
            .tatamiRoom(.standard)
        }
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private var transcriptSection: some View {
        if viewModel.exerciseResult != nil,
           let transcript = viewModel.currentExercise?.transcript {
            VStack(spacing: IkeruTheme.Spacing.md) {
                if viewModel.isTranscriptRevealed {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.ikeruPrimaryAccent)
                            Text("Transcript")
                                .font(.ikeruHeading3)
                                .foregroundStyle(.white)
                        }

                        Text(transcript)
                            .font(.system(size: IkeruTheme.Typography.Size.body))
                            .foregroundStyle(.white)
                            .lineSpacing(8)
                    }
                    .tatamiRoom(.standard)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Button {
                        withAnimation(.spring(duration: IkeruTheme.Animation.standardDuration)) {
                            viewModel.revealTranscript()
                        }
                    } label: {
                        Label("Show Transcript", systemImage: "eye")
                    }
                    .ikeruButtonStyle(.ghost)
                }
            }
        }
    }

    // MARK: - Answer Button

    private func passageAnswerButton(
        choice: String,
        exercise: ListeningExercise
    ) -> some View {
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
                    .foregroundStyle(passageAnswerForeground(isSelected: isSelected, isAnswered: isAnswered, isCorrectChoice: isCorrectChoice))

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
                passageAnswerBackgroundView(
                    isSelected: isSelected,
                    isAnswered: isAnswered,
                    isCorrectChoice: isCorrectChoice
                )
            }
            .sumiCorners(
                color: passageAnswerCornerColor(
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

    // MARK: - Colors

    private func passageAnswerForeground(isSelected: Bool, isAnswered: Bool, isCorrectChoice: Bool) -> Color {
        guard isAnswered else { return .white }
        if isCorrectChoice { return Color(red: 0.102, green: 0.078, blue: 0.055) }
        if isSelected { return .white }
        return Color.white.opacity(0.35)
    }

    @ViewBuilder
    private func passageAnswerBackgroundView(
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

    private func passageAnswerCornerColor(
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

// MARK: - Preview

#Preview("ListeningPassageView") {
    let audioService = AudioService()
    let passages = [
        ListeningExercisePassage(
            text: "今日は天気がいいです。公園に行きましょう。",
            question: "What does the speaker suggest?",
            correctAnswer: "Going to the park",
            distractors: ["Going home", "Going shopping", "Going to school"],
            transcript: "今日は天気がいいです。公園に行きましょう。",
            jlptLevel: .n5
        )
    ]
    let vm = ListeningViewModel(
        audioService: audioService,
        vocabulary: [],
        passages: passages
    )

    ListeningPassageView(viewModel: vm)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
        .task {
            await vm.loadExercise(type: .passageComprehension, level: .n5)
        }
}
