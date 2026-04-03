import Foundation
import os

// MARK: - VolumeDetecting Protocol

/// Abstraction for detecting system volume and mute state.
/// Inject this protocol to decouple audio monitoring from business logic.
public protocol VolumeDetecting: Sendable {
    /// Whether the system volume is effectively muted (volume < 0.01).
    var isMuted: Bool { get }

    /// Current system output volume (0.0 to 1.0).
    var currentVolume: Float { get }

    /// Begin observing system volume changes.
    func startMonitoring()

    /// Stop observing system volume changes and release resources.
    func stopMonitoring()
}

// MARK: - SystemVolumeDetector (AVAudioSession-backed)

#if os(iOS) || os(tvOS)
import AVFoundation

/// Monitors system output volume via AVAudioSession KVO.
/// Must be used from the main actor to safely publish observed values.
@MainActor
public final class SystemVolumeDetector: NSObject, VolumeDetecting, @unchecked Sendable {

    /// Threshold below which volume is considered muted.
    private static let muteThreshold: Float = 0.01

    public private(set) var isMuted: Bool = false
    public private(set) var currentVolume: Float = 0

    private var isObserving = false
    private let audioSession = AVAudioSession.sharedInstance()
    /// Tracks in-flight KVO dispatch tasks so they can be cancelled on stop.
    private var observationTask: Task<Void, Never>?

    override public init() {
        super.init()
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        guard !isObserving else { return }

        do {
            try audioSession.setActive(true)
        } catch {
            Logger.audio.error("Failed to activate audio session: \(error.localizedDescription)")
        }

        let volume = audioSession.outputVolume
        currentVolume = volume
        isMuted = volume < Self.muteThreshold

        audioSession.addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new],
            context: nil
        )
        isObserving = true

        Logger.audio.debug("Volume monitoring started — volume=\(volume), muted=\(self.isMuted)")
    }

    public func stopMonitoring() {
        guard isObserving else { return }
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false
        observationTask?.cancel()
        observationTask = nil
        Logger.audio.debug("Volume monitoring stopped")
    }

    // MARK: - KVO

    override public nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "outputVolume",
              let newVolume = change?[.newKey] as? Float else {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.isObserving else { return }
            self.currentVolume = newVolume
            self.isMuted = newVolume < Self.muteThreshold
            Logger.audio.debug("Volume changed: \(newVolume), muted=\(self.isMuted)")
        }
        // Store task reference on main actor for cancellation
        Task { @MainActor [weak self] in
            self?.observationTask = task
        }
    }
}
#endif

// MARK: - MockVolumeDetector (for testing)

/// A test double for VolumeDetecting that allows manual control of volume state.
public final class MockVolumeDetector: VolumeDetecting, @unchecked Sendable {

    public private(set) var isMuted: Bool
    public private(set) var currentVolume: Float
    public private(set) var isMonitoring: Bool = false

    public init(volume: Float = 0.5) {
        self.currentVolume = volume
        self.isMuted = volume < 0.01
    }

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    /// Simulates a volume change for testing.
    public func simulateVolumeChange(to volume: Float) {
        currentVolume = volume
        isMuted = volume < 0.01
    }
}
