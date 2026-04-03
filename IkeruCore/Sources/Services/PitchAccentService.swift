import AVFoundation
import Accelerate
import os

// MARK: - PitchAccentAnalyzer Protocol

/// Analyzes audio buffers to detect Japanese pitch accent patterns.
public protocol PitchAccentAnalyzer: Sendable {
    /// Analyzes pitch accent from an audio buffer against a target pattern.
    /// - Parameters:
    ///   - audioBuffer: The recorded PCM audio buffer.
    ///   - targetPattern: The expected pitch accent pattern.
    /// - Returns: The analysis result including detected pattern and confidence.
    func analyzePitch(
        audioBuffer: AVAudioPCMBuffer,
        targetPattern: PitchAccentPattern
    ) async -> PitchAccentResult

    /// Extracts the fundamental frequency (F0) contour from an audio buffer.
    /// - Parameter buffer: The PCM audio buffer to analyze.
    /// - Returns: An array of F0 values in Hz, one per analysis frame.
    func extractF0Contour(from buffer: AVAudioPCMBuffer) -> [Double]
}

// MARK: - PitchAccentService

/// On-device pitch accent analysis using autocorrelation-based F0 extraction.
/// Processes PCM audio to detect fundamental frequency contours and classify
/// them into Japanese pitch accent pattern types.
public final class PitchAccentService: PitchAccentAnalyzer, Sendable {

    // MARK: - Configuration

    /// Minimum F0 for Japanese speech (Hz).
    private let minF0: Double = 75.0

    /// Maximum F0 for Japanese speech (Hz).
    private let maxF0: Double = 500.0

    /// Analysis window duration in seconds (~30ms).
    private let windowDuration: Double = 0.03

    /// Frame hop duration in seconds (~10ms).
    private let hopDuration: Double = 0.01

    /// Minimum confidence threshold to consider a frame voiced.
    private let voicedThreshold: Double = 0.3

    /// Minimum number of voiced frames needed for valid analysis.
    private let minVoicedFrames: Int = 5

    // MARK: - Init

    public init() {}

    // MARK: - PitchAccentAnalyzer

    public func analyzePitch(
        audioBuffer: AVAudioPCMBuffer,
        targetPattern: PitchAccentPattern
    ) async -> PitchAccentResult {
        let startTime = ContinuousClock.now

        let f0Contour = extractF0Contour(from: audioBuffer)

        guard targetPattern.moraCount > 0 else {
            Logger.audio.error("Invalid target pattern: moraCount is 0")
            let elapsed = startTime.duration(to: .now)
            let ms = max(0, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            return PitchAccentResult(
                detectedPattern: .heiban,
                targetPattern: targetPattern.type,
                isCorrect: false,
                confidence: 0.0,
                f0Contour: f0Contour,
                analysisTimeMs: ms
            )
        }

        guard f0Contour.count >= minVoicedFrames else {
            Logger.audio.warning("Insufficient voiced frames for pitch analysis: \(f0Contour.count)")
            let elapsed = startTime.duration(to: .now)
            let ms = max(0, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            return PitchAccentResult(
                detectedPattern: .heiban,
                targetPattern: targetPattern.type,
                isCorrect: false,
                confidence: 0.0,
                f0Contour: f0Contour,
                analysisTimeMs: ms
            )
        }

        let normalizedContour = normalizeContour(f0Contour)
        let moraContour = segmentIntoMorae(
            contour: normalizedContour,
            moraCount: targetPattern.moraCount
        )
        let moraHighLow = classifyHighLow(moraContour: moraContour)
        let (detectedType, confidence) = classifyPattern(
            moraHighLow: moraHighLow,
            moraCount: moraHighLow.count
        )

        let isCorrect = detectedType == targetPattern.type

        let elapsed = startTime.duration(to: .now)
        let ms = max(0, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))

        Logger.audio.debug(
            "Pitch analysis complete: detected=\(detectedType.rawValue), target=\(targetPattern.type.rawValue), correct=\(isCorrect), confidence=\(String(format: "%.2f", confidence)), time=\(ms)ms"
        )

        return PitchAccentResult(
            detectedPattern: detectedType,
            targetPattern: targetPattern.type,
            isCorrect: isCorrect,
            confidence: confidence,
            f0Contour: f0Contour,
            analysisTimeMs: ms
        )
    }

    public func extractF0Contour(from buffer: AVAudioPCMBuffer) -> [Double] {
        guard let channelData = buffer.floatChannelData else {
            Logger.audio.error("No float channel data in audio buffer")
            return []
        }

        let sampleRate = Double(buffer.format.sampleRate)
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        guard !samples.isEmpty else { return [] }

        let windowSize = Int(windowDuration * sampleRate)
        let hopSize = Int(hopDuration * sampleRate)

        guard windowSize > 0, hopSize > 0, windowSize <= frameCount else { return [] }

        // Precompute Hanning window
        let hanningWindow = makeHanningWindow(size: windowSize)

        // Compute autocorrelation-based F0 for each frame
        let minLag = Int(sampleRate / maxF0)
        let maxLag = Int(sampleRate / minF0)

        var f0Values: [Double] = []

        var frameStart = 0
        while frameStart + windowSize <= frameCount {
            let f0 = estimateF0ForFrame(
                samples: samples,
                frameStart: frameStart,
                windowSize: windowSize,
                hanningWindow: hanningWindow,
                minLag: minLag,
                maxLag: min(maxLag, windowSize - 1),
                sampleRate: sampleRate
            )

            if let f0 {
                f0Values.append(f0)
            }

            frameStart += hopSize
        }

        return f0Values
    }

    // MARK: - F0 Estimation

    /// Estimates F0 for a single frame using autocorrelation.
    private func estimateF0ForFrame(
        samples: [Float],
        frameStart: Int,
        windowSize: Int,
        hanningWindow: [Float],
        minLag: Int,
        maxLag: Int,
        sampleRate: Double
    ) -> Double? {
        guard maxLag > minLag, minLag >= 0, maxLag < windowSize else { return nil }

        // Apply Hanning window
        var windowed = [Float](repeating: 0, count: windowSize)
        for i in 0..<windowSize {
            windowed[i] = samples[frameStart + i] * hanningWindow[i]
        }

        // Check energy — skip silent frames
        var energy: Float = 0
        vDSP_dotpr(windowed, 1, windowed, 1, &energy, vDSP_Length(windowSize))
        let rmsEnergy = sqrt(energy / Float(windowSize))
        guard rmsEnergy > 0.01 else { return nil }

        // Compute normalized autocorrelation for lag range
        var bestLag = minLag
        var bestCorrelation: Float = -1.0

        // Compute autocorrelation at lag 0 for normalization
        var r0: Float = 0
        vDSP_dotpr(windowed, 1, windowed, 1, &r0, vDSP_Length(windowSize))
        guard r0 > 0 else { return nil }

        for lag in minLag...maxLag {
            let overlapLength = windowSize - lag
            guard overlapLength > 0 else { continue }

            var correlation: Float = 0
            vDSP_dotpr(
                windowed, 1,
                Array(windowed[lag..<windowSize]), 1,
                &correlation,
                vDSP_Length(overlapLength)
            )

            // Normalize
            var rLag: Float = 0
            let shifted = Array(windowed[lag..<windowSize])
            vDSP_dotpr(shifted, 1, shifted, 1, &rLag, vDSP_Length(overlapLength))

            let normalizer = sqrt(r0 * rLag)
            guard normalizer > 0 else { continue }

            let normalizedCorrelation = correlation / normalizer

            if normalizedCorrelation > bestCorrelation {
                bestCorrelation = normalizedCorrelation
                bestLag = lag
            }
        }

        // Voiced threshold check
        guard bestCorrelation > Float(voicedThreshold) else { return nil }

        let f0 = sampleRate / Double(bestLag)
        return f0
    }

    /// Creates a Hanning window of the given size.
    private func makeHanningWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return window
    }

    // MARK: - Contour Processing

    /// Normalizes the F0 contour to relative values (0.0 = min, 1.0 = max).
    func normalizeContour(_ contour: [Double]) -> [Double] {
        guard !contour.isEmpty else { return [] }

        let minVal = contour.min() ?? 0
        let maxVal = contour.max() ?? 0
        let range = maxVal - minVal

        guard range > 1.0 else {
            // Flat contour
            return contour.map { _ in 0.5 }
        }

        return contour.map { ($0 - minVal) / range }
    }

    /// Segments the contour into per-mora averages.
    func segmentIntoMorae(contour: [Double], moraCount: Int) -> [Double] {
        guard moraCount > 0, !contour.isEmpty else { return [] }

        let framesPerMora = max(1, contour.count / moraCount)
        var moraAverages: [Double] = []

        for i in 0..<moraCount {
            let startFrame = i * framesPerMora
            let endFrame = min((i + 1) * framesPerMora, contour.count)

            guard startFrame < contour.count else {
                moraAverages.append(moraAverages.last ?? 0.5)
                continue
            }

            let slice = Array(contour[startFrame..<endFrame])
            let average = slice.reduce(0, +) / Double(slice.count)
            moraAverages.append(average)
        }

        return moraAverages
    }

    /// Classifies each mora as high or low based on the median threshold.
    func classifyHighLow(moraContour: [Double]) -> [Bool] {
        guard !moraContour.isEmpty else { return [] }

        let sorted = moraContour.sorted()
        let median = sorted[sorted.count / 2]

        return moraContour.map { $0 >= median }
    }

    /// Classifies the high/low pattern into a PitchAccentType.
    /// Returns the type and a confidence score.
    func classifyPattern(
        moraHighLow: [Bool],
        moraCount: Int
    ) -> (PitchAccentType, Double) {
        guard moraHighLow.count >= 2 else {
            return (.heiban, 0.3)
        }

        let firstHigh = moraHighLow[0]
        let secondHigh = moraHighLow.count > 1 ? moraHighLow[1] : false

        // Atamadaka: first mora high, rest low
        if firstHigh && !secondHigh {
            let lowCount = moraHighLow.dropFirst().filter { !$0 }.count
            let confidence = Double(lowCount) / Double(moraHighLow.count - 1)
            return (.atamadaka, max(0.4, confidence))
        }

        // First mora should be low for heiban, nakadaka, odaka
        if !firstHigh {
            // Find where pitch drops
            var dropIndex: Int?
            for i in 1..<moraHighLow.count {
                if moraHighLow[i - 1] && !moraHighLow[i] {
                    dropIndex = i
                    break
                }
            }

            if let drop = dropIndex {
                if drop >= moraCount {
                    // Odaka: drops after final mora
                    return (.odaka, 0.7)
                } else if drop == moraCount - 1 || drop >= 2 {
                    // Nakadaka: drops in the middle
                    return (.nakadaka, 0.7)
                }
            }

            // No drop detected — heiban (low-high-high...)
            let highCount = moraHighLow.dropFirst().filter { $0 }.count
            let confidence = Double(highCount) / Double(max(1, moraHighLow.count - 1))
            return (.heiban, max(0.4, confidence))
        }

        // Fallback: if first is high and second is also high, likely heiban
        // with noisy first mora
        return (.heiban, 0.3)
    }
}
