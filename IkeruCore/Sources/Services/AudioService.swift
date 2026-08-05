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
// AVAudioUnitTimePitch is unavailable on watchOS, and the watch target
// doesn't ship any audio drills — gate the whole service so the package
// builds clean for watchOS while staying available on iOS / macOS.
#if !os(watchOS)

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
    private var cachedAudioPlayer: AVAudioPlayer?
    private var cachedAudioDelegate: CachedAudioDelegate?
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
        self.cachedAudioDelegate = CachedAudioDelegate { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleCachedAudioFinished()
            }
        }
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
        // Prefer a pre-generated, bundled clip (offline, consistent VOICEVOX
        // voice, zero setup). Fall back to on-device synthesis when no clip is
        // bundled for this exact text — so nothing ever goes silent.
        if let bundledURL = BundledAudioLocator.url(for: text) {
            await playCachedAudio(url: bundledURL, rate: rate)
            return
        }

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

        // The shared session is mutated by the recording paths
        // (`SpeechRecognitionService`, the pitch-accent exercise). They each
        // restore `.playback` on the happy path, but a cancelled or crashed
        // recording leaves the category on `.playAndRecord`/`.measurement`,
        // where this playback is inaudible. Re-asserting costs nothing and
        // makes playback independent of whatever ran before it.
        configureAudioSession()

        do {
            // AVAudioPlayer rather than an AVAudioEngine graph: the engine was
            // only ever there to host AVAudioUnitTimePitch for the rate
            // control, which AVAudioPlayer does natively via `enableRate`.
            // The graph also had to negotiate formats — the bundled VOICEVOX
            // clips are 24 kHz mono while device output runs at 48 kHz, and it
            // pinned the mixer connection to the *file's* format. That whole
            // class of failure (format negotiation, node graph, engine
            // lifetime) is silent when it goes wrong: the engine starts, no
            // error is thrown, and nothing is ever rendered — which is exactly
            // what a device pass showed (2026-08-05: no audio at all on an
            // iPhone 14 Pro, healthy `.playback` session, headphones no help).
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = Float(effectiveRate.rawValue)
            player.delegate = cachedAudioDelegate
            guard player.prepareToPlay() else {
                Logger.audio.error("Cached audio: prepareToPlay() failed for \(url.lastPathComponent)")
                isPlaying = false
                return
            }

            self.cachedAudioPlayer = player

            guard player.play() else {
                Logger.audio.error("Cached audio: play() returned false for \(url.lastPathComponent)")
                self.cachedAudioPlayer = nil
                isPlaying = false
                return
            }

            isPlaying = true
            Logger.audio.debug(
                "Cached audio started: url=\(url.lastPathComponent), rate=\(effectiveRate.displayLabel), duration=\(player.duration)s"
            )

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.cachedAudioContinuation = continuation
            }
        } catch {
            Logger.audio.error("Failed to play cached audio: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    /// Called by the player delegate when a cached clip finishes on its own.
    fileprivate func handleCachedAudioFinished() {
        cachedAudioPlayer = nil
        isPlaying = false
        if let continuation = cachedAudioContinuation {
            cachedAudioContinuation = nil
            continuation.resume()
        }
    }

    // MARK: - Stop

    /// Stops any in-progress playback (TTS or cached audio).
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        cachedAudioPlayer?.stop()
        cachedAudioPlayer = nil

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

    // Removed (remediation 7.9): `isSilentMode` / `shouldSkipAudioExercises`
    // used to detect "silent mode" by checking `outputVolume == 0.0`. That's
    // the volume slider, not the physical mute switch — the switch doesn't
    // touch `outputVolume` at all — and playback here runs in `.playback`
    // audio session category, which ignores the mute switch by design anyway.
    // The old skip logic gave callers false confidence that audio would stay
    // silent when it wouldn't. If real mute-switch-aware behavior is wanted
    // later, build on `VolumeDetector`/`SystemVolumeDetector` (KVO-based,
    // already implemented and tested) rather than resurrecting this check.

    // MARK: - Cleanup

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

/// Bridges `AVAudioPlayer`'s completion callback back to the service.
/// Only natural completion resumes the continuation — an interrupted or
/// explicitly stopped clip goes through `stop()`, which resumes it itself.
private final class CachedAudioDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onDidFinish: () -> Void

    init(onDidFinish: @escaping () -> Void) {
        self.onDidFinish = onDidFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onDidFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Logger.audio.error("Cached audio decode error: \(error?.localizedDescription ?? "unknown")")
        onDidFinish()
    }
}

#endif // !os(watchOS) — closes the AudioService gate

// MARK: - Environment Key

#if canImport(SwiftUI) && !os(watchOS)
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
