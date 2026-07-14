import Testing
import Foundation
#if !os(watchOS)
import AVFoundation
@testable import IkeruCore

@Suite("AudioService")
struct AudioServiceTests {

    // MARK: - PlaybackRate Tests

    @Test("PlaybackRate slow has value 0.5")
    func playbackRateSlowValue() {
        #expect(PlaybackRate.slow.rawValue == 0.5)
    }

    @Test("PlaybackRate slower has value 0.75")
    func playbackRateSlowerValue() {
        #expect(PlaybackRate.slower.rawValue == 0.75)
    }

    @Test("PlaybackRate normal has value 1.0")
    func playbackRateNormalValue() {
        #expect(PlaybackRate.normal.rawValue == 1.0)
    }

    @Test("PlaybackRate fast has value 1.25")
    func playbackRateFastValue() {
        #expect(PlaybackRate.fast.rawValue == 1.25)
    }

    @Test("PlaybackRate maps to correct utterance rate", arguments: [
        (PlaybackRate.slow, Float(0.3)),
        (PlaybackRate.slower, Float(0.4)),
        (PlaybackRate.normal, Float(0.5)),
        (PlaybackRate.fast, Float(0.6))
    ])
    func playbackRateToUtteranceRate(rate: PlaybackRate, expectedUtteranceRate: Float) {
        #expect(rate.utteranceRate == expectedUtteranceRate)
    }

    @Test("PlaybackRate has correct display labels", arguments: [
        (PlaybackRate.slow, "0.5x"),
        (PlaybackRate.slower, "0.75x"),
        (PlaybackRate.normal, "1.0x"),
        (PlaybackRate.fast, "1.25x")
    ])
    func playbackRateDisplayLabel(rate: PlaybackRate, expectedLabel: String) {
        #expect(rate.displayLabel == expectedLabel)
    }

    @Test("PlaybackRate allCases has 4 cases")
    func playbackRateAllCases() {
        #expect(PlaybackRate.allCases.count == 4)
    }

    // MARK: - AudioService Initialization Tests

    @Test("AudioService initializes with default state")
    @MainActor
    func audioServiceDefaultState() {
        let service = AudioService()
        #expect(service.isPlaying == false)
        #expect(service.currentRate == .normal)
    }

    @Test("AudioService stop sets isPlaying to false")
    @MainActor
    func audioServiceStopSetsNotPlaying() {
        let service = AudioService()
        service.stop()
        #expect(service.isPlaying == false)
    }

    // Silent Mode Detection Tests removed (remediation 7.9):
    // `AudioService.isSilentMode`/`shouldSkipAudioExercises` detected
    // `outputVolume == 0.0` — the volume slider, not the physical mute
    // switch — and were never a reliable signal (TTS in `.playback` category
    // ignores the mute switch anyway). The properties were removed; see the
    // comment left in `AudioService.swift` where they used to live.
}

#endif

