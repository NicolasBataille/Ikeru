import Foundation

/// A directed edge in the kanji knowledge graph: radical -> kanji.
/// Represents the relationship "this radical is a component of this kanji."
public struct KanjiRadicalEdge: Sendable, Codable, Identifiable, Equatable {

    /// The radical character (source node).
    public let radicalCharacter: String

    /// The kanji character (target node).
    public let kanjiCharacter: String

    /// Identifiable: combines radical and kanji for a unique edge ID.
    public var id: String { "\(radicalCharacter)\u{2192}\(kanjiCharacter)" }

    public init(radicalCharacter: String, kanjiCharacter: String) {
        self.radicalCharacter = radicalCharacter
        self.kanjiCharacter = kanjiCharacter
    }
}
