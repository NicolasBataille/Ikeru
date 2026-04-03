import SwiftUI
import IkeruCore

// MARK: - ShadowingExerciseView

/// Displays a shadowing exercise with three phases: listen, record, and feedback.
struct ShadowingExerciseView: View {

    @Bindable var viewModel: ShadowingViewModel

    @State private var hapticRecord = false
    @State private var recordingPulse = false

    var body: some View {
        Group {
            if viewModel.permissionStatus == .denied
                || viewModel.permissionStatus == .restricted {
                permissionDeniedView
            } else {
                exerciseContent
            }
        }
        .task {
            viewModel.checkPermissions()
        }
    }

    // MARK: - Exercise Content

    @ViewBuilder
    private var exerciseContent: some View {
        if let exercise = viewModel.currentExercise {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                phaseIndicator
                targetTextSection(exercise: exercise)
                actionArea
                feedbackSection
            }
            .ikeruCard(.interactive)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .sensoryFeedback(.impact, trigger: hapticRecord)
        } else if viewModel.loadingState.isLoading {
            ProgressView()
                .tint(Color.ikeruPrimaryAccent)
        }
    }

    // MARK: - Phase Indicator

    private var phaseIndicator: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            phaseStep(label: "Listen", phase: .listen)
            phaseConnector
            phaseStep(label: "Speak", phase: .record)
            phaseConnector
            phaseStep(label: "Review", phase: .feedback)
        }
    }

    private func phaseStep(label: String, phase: ExercisePhase) -> some View {
        let isActive = viewModel.exercisePhase == phase
        let isPast = phaseOrder(viewModel.exercisePhase) > phaseOrder(phase)

        return Text(label)
            .font(.ikeruCaption)
            .foregroundStyle(
                isActive ? Color.ikeruPrimaryAccent :
                    isPast ? Color.ikeruSuccess :
                    Color.ikeruTextSecondary
            )
            .fontWeight(isActive ? .semibold : .regular)
    }

    private var phaseConnector: some View {
        Rectangle()
            .fill(Color.ikeruTextSecondary)
            .frame(width: 20, height: 1)
    }

    private func phaseOrder(_ phase: ExercisePhase) -> Int {
        switch phase {
        case .listen: 0
        case .record: 1
        case .feedback: 2
        }
    }

    // MARK: - Target Text Section

    private func targetTextSection(exercise: ShadowingExercise) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            // Main target text
            Text(exercise.targetText)
                .font(.ikeruHeading2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Reading (hiragana)
            Text(exercise.reading)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)

            // Translation
            Text(exercise.translation)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .italic()
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch viewModel.exercisePhase {
        case .listen:
            listenPhaseControls
        case .record:
            recordPhaseControls
        case .feedback:
            feedbackPhaseControls
        }
    }

    // MARK: - Listen Phase

    private var listenPhaseControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Button {
                Task {
                    await viewModel.playTarget()
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ikeruPrimaryAccent)

                    if viewModel.isPlaying {
                        listeningWaveform
                    } else {
                        Text("Tap to listen")
                            .font(.ikeruBody)
                            .foregroundStyle(.ikeruTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            PlaybackRateSelector(
                selectedRate: Binding(
                    get: { viewModel.playbackRate },
                    set: { viewModel.setPlaybackRate($0) }
                ),
                isCompact: true
            )
        }
    }

    private var listeningWaveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                WaveformBar(index: index, isAnimating: viewModel.isPlaying)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Record Phase

    private var recordPhaseControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Real-time recognized text
            if !viewModel.recognizedText.isEmpty {
                Text(viewModel.recognizedText)
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            // Record button
            Button {
                if viewModel.isRecording {
                    Task {
                        await viewModel.stopRecording()
                    }
                } else {
                    hapticRecord.toggle()
                    Task {
                        await viewModel.startRecording()
                    }
                }
            } label: {
                recordButton
            }
            .buttonStyle(.plain)

            // Replay target button
            Button {
                Task {
                    await viewModel.playTarget()
                }
            } label: {
                Label("Replay", systemImage: "speaker.wave.2")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var recordButton: some View {
        ZStack {
            // Pulsing ring animation
            if viewModel.isRecording {
                Circle()
                    .stroke(Color.ikeruSecondaryAccent.opacity(0.3), lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .scaleEffect(recordingPulse ? 1.3 : 1.0)
                    .opacity(recordingPulse ? 0.0 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: recordingPulse
                    )
                    .onAppear { recordingPulse = true }
                    .onDisappear { recordingPulse = false }
            }

            // Main button
            Circle()
                .fill(viewModel.isRecording ? Color.ikeruSecondaryAccent : Color.ikeruPrimaryAccent)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Feedback Phase

    private var feedbackPhaseControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Replay target
            Button {
                Task {
                    await viewModel.playTarget()
                }
            } label: {
                Label("Play Again", systemImage: "speaker.wave.2")
            }
            .ikeruButtonStyle(.secondary)

            // Retry
            Button {
                viewModel.retryExercise()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .ikeruButtonStyle(.primary)
        }
    }

    // MARK: - Feedback Section

    @ViewBuilder
    private var feedbackSection: some View {
        if let result = viewModel.shadowingResult,
           viewModel.exercisePhase == .feedback {
            VStack(spacing: IkeruTheme.Spacing.md) {
                Text("Your pronunciation")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)

                DiffHighlightView(
                    segments: result.diffSegments,
                    accuracy: result.accuracy
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ikeruSecondaryAccent)

            Text("Microphone Access Required")
                .font(.ikeruHeading3)
                .foregroundStyle(.white)

            Text("Shadowing exercises need microphone and speech recognition access to work. Please enable them in Settings.")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .ikeruButtonStyle(.primary)
        }
        .padding(IkeruTheme.Spacing.lg)
        .ikeruCard(.elevated)
        .padding(.horizontal, IkeruTheme.Spacing.md)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - WaveformBar (reused from Listening)

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

#Preview("ShadowingExerciseView") {
    let audioService = AudioService()
    let speechService = SpeechRecognitionService()
    let vocabulary = [
        VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
        VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
        VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
        VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
    ]
    let vm = ShadowingViewModel(
        audioService: audioService,
        speechService: speechService,
        vocabulary: vocabulary
    )

    ShadowingExerciseView(viewModel: vm)
        .background(Color.ikeruBackground)
        .preferredColorScheme(.dark)
        .task {
            await vm.loadExercise(difficulty: .word, level: .n5)
        }
}
