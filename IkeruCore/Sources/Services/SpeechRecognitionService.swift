#if canImport(Speech)
import Speech
import AVFoundation
import Observation
import os

// MARK: - SpeechPermissionStatus

/// The combined permission status for microphone and speech recognition.
public enum SpeechPermissionStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

// MARK: - SpeechRecognitionResult

/// The result of a completed speech recognition session.
public struct SpeechRecognitionResult: Sendable, Equatable {
    /// The final transcribed text.
    public let text: String

    /// Whether the result is final (not a partial result).
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

// MARK: - SpeechRecognitionService

/// Manages on-device speech recognition for Japanese using SFSpeechRecognizer.
/// Observable service that drives UI state for recording controls.
@Observable
@MainActor
public final class SpeechRecognitionService {

    // MARK: - Observable State

    /// Whether the service is currently recording audio.
    public private(set) var isRecording: Bool = false

    /// The currently recognized text (updates with partial results).
    public private(set) var recognizedText: String = ""

    /// The combined permission status for microphone and speech recognition.
    public private(set) var permissionStatus: SpeechPermissionStatus = .notDetermined

    /// Whether on-device recognition is available for Japanese.
    public private(set) var isOnDeviceAvailable: Bool = false

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastRecognitionResult: SpeechRecognitionResult?

    // MARK: - Init

    public init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        updateOnDeviceAvailability()
    }

    // MARK: - Availability

    private func updateOnDeviceAvailability() {
        isOnDeviceAvailable = speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Permissions

    /// Requests both speech recognition and microphone permissions.
    /// - Returns: True if both permissions are authorized.
    public func requestAuthorization() async -> Bool {
        let speechAuthorized = await requestSpeechAuthorization()
        let micAuthorized = await requestMicrophonePermission()

        if speechAuthorized && micAuthorized {
            permissionStatus = .authorized
            return true
        }

        if !speechAuthorized || !micAuthorized {
            permissionStatus = .denied
        }

        return false
    }

    /// Checks current permission status without requesting.
    public func checkPermissionStatus() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        #if os(iOS)
        let micStatus = AVAudioApplication.shared.recordPermission

        switch (speechStatus, micStatus) {
        case (.authorized, .granted):
            permissionStatus = .authorized
        case (.notDetermined, _), (_, .undetermined):
            permissionStatus = .notDetermined
        case (.restricted, _):
            permissionStatus = .restricted
        default:
            permissionStatus = .denied
        }
        #else
        switch speechStatus {
        case .authorized:
            permissionStatus = .authorized
        case .notDetermined:
            permissionStatus = .notDetermined
        case .restricted:
            permissionStatus = .restricted
        default:
            permissionStatus = .denied
        }
        #endif
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        await AVAudioApplication.requestRecordPermission()
        #else
        true
        #endif
    }

    // MARK: - Recording

    /// Starts recording audio and performing speech recognition.
    /// - Throws: An error if the audio engine or recognition request cannot be configured.
    public func startRecording() async throws {
        guard !isRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            Logger.audio.error("Speech recognizer is not available")
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Cancel any existing task
        stopRecognitionTask()

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Configure audio session for recording
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            Logger.audio.error("Invalid audio format — sample rate is 0")
            throw SpeechRecognitionError.audioEngineError
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recognizedText = ""
        self.lastRecognitionResult = nil
        self.isRecording = true

        Logger.audio.info("Speech recognition started (on-device: \(request.requiresOnDeviceRecognition))")

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.recognizedText = text
                    self.lastRecognitionResult = SpeechRecognitionResult(
                        text: text,
                        isFinal: result.isFinal
                    )

                    if result.isFinal {
                        Logger.audio.debug("Final recognition result: \(text.prefix(50))")
                    }
                }

                if let error {
                    Logger.audio.error("Recognition error: \(error.localizedDescription)")
                    self.stopRecordingInternal()
                }
            }
        }
    }

    /// Stops recording and returns the final recognition result.
    /// - Returns: The speech recognition result with the transcribed text.
    public func stopRecording() -> SpeechRecognitionResult {
        let result = lastRecognitionResult ?? SpeechRecognitionResult(
            text: recognizedText,
            isFinal: true
        )
        stopRecordingInternal()
        Logger.audio.info("Speech recognition stopped — result: \(result.text.prefix(50))")
        return result
    }

    // MARK: - Private Helpers

    private func stopRecordingInternal() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        stopRecognitionTask()

        isRecording = false

        // Restore audio session for playback
        restoreAudioSession()
    }

    private func stopRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func restoreAudioSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
            try audioSession.setActive(true)
            Logger.audio.debug("Audio session restored to playback mode")
        } catch {
            Logger.audio.error("Failed to restore audio session: \(error.localizedDescription)")
        }
        #endif
    }

    /// Tears down resources. Call when the service is no longer needed.
    public func tearDown() {
        if isRecording {
            _ = stopRecording()
        }
    }
}

// MARK: - SpeechRecognitionError

/// Errors that can occur during speech recognition.
public enum SpeechRecognitionError: Error, Sendable {
    case recognizerUnavailable
    case audioEngineError
    case permissionDenied
}

// MARK: - Environment Key

#if canImport(SwiftUI)
import SwiftUI

private struct SpeechRecognitionServiceKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: SpeechRecognitionService? = nil
}

extension EnvironmentValues {
    public var speechRecognitionService: SpeechRecognitionService? {
        get { self[SpeechRecognitionServiceKey.self] }
        set { self[SpeechRecognitionServiceKey.self] = newValue }
    }
}
#endif

#endif
