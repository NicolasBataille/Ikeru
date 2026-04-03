import SwiftUI
import IkeruCore
import AVFoundation
import os

// MARK: - PitchAccentView

/// Displays a pitch accent exercise with target visualization, recording controls,
/// and analysis feedback overlaid on the contour.
struct PitchAccentView: View {

    @Bindable var viewModel: PitchAccentViewModel
    let speechService: SpeechRecognitionService
    let audioService: AudioService

    /// Mora labels for the current target word (e.g. ["か", "ぜ"]).
    let moraLabels: [String]

    /// The word reading (hiragana) for TTS playback.
    let reading: String

    @State private var isRecording = false
    @State private var recordingPulse = false
    @State private var audioEngine: AVAudioEngine?
    @State private var recordedBuffer: AVAudioPCMBuffer?
    @State private var hapticTrigger = false

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            patternHeader
            contourSection
            actionControls
            accuracyStats
        }
        .ikeruCard(.interactive)
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .task {
            await viewModel.loadAccuracies()
        }
    }

    // MARK: - Pattern Header

    @ViewBuilder
    private var patternHeader: some View {
        if let target = viewModel.targetPattern {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text(target.type.displayLabel)
                    .font(.ikeruHeading2)
                    .foregroundStyle(.white)

                Text("Accent position: \(target.accentPosition)")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
    }

    // MARK: - Contour Section

    @ViewBuilder
    private var contourSection: some View {
        if let target = viewModel.targetPattern {
            VStack(spacing: IkeruTheme.Spacing.sm) {
                // Legend
                HStack(spacing: IkeruTheme.Spacing.md) {
                    legendItem(color: Color.ikeruSecondaryAccent.opacity(0.5), label: "Target", isDashed: true)
                    if viewModel.result != nil {
                        legendItem(color: Color.ikeruPrimaryAccent, label: "Yours", isDashed: false)
                    }
                }

                PitchContourView(
                    targetPattern: target,
                    detectedHighLow: detectedHighLow,
                    moraLabels: moraLabels
                )
            }
        }
    }

    private var detectedHighLow: [Bool]? {
        guard let result = viewModel.result,
              let target = viewModel.targetPattern else { return nil }

        // Derive high/low from detected pattern type and target mora count
        let accentPos: Int
        switch result.detectedPattern {
        case .heiban: accentPos = 0
        case .atamadaka: accentPos = 1
        case .odaka: accentPos = target.moraCount
        case .nakadaka: accentPos = max(2, target.moraCount / 2)
        }

        return PitchAccentPattern.buildMoraHighLow(
            moraCount: target.moraCount,
            accentPosition: accentPos
        )
    }

    private func legendItem(color: Color, label: String, isDashed: Bool) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            if isDashed {
                // Dashed line representation
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(width: 6, height: 2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 20, height: 2)
            }
            Text(label)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Action Controls

    @ViewBuilder
    private var actionControls: some View {
        if viewModel.result != nil {
            feedbackControls
        } else {
            recordingControls
        }
    }

    private var recordingControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Listen button
            Button {
                Task {
                    await audioService.playTTS(text: reading)
                }
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                    Text("Listen")
                        .font(.ikeruBody)
                }
                .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .buttonStyle(.plain)

            // Record button
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    hapticTrigger.toggle()
                    startRecording()
                }
            } label: {
                recordButton
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnalyzing)

            if viewModel.isAnalyzing {
                ProgressView()
                    .tint(Color.ikeruPrimaryAccent)
            }
        }
    }

    private var recordButton: some View {
        ZStack {
            if isRecording {
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

            Circle()
                .fill(isRecording ? Color.ikeruSecondaryAccent : Color.ikeruPrimaryAccent)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
        }
    }

    private var feedbackControls: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            if let result = viewModel.result {
                // Result badge
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(result.isCorrect ? Color.ikeruSuccess : Color.ikeruSecondaryAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.isCorrect ? "Correct!" : "Not quite")
                            .font(.ikeruHeading3)
                            .foregroundStyle(.white)

                        Text("Detected: \(result.detectedPattern.rawValue)型")
                            .font(.ikeruCaption)
                            .foregroundStyle(.ikeruTextSecondary)
                    }
                }

                // Confidence and timing
                HStack(spacing: IkeruTheme.Spacing.lg) {
                    statBadge(
                        label: "Confidence",
                        value: String(format: "%.0f%%", result.confidence * 100)
                    )
                    statBadge(
                        label: "Analysis",
                        value: "\(result.analysisTimeMs)ms"
                    )
                }
            }

            // Retry button
            Button {
                viewModel.reset()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .ikeruButtonStyle(.primary)
        }
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .fontWeight(.semibold)
            Text(label)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Accuracy Stats

    private var accuracyStats: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Pattern Accuracy")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                ForEach(PitchAccentType.allCases, id: \.rawValue) { type in
                    patternAccuracyBadge(type: type)
                }
            }

            if viewModel.overallAccuracy > 0 {
                Text("Overall: \(String(format: "%.0f%%", viewModel.overallAccuracy * 100))")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }
    }

    private func patternAccuracyBadge(type: PitchAccentType) -> some View {
        let accuracy = viewModel.patternAccuracies[type] ?? 0
        let attempts = viewModel.patternAttempts[type] ?? 0

        return VStack(spacing: 2) {
            Text(type.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)

            if attempts > 0 {
                Text(String(format: "%.0f%%", accuracy * 100))
                    .font(.system(size: 11))
                    .foregroundStyle(accuracy >= 0.7 ? Color.ikeruSuccess : Color.ikeruSecondaryAccent)
            } else {
                Text("--")
                    .font(.system(size: 11))
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .background(Color.ikeruSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
    }

    // MARK: - Recording

    private func startRecording() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Collect samples directly into a buffer via tap
            let bufferSize: AVAudioFrameCount = 4096
            var collectedSamples: [Float] = []

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                collectedSamples.append(contentsOf: samples)
            }

            try engine.start()
            self.audioEngine = engine
            self.isRecording = true
        } catch {
            Logger.audio.error("Failed to start pitch recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Capture samples before removing tap
        // Build PCM buffer from the tap's accumulated data
        inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        recordingPulse = false
        self.audioEngine = nil

        // Record a clean 2-second sample for analysis
        Task {
            await captureAndAnalyze(format: format)
        }
    }

    /// Records a short audio sample and sends it for analysis.
    private func captureAndAnalyze(format: AVAudioFormat) async {
        guard viewModel.targetPattern != nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else { return }

        let sampleRate = recordingFormat.sampleRate
        let totalFrames = AVAudioFrameCount(sampleRate * 2.0)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let buffer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioPCMBuffer, Error>) in
                var collectedSamples: [Float] = []
                let targetCount = Int(totalFrames)
                var resumed = false

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { tapBuffer, _ in
                    guard !resumed else { return }
                    guard let channelData = tapBuffer.floatChannelData else { return }
                    let count = Int(tapBuffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                    collectedSamples.append(contentsOf: samples)

                    if collectedSamples.count >= targetCount {
                        resumed = true
                        inputNode.removeTap(onBus: 0)
                        engine.stop()

                        if let pcmBuffer = Self.buildPCMBuffer(from: collectedSamples, format: recordingFormat) {
                            continuation.resume(returning: pcmBuffer)
                        } else {
                            continuation.resume(throwing: PitchCaptureError.bufferCreationFailed)
                        }
                    }
                }

                do {
                    try engine.start()
                } catch {
                    resumed = true
                    continuation.resume(throwing: error)
                    return
                }

                // Timeout after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !resumed else { return }
                    resumed = true
                    inputNode.removeTap(onBus: 0)
                    engine.stop()

                    if collectedSamples.isEmpty {
                        continuation.resume(throwing: PitchCaptureError.noAudioCaptured)
                    } else if let pcmBuffer = Self.buildPCMBuffer(from: collectedSamples, format: recordingFormat) {
                        continuation.resume(returning: pcmBuffer)
                    } else {
                        continuation.resume(throwing: PitchCaptureError.bufferCreationFailed)
                    }
                }
            }

            await viewModel.analyzeRecording(buffer: buffer)

        } catch {
            Logger.audio.error("Failed to capture audio for pitch analysis: \(error.localizedDescription)")
        }

        // Restore audio session
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }

    /// Assembles collected float samples into an AVAudioPCMBuffer.
    private static func buildPCMBuffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(samples.count)
        guard let dest = pcmBuffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { src in
            dest[0].update(from: src.baseAddress!, count: samples.count)
        }
        return pcmBuffer
    }
}

// MARK: - PitchCaptureError

private enum PitchCaptureError: Error, LocalizedError {
    case noAudioCaptured
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured: "No audio was captured during recording."
        case .bufferCreationFailed: "Failed to create audio buffer from recorded samples."
        }
    }
}

// MARK: - Preview

#Preview("PitchAccentView") {
    let vm = PitchAccentViewModel()
    let audioService = AudioService()
    let speechService = SpeechRecognitionService()

    PitchAccentView(
        viewModel: vm,
        speechService: speechService,
        audioService: audioService,
        moraLabels: ["あ", "め"],
        reading: "あめ"
    )
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
    .task {
        let pattern = PitchAccentPattern.make(moraCount: 2, accentPosition: 1)
        vm.setTarget(pattern: pattern)
    }
}
