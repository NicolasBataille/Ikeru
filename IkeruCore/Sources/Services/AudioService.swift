import AVFoundation
import Observation
import os

// MARK: - PlaybackRate

/// Playback speed options for audio exercises.
public enum PlaybackRate: Double, CaseIterable, Sendable, Identifiable {
    case slow = 0.5
    case slower = 0.75
    case normal = 1.0
    case fast = 1.25

    public var id: Double { rawValue }

    /// Maps the playback rate to an AVSpeechUtterance rate value (0.0–1.0 range).
    public var utteranceRate: Float {
        switch self {
        case .slow: 0.3
        case .slower: 0.4
        case .normal: 0.5
        case .fast: 0.6
        }
    }

    /// Human-readable label for display in the UI.
    public var displayLabel: String {
        switch self {
        case .slow: "0.5x"
        case .slower: "0.75x"
        case .normal: "1.0x"
        case .fast: "1.25x"
        }
    }
}

// MARK: - AudioService

/// Manages audio playback for TTS and cached audio files.
/// Observable service that drives UI state for playback controls.
@Observable
@MainActor
public final class AudioService {

    // MARK: - Observable State

    /// Whether audio is currently playing.
    public private(set) var isPlaying: Bool = false

    /// The current playback rate setting.
    public var currentRate: PlaybackRate = .normal

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private nonisolated(unsafe) var interruptionObserver: (any NSObjectProtocol)?

    /// Continuation for awaiting speech completion.
    private var speechCompletionContinuation: CheckedContinuation<Void, Never>?

    /// Continuation for awaiting cached audio completion.
    private var cachedAudioContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    public init() {
        let delegate = SpeechDelegate(
            onDidFinish: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleSpeechFinished()
                }
            },
            onDidCancel: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isPlaying = false
                }
            }
        )
        self.speechDelegate = delegate
        synthesizer.delegate = delegate
        configureAudioSession()
        observeInterruptions()
    }

    // MARK: - Audio Session

    /// Configures AVAudioSession for a learning app with spoken audio.
    private func configureAudioSession() {
        #if os(iOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
            try session.setActive(true)
            Logger.audio.info("Audio session configured for spoken audio playback")
        } catch {
            Logger.audio.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Interruption Handling

    /// Observes audio interruptions (phone calls, other app audio) and pauses/resumes.
    private func observeInterruptions() {
        #if os(iOS) || os(watchOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
        #endif
    }

    #if os(iOS) || os(watchOS)
    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            Logger.audio.info("Audio interruption began — stopping playback")
            stop()
        case .ended:
            Logger.audio.info("Audio interruption ended")
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) {
                configureAudioSession()
                Logger.audio.info("Audio session reactivated after interruption")
            }
        @unknown default:
            break
        }
    }
    #endif

    // MARK: - Speech Completion

    private func handleSpeechFinished() {
        isPlaying = false
        if let continuation = speechCompletionContinuation {
            speechCompletionContinuation = nil
            continuation.resume()
        }
    }

    // MARK: - TTS Playback

    /// Plays Japanese text-to-speech at the specified rate.
    /// - Parameters:
    ///   - text: The Japanese text to speak.
    ///   - language: The BCP 47 language tag (defaults to "ja-JP").
    ///   - rate: The playback speed.
    public func playTTS(
        text: String,
        language: String = "ja-JP",
        rate: PlaybackRate? = nil
    ) async {
        stop()

        let effectiveRate = rate ?? currentRate
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = effectiveRate.utteranceRate
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.5

        isPlaying = true
        synthesizer.speak(utterance)

        Logger.audio.debug("TTS started: text=\(text.prefix(30)), rate=\(effectiveRate.displayLabel)")

        // Wait for speech to complete
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.speechCompletionContinuation = continuation
        }
    }

    // MARK: - Cached Audio Playback

    /// Plays a pre-recorded audio file at the specified rate.
    /// - Parameters:
    ///   - url: The URL of the audio file to play.
    ///   - rate: The playback speed.
    public func playCachedAudio(url: URL, rate: PlaybackRate? = nil) async {
        stop()

        let effectiveRate = rate ?? currentRate

        do {
            let audioFile = try AVAudioFile(forReading: url)

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()

            timePitch.rate = Float(effectiveRate.rawValue)

            engine.attach(playerNode)
            engine.attach(timePitch)

            engine.connect(playerNode, to: timePitch, format: audioFile.processingFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: audioFile.processingFormat)

            self.audioEngine = engine
            self.audioPlayerNode = playerNode
            self.timePitchNode = timePitch

            try engine.start()
            isPlaying = true

            Logger.audio.debug(
                "Cached audio started: url=\(url.lastPathComponent), rate=\(effectiveRate.displayLabel)"
            )

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.cachedAudioContinuation = continuation
                playerNode.scheduleFile(audioFile, at: nil) {
                    Task { @MainActor [weak self] in
                        guard let self, self.cachedAudioContinuation != nil else { return }
                        self.cachedAudioContinuation = nil
                        self.isPlaying = false
                        self.cleanupAudioEngine()
                        continuation.resume()
                    }
                }
                playerNode.play()
            }
        } catch {
            Logger.audio.error("Failed to play cached audio: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    // MARK: - Stop

    /// Stops any in-progress playback (TTS or cached audio).
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        audioPlayerNode?.stop()
        audioEngine?.stop()
        cleanupAudioEngine()

        isPlaying = false

        // Resume any awaiting continuations
        if let continuation = speechCompletionContinuation {
            speechCompletionContinuation = nil
            continuation.resume()
        }
        if let continuation = cachedAudioContinuation {
            cachedAudioContinuation = nil
            continuation.resume()
        }
    }

    // MARK: - Silent Mode Detection

    /// Whether the system volume is effectively muted.
    public var isSilentMode: Bool {
        #if os(iOS) || os(watchOS)
        AVAudioSession.sharedInstance().outputVolume == 0.0
        #else
        false
        #endif
    }

    /// Whether audio exercises should be skipped due to silent mode.
    public var shouldSkipAudioExercises: Bool {
        isSilentMode
    }

    // MARK: - Cleanup

    private func cleanupAudioEngine() {
        audioPlayerNode = nil
        timePitchNode = nil
        audioEngine = nil
    }

    /// Removes the interruption observer. Call when the service is no longer needed.
    public func tearDown() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }
}

// MARK: - SpeechDelegate

/// Separate NSObject delegate to avoid @Observable + NSObject subclass conflict.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onDidFinish: () -> Void
    let onDidCancel: () -> Void

    init(onDidFinish: @escaping () -> Void, onDidCancel: @escaping () -> Void) {
        self.onDidFinish = onDidFinish
        self.onDidCancel = onDidCancel
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onDidFinish()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        onDidCancel()
    }
}

// MARK: - Environment Key

#if canImport(SwiftUI)
import SwiftUI

private struct AudioServiceKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: AudioService? = nil
}

extension EnvironmentValues {
    public var audioService: AudioService? {
        get { self[AudioServiceKey.self] }
        set { self[AudioServiceKey.self] = newValue }
    }
}
#endif
