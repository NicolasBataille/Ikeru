import Foundation

/// A radical (kanji component) with its meaning and stroke data.
/// This is a plain value type for static content from the SQLite bundle.
public struct Radical: Sendable, Codable, Identifiable, Equatable {

    /// The radical character (e.g., "一").
    public let character: String

    /// English meaning of the radical.
    public let meaning: String

    /// Total number of strokes.
    public let strokeCount: Int

    /// Identifiable: uses the character as the unique ID.
    public var id: String { character }

    public init(
        character: String,
        meaning: String,
        strokeCount: Int
    ) {
        self.character = character
        self.meaning = meaning
        self.strokeCount = strokeCount
    }
}
