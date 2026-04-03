import Foundation

/// A kanji character with its readings, meanings, and structural data.
/// This is a plain value type for static content from the SQLite bundle.
public struct Kanji: Sendable, Codable, Identifiable, Equatable {

    /// The kanji character (e.g., "日").
    public let character: String

    /// Radical characters that compose this kanji.
    public let radicals: [String]

    /// On'yomi (Chinese-derived) readings in katakana.
    public let onReadings: [String]

    /// Kun'yomi (Japanese native) readings in hiragana.
    public let kunReadings: [String]

    /// English meanings.
    public let meanings: [String]

    /// JLPT level classification.
    public let jlptLevel: JLPTLevel

    /// Total number of strokes.
    public let strokeCount: Int

    /// SVG path data for stroke order animation (from KanjiVG). Nil if unavailable.
    public let strokeOrderSVGRef: String?

    /// Identifiable: uses the character as the unique ID.
    public var id: String { character }

    public init(
        character: String,
        radicals: [String],
        onReadings: [String],
        kunReadings: [String],
        meanings: [String],
        jlptLevel: JLPTLevel,
        strokeCount: Int,
        strokeOrderSVGRef: String?
    ) {
        self.character = character
        self.radicals = radicals
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.meanings = meanings
        self.jlptLevel = jlptLevel
        self.strokeCount = strokeCount
        self.strokeOrderSVGRef = strokeOrderSVGRef
    }
}
