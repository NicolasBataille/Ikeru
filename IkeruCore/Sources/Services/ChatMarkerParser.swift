import Foundation
import os

// MARK: - Chat Marker Parse Result

/// The outcome of parsing a raw AI reply for `[CORRECTION: ...]` /
/// `[VOCAB: ...]` sentinel markers: the cleaned prose plus whatever
/// structured corrections/hints were recognized.
struct ChatMarkerParseResult: Equatable {
    let content: String
    let corrections: [Correction]
    let vocabularyHints: [VocabularyHint]
}

// MARK: - Chat Marker Parser

/// Parses Sakura's raw AI reply text for the two inline sentinel markers
/// (`[CORRECTION: original → corrected | explanation]` and
/// `[VOCAB: word(reading) = meaning]`) and strips them from the
/// user-visible content.
///
/// Tolerant of common formatting drift: a marker is recognized anywhere in
/// the text — inline, mid-line, or several per line — not just when it is
/// the entire trimmed line. Separators accept both ASCII and fullwidth
/// variants (arrows, pipes, equals signs, colons, parentheses) with or
/// without surrounding whitespace, and the tag name is matched
/// case-insensitively.
///
/// Every recognized sentinel span (tag `CORRECTION` or `VOCAB`,
/// case-insensitive) is ALWAYS removed from `content` — even when its inner
/// text fails to parse (e.g. no arrow) — so raw marker syntax never leaks to
/// the learner. Non-sentinel bracketed text (`[laughs]`, `[1]`, ...) is left
/// completely untouched.
///
/// `internal` rather than `private` so it can be unit-tested directly
/// without a mock AI provider — mirrors how `ConversationService.buildPrompt`
/// was made `internal` for direct unit testing.
enum ChatMarkerParser {

    // MARK: - Recognized Separators

    /// Arrow variants accepted between original/corrected text in a
    /// `[CORRECTION: ...]` marker. Split occurs on the FIRST match.
    private static let arrowVariants = ["→", "->", "⇒", "=>"]

    /// Pipe variants separating the optional explanation in a
    /// `[CORRECTION: ...]` marker. Split occurs on the FIRST match.
    private static let pipeVariants = ["|", "｜"]

    /// Equals-sign variants separating word/reading from meaning in a
    /// `[VOCAB: ...]` marker. Split occurs on the FIRST match.
    private static let equalsVariants = ["=", "＝"]

    /// Opening/closing parenthesis variants around a VOCAB reading.
    private static let openParens: Set<Character> = ["(", "（"]
    private static let closeParens: Set<Character> = [")", "）"]

    /// Matches any `[TAG: inner]` span where `TAG` is one or more ASCII
    /// letters and the colon is ASCII or fullwidth, with optional whitespace
    /// around both. `inner` never crosses a `]`, matching the task's
    /// guarantee that marker inner text never contains a closing bracket —
    /// so this never over-matches across two adjacent markers.
    ///
    /// Built fresh per call (rather than cached as a static) because
    /// `Regex` with capture groups is not `Sendable` under Swift 6 strict
    /// concurrency, so it cannot safely live in shared static state; regex
    /// literals compile once at build time, so this has no runtime parsing
    /// cost.
    private static var markerRegex: Regex<(Substring, Substring, Substring)> {
        /\[\s*([A-Za-z]+)\s*[:：]([^\]]*)\]/
    }

    // MARK: - Public API

    /// Parses `text` for CORRECTION/VOCAB sentinel markers anywhere in the
    /// string (inline or on their own line, single or multiple per line).
    static func parse(_ text: String) -> ChatMarkerParseResult {
        var corrections: [Correction] = []
        var vocabularyHints: [VocabularyHint] = []
        var strippedContent = text

        // Process matches in reverse so removing an earlier-found span's
        // range doesn't invalidate the string indices of matches still
        // pending removal.
        let matches = text.matches(of: markerRegex)
        for match in matches.reversed() {
            let tag = String(match.output.1)
            let inner = String(match.output.2)

            switch tag.uppercased() {
            case "CORRECTION":
                if let correction = parseCorrection(inner) {
                    corrections.insert(correction, at: 0)
                } else {
                    Logger.ai.debug("ChatMarkerParser: unparseable CORRECTION marker, dropping from content: \(inner)")
                }
                strippedContent.removeSubrange(match.range)
            case "VOCAB":
                if let hint = parseVocabularyHint(inner) {
                    vocabularyHints.insert(hint, at: 0)
                } else {
                    Logger.ai.debug("ChatMarkerParser: unparseable VOCAB marker, dropping from content: \(inner)")
                }
                strippedContent.removeSubrange(match.range)
            default:
                // Not a recognized sentinel tag (e.g. "[laughs]", "[NOTE: ...]") — leave untouched.
                break
            }
        }

        return ChatMarkerParseResult(
            content: cleanedContent(from: strippedContent),
            corrections: corrections,
            vocabularyHints: vocabularyHints
        )
    }

    // MARK: - Content Cleanup

    /// Collapses the whitespace/blank-line residue left behind after marker
    /// removal so `content` reads as natural prose: runs of spaces/tabs
    /// collapse to one, lines that became empty are dropped, and the result
    /// is trimmed. Intra-prose newlines that were never part of a marker
    /// line are preserved.
    private static func cleanedContent(from text: String) -> String {
        let lines = text
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    // MARK: - CORRECTION Parsing

    /// Parses `original → corrected | explanation` (explanation optional).
    /// Splits on the FIRST arrow and, within the remainder, the FIRST pipe.
    /// Returns `nil` when no arrow variant is present — the marker is then
    /// unparseable and simply dropped from `content` by the caller.
    private static func parseCorrection(_ inner: String) -> Correction? {
        guard let arrowRange = firstRange(of: arrowVariants, in: inner) else { return nil }

        let original = String(inner[inner.startIndex..<arrowRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let afterArrow = inner[arrowRange.upperBound...]

        let corrected: String
        let explanation: String
        if let pipeRange = firstRange(of: pipeVariants, in: afterArrow) {
            corrected = String(afterArrow[afterArrow.startIndex..<pipeRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            explanation = String(afterArrow[pipeRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            corrected = String(afterArrow).trimmingCharacters(in: .whitespaces)
            explanation = ""
        }

        return Correction(original: original, corrected: corrected, explanation: explanation)
    }

    // MARK: - VOCAB Parsing

    /// Parses `word(reading) = meaning` (reading optional). Splits on the
    /// FIRST equals-sign variant. Returns `nil` when no equals variant is
    /// present — the marker is then unparseable and simply dropped from
    /// `content` by the caller.
    private static func parseVocabularyHint(_ inner: String) -> VocabularyHint? {
        guard let equalsRange = firstRange(of: equalsVariants, in: inner) else { return nil }

        let wordPart = String(inner[inner.startIndex..<equalsRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let meaning = String(inner[equalsRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        let (word, reading) = extractReading(from: wordPart)
        return VocabularyHint(word: word, reading: reading, meaning: meaning)
    }

    /// Splits `word(reading)` into its parts. Parens may be ASCII or
    /// fullwidth. Returns the whole string as `word` with an empty
    /// `reading` when no paren pair is present.
    private static func extractReading(from wordPart: String) -> (word: String, reading: String) {
        guard let openIndex = wordPart.firstIndex(where: { openParens.contains($0) }) else {
            return (wordPart, "")
        }
        let afterOpen = wordPart.index(after: openIndex)
        guard let closeIndex = wordPart[afterOpen...].firstIndex(where: { closeParens.contains($0) }) else {
            return (wordPart, "")
        }

        let word = String(wordPart[wordPart.startIndex..<openIndex]).trimmingCharacters(in: .whitespaces)
        let reading = String(wordPart[afterOpen..<closeIndex]).trimmingCharacters(in: .whitespaces)
        return (word, reading)
    }

    // MARK: - Separator Search

    /// Finds the earliest occurrence, across all `variants`, of any matching
    /// substring in `text`. Used to split on the FIRST separator regardless
    /// of which accepted variant it is.
    private static func firstRange(of variants: [String], in text: Substring) -> Range<String.Index>? {
        variants
            .compactMap { text.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func firstRange(of variants: [String], in text: String) -> Range<String.Index>? {
        firstRange(of: variants, in: text[text.startIndex...])
    }
}
