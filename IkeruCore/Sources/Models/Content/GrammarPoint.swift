import Foundation

/// A grammar point with explanation and examples.
/// This is a plain value type for static content from the SQLite bundle.
public struct GrammarPoint: Sendable, Codable, Identifiable, Equatable {

    /// Unique identifier for the grammar point.
    public let id: Int

    /// JLPT level classification.
    public let jlptLevel: JLPTLevel

    /// Short title describing the grammar point (e.g., "は (Topic Marker)").
    public let title: String

    /// Detailed explanation of the grammar point.
    public let explanation: String

    /// Example sentences demonstrating usage.
    public let examples: [String]

    public init(
        id: Int,
        jlptLevel: JLPTLevel,
        title: String,
        explanation: String,
        examples: [String]
    ) {
        self.id = id
        self.jlptLevel = jlptLevel
        self.title = title
        self.explanation = explanation
        self.examples = examples
    }
}
