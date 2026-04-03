import Foundation

// MARK: - PitchAccentType

/// The four standard Japanese pitch accent pattern types.
public enum PitchAccentType: String, Codable, Sendable, CaseIterable {
    /// Flat pattern (accent position 0) — low first mora, then all high.
    case heiban = "平板"

    /// Head-high pattern (accent position 1) — high first mora, then all low.
    case atamadaka = "頭高"

    /// Middle-high pattern (accent position 2+) — pitch drops after an interior mora.
    case nakadaka = "中高"

    /// Tail-high pattern (accent position n) — pitch drops after the final mora (on particles).
    case odaka = "尾高"

    /// Japanese label with 型 suffix for display (e.g. "頭高型").
    public var displayLabel: String {
        rawValue + "型"
    }
}

// MARK: - PitchAccentPattern

/// Describes the expected pitch accent pattern for a Japanese word.
public struct PitchAccentPattern: Sendable, Equatable {
    /// The classified pattern type.
    public let type: PitchAccentType

    /// Number of morae in the word.
    public let moraCount: Int

    /// The accent nucleus position (0 = heiban, 1 = atamadaka, 2..n-1 = nakadaka, n = odaka).
    public let accentPosition: Int

    /// Per-mora pitch: `true` = high, `false` = low.
    public let moraHighLow: [Bool]

    public init(
        type: PitchAccentType,
        moraCount: Int,
        accentPosition: Int,
        moraHighLow: [Bool]
    ) {
        self.type = type
        self.moraCount = moraCount
        self.accentPosition = accentPosition
        self.moraHighLow = moraHighLow
    }

    /// Convenience factory that derives `moraHighLow` from accent position and mora count.
    /// Follows the standard Tokyo-dialect pitch rules.
    public static func make(
        moraCount: Int,
        accentPosition: Int
    ) -> PitchAccentPattern {
        let type = classifyType(moraCount: moraCount, accentPosition: accentPosition)
        let moraHighLow = buildMoraHighLow(moraCount: moraCount, accentPosition: accentPosition)
        return PitchAccentPattern(
            type: type,
            moraCount: moraCount,
            accentPosition: accentPosition,
            moraHighLow: moraHighLow
        )
    }

    /// Classifies accent position into one of the four pattern types.
    public static func classifyType(
        moraCount: Int,
        accentPosition: Int
    ) -> PitchAccentType {
        switch accentPosition {
        case 0:
            return .heiban
        case 1:
            return .atamadaka
        case moraCount:
            return .odaka
        default:
            return .nakadaka
        }
    }

    /// Builds the high/low array from accent position using standard Tokyo-dialect rules:
    /// - First mora is low unless atamadaka (accent position 1).
    /// - Pitch rises after mora 1 and drops after the accent position.
    static func buildMoraHighLow(moraCount: Int, accentPosition: Int) -> [Bool] {
        guard moraCount > 0 else { return [] }

        var result = [Bool](repeating: false, count: moraCount)

        if accentPosition == 0 {
            // Heiban: low-high-high-high...
            result[0] = false
            for i in 1..<moraCount {
                result[i] = true
            }
        } else if accentPosition == 1 {
            // Atamadaka: high-low-low-low...
            result[0] = true
            for i in 1..<moraCount {
                result[i] = false
            }
        } else {
            // Nakadaka or Odaka: low then high until accent, then low
            result[0] = false
            for i in 1..<moraCount {
                result[i] = i < accentPosition
            }
        }

        return result
    }
}

// MARK: - PitchAccentResult

/// The result of analyzing a learner's pitch accent against a target pattern.
public struct PitchAccentResult: Sendable, Equatable {
    /// The pattern detected from the learner's audio.
    public let detectedPattern: PitchAccentType

    /// The expected target pattern.
    public let targetPattern: PitchAccentType

    /// Whether the detected pattern matches the target.
    public let isCorrect: Bool

    /// Confidence of the detection (0.0 to 1.0).
    public let confidence: Double

    /// Normalized F0 contour values extracted from the audio.
    public let f0Contour: [Double]

    /// Time taken for analysis in milliseconds.
    public let analysisTimeMs: Int

    public init(
        detectedPattern: PitchAccentType,
        targetPattern: PitchAccentType,
        isCorrect: Bool,
        confidence: Double,
        f0Contour: [Double],
        analysisTimeMs: Int
    ) {
        self.detectedPattern = detectedPattern
        self.targetPattern = targetPattern
        self.isCorrect = isCorrect
        self.confidence = confidence
        self.f0Contour = f0Contour
        self.analysisTimeMs = analysisTimeMs
    }
}
