import Foundation

// MARK: - DiffSegment

/// A segment of the diff between expected and recognized text.
public enum DiffSegment: Sendable, Equatable {
    /// Characters that match between expected and recognized.
    case match(String)

    /// Characters where expected differs from what was recognized.
    case mismatch(expected: String, actual: String)

    /// Characters present in expected but missing from recognized.
    case missing(String)

    /// Extra characters in recognized that aren't in expected.
    case extra(String)
}

// MARK: - ShadowingResult

/// The result of scoring a shadowing attempt.
public struct ShadowingResult: Sendable, Equatable {
    /// The text recognized from the learner's speech.
    public let recognizedText: String

    /// The expected target text.
    public let expectedText: String

    /// Accuracy score from 0.0 (no match) to 1.0 (perfect match).
    public let accuracy: Double

    /// Diff segments showing the comparison between expected and recognized.
    public let diffSegments: [DiffSegment]

    public init(
        recognizedText: String,
        expectedText: String,
        accuracy: Double,
        diffSegments: [DiffSegment]
    ) {
        self.recognizedText = recognizedText
        self.expectedText = expectedText
        self.accuracy = accuracy
        self.diffSegments = diffSegments
    }
}

// MARK: - PronunciationScorer

/// Scores pronunciation by comparing recognized speech to expected text.
/// Uses character-level longest common subsequence (LCS) for alignment.
public enum PronunciationScorer {

    // MARK: - Public API

    /// Scores the recognized text against the expected text.
    /// - Parameters:
    ///   - recognized: The text from speech recognition.
    ///   - expected: The target text the learner should have said.
    /// - Returns: A ShadowingResult with accuracy score and diff segments.
    public static func score(recognized: String, expected: String) -> ShadowingResult {
        let normalizedRecognized = normalize(recognized)
        let normalizedExpected = normalize(expected)

        guard !normalizedExpected.isEmpty else {
            return ShadowingResult(
                recognizedText: recognized,
                expectedText: expected,
                accuracy: normalizedRecognized.isEmpty ? 1.0 : 0.0,
                diffSegments: normalizedRecognized.isEmpty ? [] : [.extra(recognized)]
            )
        }

        guard !normalizedRecognized.isEmpty else {
            return ShadowingResult(
                recognizedText: recognized,
                expectedText: expected,
                accuracy: 0.0,
                diffSegments: [.missing(expected)]
            )
        }

        let expectedChars = Array(normalizedExpected)
        let recognizedChars = Array(normalizedRecognized)

        let lcs = longestCommonSubsequence(expectedChars, recognizedChars)
        let accuracy = Double(lcs.count) / Double(expectedChars.count)
        let segments = buildDiffSegments(
            expected: expectedChars,
            recognized: recognizedChars,
            lcs: lcs
        )

        return ShadowingResult(
            recognizedText: recognized,
            expectedText: expected,
            accuracy: min(1.0, max(0.0, accuracy)),
            diffSegments: segments
        )
    }

    // MARK: - Normalization

    /// Normalizes Japanese text for comparison:
    /// - Converts katakana to hiragana
    /// - Strips whitespace and punctuation
    static func normalize(_ text: String) -> String {
        let katakanaToHiragana = text.applyingTransform(
            .init("Katakana-Hiragana"),
            reverse: false
        ) ?? text

        return katakanaToHiragana.filter { char in
            !char.isWhitespace && !char.isPunctuation && !isJapanesePunctuation(char)
        }
    }

    /// Checks if a character is Japanese punctuation.
    private static func isJapanesePunctuation(_ char: Character) -> Bool {
        let japanesePunctuation: Set<Character> = [
            "\u{3001}", // ideographic comma
            "\u{3002}", // ideographic full stop
            "\u{FF0C}", // fullwidth comma
            "\u{FF0E}", // fullwidth full stop
            "\u{300C}", // left corner bracket
            "\u{300D}", // right corner bracket
            "\u{3000}", // ideographic space
            "\u{30FB}", // katakana middle dot
            "\u{FF01}", // fullwidth exclamation
            "\u{FF1F}", // fullwidth question mark
        ]
        return japanesePunctuation.contains(char)
    }

    // MARK: - Longest Common Subsequence

    /// Computes the longest common subsequence of two character arrays.
    /// Returns the LCS characters with their indices in both arrays.
    static func longestCommonSubsequence(
        _ expected: [Character],
        _ recognized: [Character]
    ) -> [(expectedIndex: Int, recognizedIndex: Int, char: Character)] {
        let m = expected.count
        let n = recognized.count

        // Build LCS length table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if expected[i - 1] == recognized[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the actual LCS
        var result: [(expectedIndex: Int, recognizedIndex: Int, char: Character)] = []
        var i = m
        var j = n

        while i > 0 && j > 0 {
            if expected[i - 1] == recognized[j - 1] {
                result.append((expectedIndex: i - 1, recognizedIndex: j - 1, char: expected[i - 1]))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }

    // MARK: - Diff Segments

    /// Builds diff segments from expected, recognized, and LCS alignment.
    static func buildDiffSegments(
        expected: [Character],
        recognized: [Character],
        lcs: [(expectedIndex: Int, recognizedIndex: Int, char: Character)]
    ) -> [DiffSegment] {
        var segments: [DiffSegment] = []
        var expIdx = 0
        var recIdx = 0

        for entry in lcs {
            // Characters before this LCS match in expected are missing
            if expIdx < entry.expectedIndex {
                let missingChars = String(expected[expIdx..<entry.expectedIndex])
                segments.append(.missing(missingChars))
            }

            // Characters before this LCS match in recognized are extra
            if recIdx < entry.recognizedIndex {
                let extraChars = String(recognized[recIdx..<entry.recognizedIndex])
                segments.append(.extra(extraChars))
            }

            // The matched character
            segments.append(.match(String(entry.char)))

            expIdx = entry.expectedIndex + 1
            recIdx = entry.recognizedIndex + 1
        }

        // Remaining characters after last LCS match
        if expIdx < expected.count {
            let remaining = String(expected[expIdx...])
            segments.append(.missing(remaining))
        }
        if recIdx < recognized.count {
            let remaining = String(recognized[recIdx...])
            segments.append(.extra(remaining))
        }

        return mergeAdjacentSegments(segments)
    }

    /// Merges adjacent segments of the same type for cleaner output.
    private static func mergeAdjacentSegments(_ segments: [DiffSegment]) -> [DiffSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [DiffSegment] = []

        for segment in segments {
            guard let last = merged.last else {
                merged.append(segment)
                continue
            }

            switch (last, segment) {
            case (.match(let a), .match(let b)):
                merged[merged.count - 1] = .match(a + b)
            case (.missing(let a), .missing(let b)):
                merged[merged.count - 1] = .missing(a + b)
            case (.extra(let a), .extra(let b)):
                merged[merged.count - 1] = .extra(a + b)
            default:
                merged.append(segment)
            }
        }

        return merged
    }
}
