import Testing
import Foundation
@testable import IkeruCore

@Suite("VolumeDetector — Volume and Mute Detection")
@MainActor
struct VolumeDetectorTests {

    // MARK: - MockVolumeDetector Tests

    @Test("Mock detector reports muted when volume is 0")
    func mutedAtZeroVolume() {
        let detector = MockVolumeDetector(volume: 0)
        #expect(detector.isMuted == true)
        #expect(detector.currentVolume == 0)
    }

    @Test("Mock detector reports not muted when volume is above threshold")
    func notMutedAtNormalVolume() {
        let detector = MockVolumeDetector(volume: 0.5)
        #expect(detector.isMuted == false)
        #expect(detector.currentVolume == 0.5)
    }

    @Test("Mock detector reports muted when volume is below threshold (0.005)")
    func mutedBelowThreshold() {
        let detector = MockVolumeDetector(volume: 0.005)
        #expect(detector.isMuted == true)
    }

    @Test("Mock detector reports not muted at threshold boundary (0.01)")
    func notMutedAtExactThreshold() {
        let detector = MockVolumeDetector(volume: 0.01)
        #expect(detector.isMuted == false)
    }

    @Test("Mock detector tracks monitoring start and stop")
    func monitoringLifecycle() {
        let detector = MockVolumeDetector(volume: 0.5)
        #expect(detector.isMonitoring == false)

        detector.startMonitoring()
        #expect(detector.isMonitoring == true)

        detector.stopMonitoring()
        #expect(detector.isMonitoring == false)
    }

    @Test("simulateVolumeChange updates volume and mute state")
    func volumeChangeSimulation() {
        let detector = MockVolumeDetector(volume: 0.5)
        #expect(detector.isMuted == false)

        detector.simulateVolumeChange(to: 0)
        #expect(detector.isMuted == true)
        #expect(detector.currentVolume == 0)

        detector.simulateVolumeChange(to: 0.8)
        #expect(detector.isMuted == false)
        #expect(detector.currentVolume == 0.8)
    }

    @Test("Default volume is 0.5 and not muted")
    func defaultInitialization() {
        let detector = MockVolumeDetector()
        #expect(detector.currentVolume == 0.5)
        #expect(detector.isMuted == false)
    }

    // SessionConfig Integration tests removed (remediation 7.9):
    // `SessionConfig.isSilentMode` was fed by the same unreliable
    // `outputVolume == 0.0` signal as `AudioService.isSilentMode` (volume
    // slider, not the mute switch) and has been removed along with the
    // exclusion logic in `PlannerService.availableSkills()` that read it.
    // `VolumeDetector`/`MockVolumeDetector` above remain — they're a
    // correctly-implemented, KVO-based mute detector — just not wired to
    // session composition (yet).
}
