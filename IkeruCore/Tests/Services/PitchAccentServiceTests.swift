import Testing
import Foundation
import AVFoundation
@testable import IkeruCore

@Suite("PitchAccentService")
struct PitchAccentServiceTests {

    // MARK: - PitchAccentType Tests

    @Test("PitchAccentType has 4 cases")
    func pitchAccentTypeCount() {
        #expect(PitchAccentType.allCases.count == 4)
    }

    @Test("PitchAccentType raw values are Japanese labels", arguments: [
        (PitchAccentType.heiban, "平板"),
        (PitchAccentType.atamadaka, "頭高"),
        (PitchAccentType.nakadaka, "中高"),
        (PitchAccentType.odaka, "尾高")
    ])
    func pitchAccentTypeRawValues(type: PitchAccentType, expected: String) {
        #expect(type.rawValue == expected)
    }

    @Test("PitchAccentType displayLabel appends 型")
    func pitchAccentTypeDisplayLabel() {
        #expect(PitchAccentType.heiban.displayLabel == "平板型")
        #expect(PitchAccentType.atamadaka.displayLabel == "頭高型")
    }

    // MARK: - PitchAccentPattern Classification

    @Test("classifyType returns heiban for accent position 0")
    func classifyHeiban() {
        let type = PitchAccentPattern.classifyType(moraCount: 3, accentPosition: 0)
        #expect(type == .heiban)
    }

    @Test("classifyType returns atamadaka for accent position 1")
    func classifyAtamadaka() {
        let type = PitchAccentPattern.classifyType(moraCount: 3, accentPosition: 1)
        #expect(type == .atamadaka)
    }

    @Test("classifyType returns nakadaka for accent position between 2 and n-1")
    func classifyNakadaka() {
        let type = PitchAccentPattern.classifyType(moraCount: 4, accentPosition: 2)
        #expect(type == .nakadaka)

        let type2 = PitchAccentPattern.classifyType(moraCount: 5, accentPosition: 3)
        #expect(type2 == .nakadaka)
    }

    @Test("classifyType returns odaka for accent position equal to moraCount")
    func classifyOdaka() {
        let type = PitchAccentPattern.classifyType(moraCount: 3, accentPosition: 3)
        #expect(type == .odaka)
    }

    // MARK: - Mora High/Low Generation

    @Test("buildMoraHighLow for heiban produces low-high-high pattern")
    func heibanMoraHighLow() {
        let result = PitchAccentPattern.buildMoraHighLow(moraCount: 3, accentPosition: 0)
        #expect(result == [false, true, true])
    }

    @Test("buildMoraHighLow for atamadaka produces high-low-low pattern")
    func atamadakaMoraHighLow() {
        let result = PitchAccentPattern.buildMoraHighLow(moraCount: 3, accentPosition: 1)
        #expect(result == [true, false, false])
    }

    @Test("buildMoraHighLow for nakadaka produces low-high-low pattern")
    func nakadakaMoraHighLow() {
        let result = PitchAccentPattern.buildMoraHighLow(moraCount: 3, accentPosition: 2)
        #expect(result == [false, true, false])
    }

    @Test("buildMoraHighLow for odaka produces low-high-high pattern (same shape as heiban)")
    func odakaMoraHighLow() {
        // Odaka for 3 morae with accent at 3: low then high until position 3
        // Mora 0: low, Mora 1: high (1 < 3), Mora 2: high (2 < 3)
        let result = PitchAccentPattern.buildMoraHighLow(moraCount: 3, accentPosition: 3)
        #expect(result == [false, true, true])
    }

    @Test("buildMoraHighLow returns empty for zero morae")
    func emptyMoraHighLow() {
        let result = PitchAccentPattern.buildMoraHighLow(moraCount: 0, accentPosition: 0)
        #expect(result.isEmpty)
    }

    @Test("make factory produces correct pattern")
    func makeFactory() {
        let pattern = PitchAccentPattern.make(moraCount: 2, accentPosition: 1)
        #expect(pattern.type == .atamadaka)
        #expect(pattern.moraCount == 2)
        #expect(pattern.accentPosition == 1)
        #expect(pattern.moraHighLow == [true, false])
    }

    // MARK: - PitchAccentResult Equality

    @Test("PitchAccentResult isCorrect reflects pattern match")
    func resultIsCorrect() {
        let result = PitchAccentResult(
            detectedPattern: .heiban,
            targetPattern: .heiban,
            isCorrect: true,
            confidence: 0.9,
            f0Contour: [100, 200, 200],
            analysisTimeMs: 50
        )
        #expect(result.isCorrect == true)
        #expect(result.detectedPattern == result.targetPattern)
    }

    @Test("PitchAccentResult isCorrect false when patterns differ")
    func resultIsIncorrect() {
        let result = PitchAccentResult(
            detectedPattern: .atamadaka,
            targetPattern: .heiban,
            isCorrect: false,
            confidence: 0.6,
            f0Contour: [200, 100, 100],
            analysisTimeMs: 45
        )
        #expect(result.isCorrect == false)
        #expect(result.detectedPattern != result.targetPattern)
    }

    // MARK: - F0 Contour Extraction from Sine Wave

    @Test("extractF0Contour detects frequency of a sine wave")
    func extractF0FromSineWave() {
        let service = PitchAccentService()
        let sampleRate: Double = 44100
        let frequency: Double = 220.0 // A3
        let duration: Double = 0.5
        let frameCount = Int(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            Issue.record("Failed to create audio format")
            return
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            Issue.record("Failed to create PCM buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                channelData[0][i] = Float(sin(2.0 * .pi * frequency * t) * 0.8)
            }
        }

        let contour = service.extractF0Contour(from: buffer)

        // Should have detected voiced frames
        #expect(contour.count > 5)

        // Detected F0 should be close to 220 Hz (within 20% tolerance)
        let averageF0 = contour.reduce(0, +) / Double(contour.count)
        #expect(averageF0 > frequency * 0.8)
        #expect(averageF0 < frequency * 1.2)
    }

    @Test("extractF0Contour returns empty for silent buffer")
    func extractF0FromSilence() {
        let service = PitchAccentService()
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * 0.1)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            Issue.record("Failed to create audio format/buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Fill with silence (zeros)
        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                channelData[0][i] = 0.0
            }
        }

        let contour = service.extractF0Contour(from: buffer)
        #expect(contour.isEmpty)
    }

    // MARK: - Pattern Classification

    @Test("classifyPattern detects atamadaka from high-low-low")
    func classifyPatternAtamadaka() {
        let service = PitchAccentService()
        let (type, confidence) = service.classifyPattern(
            moraHighLow: [true, false, false],
            moraCount: 3
        )
        #expect(type == .atamadaka)
        #expect(confidence > 0.3)
    }

    @Test("classifyPattern detects heiban from low-high-high")
    func classifyPatternHeiban() {
        let service = PitchAccentService()
        let (type, confidence) = service.classifyPattern(
            moraHighLow: [false, true, true],
            moraCount: 3
        )
        #expect(type == .heiban)
        #expect(confidence > 0.3)
    }

    @Test("classifyPattern detects nakadaka from low-high-low")
    func classifyPatternNakadaka() {
        let service = PitchAccentService()
        let (type, _) = service.classifyPattern(
            moraHighLow: [false, true, false],
            moraCount: 3
        )
        #expect(type == .nakadaka)
    }

    @Test("classifyPattern handles single mora gracefully")
    func classifyPatternSingleMora() {
        let service = PitchAccentService()
        let (type, confidence) = service.classifyPattern(
            moraHighLow: [true],
            moraCount: 1
        )
        #expect(type == .heiban)
        #expect(confidence == 0.3)
    }

    // MARK: - Contour Processing

    @Test("normalizeContour maps to 0-1 range")
    func normalizeContour() {
        let service = PitchAccentService()
        let contour = [100.0, 200.0, 150.0, 300.0]
        let normalized = service.normalizeContour(contour)

        #expect(normalized.count == 4)
        #expect(normalized[0] == 0.0) // min
        #expect(normalized[3] == 1.0) // max

        // 150 should be at 0.25 of the range
        let expected = (150.0 - 100.0) / (300.0 - 100.0)
        #expect(abs(normalized[2] - expected) < 0.01)
    }

    @Test("normalizeContour handles flat input")
    func normalizeContourFlat() {
        let service = PitchAccentService()
        let contour = [200.0, 200.0, 200.0]
        let normalized = service.normalizeContour(contour)

        // All values should be 0.5 for flat contour
        for val in normalized {
            #expect(abs(val - 0.5) < 0.01)
        }
    }

    @Test("normalizeContour returns empty for empty input")
    func normalizeContourEmpty() {
        let service = PitchAccentService()
        let result = service.normalizeContour([])
        #expect(result.isEmpty)
    }

    @Test("segmentIntoMorae averages contour per mora")
    func segmentIntoMorae() {
        let service = PitchAccentService()
        // 8 frames, 2 morae => 4 frames per mora
        let contour = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
        let result = service.segmentIntoMorae(contour: contour, moraCount: 2)

        #expect(result.count == 2)
        // First 4: avg = (0.2+0.3+0.4+0.5)/4 = 0.35
        #expect(abs(result[0] - 0.35) < 0.01)
        // Last 4: avg = (0.6+0.7+0.8+0.9)/4 = 0.75
        #expect(abs(result[1] - 0.75) < 0.01)
    }

    @Test("classifyHighLow uses median threshold")
    func classifyHighLow() {
        let service = PitchAccentService()
        let moraContour = [0.2, 0.8, 0.9]
        let result = service.classifyHighLow(moraContour: moraContour)

        #expect(result == [false, true, true])
    }

    // MARK: - Analysis Timeout

    @Test("analyzePitch completes within 500ms for synthetic buffer")
    func analysisCompletesFast() async {
        let service = PitchAccentService()
        let sampleRate: Double = 44100
        let frequency: Double = 200.0
        let duration: Double = 0.5
        let frameCount = Int(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            Issue.record("Failed to create audio format/buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                channelData[0][i] = Float(sin(2.0 * .pi * frequency * t) * 0.8)
            }
        }

        let target = PitchAccentPattern.make(moraCount: 2, accentPosition: 1)

        let result = await service.analyzePitch(
            audioBuffer: buffer,
            targetPattern: target
        )

        #expect(result.analysisTimeMs < 500)
        #expect(result.f0Contour.count > 0)
    }
}

// MARK: - PitchAccentTracker Tests

@Suite("PitchAccentTracker")
@MainActor
struct PitchAccentTrackerTests {

    @Test("recordResult increments total and correct counts")
    func recordResultTracksCorrectly() async {
        nonisolated(unsafe) let defaults = UserDefaults(suiteName: "test.pitchTracker.\(UUID().uuidString)")!
        let tracker = PitchAccentTracker(defaults: defaults)

        await tracker.recordResult(pattern: .heiban, wasCorrect: true)
        await tracker.recordResult(pattern: .heiban, wasCorrect: true)
        await tracker.recordResult(pattern: .heiban, wasCorrect: false)

        let accuracy = await tracker.accuracy(for: .heiban)
        let attempts = await tracker.totalAttempts(for: .heiban)

        #expect(attempts == 3)
        #expect(abs(accuracy - (2.0 / 3.0)) < 0.01)

        defaults.removePersistentDomain(forName: "test.pitchTracker")
    }

    @Test("accuracy returns 0 for pattern with no attempts")
    func accuracyNoAttempts() async {
        let defaults = UserDefaults(suiteName: "test.pitchTracker.\(UUID().uuidString)")!
        let tracker = PitchAccentTracker(defaults: defaults)

        let accuracy = await tracker.accuracy(for: .nakadaka)
        #expect(accuracy == 0.0)
    }

    @Test("totalAttempts returns 0 for pattern with no attempts")
    func totalAttemptsNoAttempts() async {
        let defaults = UserDefaults(suiteName: "test.pitchTracker.\(UUID().uuidString)")!
        let tracker = PitchAccentTracker(defaults: defaults)

        let attempts = await tracker.totalAttempts(for: .odaka)
        #expect(attempts == 0)
    }

    @Test("overallAccuracy calculates across all patterns")
    func overallAccuracy() async {
        let defaults = UserDefaults(suiteName: "test.pitchTracker.\(UUID().uuidString)")!
        let tracker = PitchAccentTracker(defaults: defaults)

        await tracker.recordResult(pattern: .heiban, wasCorrect: true)
        await tracker.recordResult(pattern: .atamadaka, wasCorrect: false)
        await tracker.recordResult(pattern: .nakadaka, wasCorrect: true)
        await tracker.recordResult(pattern: .odaka, wasCorrect: false)

        let overall = await tracker.overallAccuracy()
        #expect(abs(overall - 0.5) < 0.01)
    }

    @Test("overallAccuracy returns 0 when no attempts")
    func overallAccuracyNoAttempts() async {
        let defaults = UserDefaults(suiteName: "test.pitchTracker.\(UUID().uuidString)")!
        let tracker = PitchAccentTracker(defaults: defaults)

        let overall = await tracker.overallAccuracy()
        #expect(overall == 0.0)
    }

    @Test("reset clears all data")
    func resetClearsData() async {
        let suiteName = "test.pitchTracker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tracker = PitchAccentTracker(defaults: defaults)

        await tracker.recordResult(pattern: .heiban, wasCorrect: true)
        await tracker.recordResult(pattern: .atamadaka, wasCorrect: true)

        await tracker.reset()

        let accuracy = await tracker.accuracy(for: .heiban)
        let attempts = await tracker.totalAttempts(for: .heiban)
        let overall = await tracker.overallAccuracy()

        #expect(accuracy == 0.0)
        #expect(attempts == 0)
        #expect(overall == 0.0)
    }

    @Test("tracker persists data via UserDefaults")
    func persistence() async {
        let suiteName = "test.pitchTracker.\(UUID().uuidString)"
        nonisolated(unsafe) let defaults = UserDefaults(suiteName: suiteName)!

        // Record with first instance
        let tracker1 = PitchAccentTracker(defaults: defaults)
        await tracker1.recordResult(pattern: .heiban, wasCorrect: true)
        await tracker1.recordResult(pattern: .heiban, wasCorrect: true)

        // Create second instance — should load persisted data
        let tracker2 = PitchAccentTracker(defaults: defaults)
        let accuracy = await tracker2.accuracy(for: .heiban)
        let attempts = await tracker2.totalAttempts(for: .heiban)

        #expect(attempts == 2)
        #expect(accuracy == 1.0)
    }
}
