import Foundation

/// A single kana character with its romaji reading and group membership.
public struct KanaCharacter: Sendable, Hashable, Identifiable, Codable {
    public let character: String
    public let romaji: String
    public let group: KanaGroup

    public var id: String { character }
    public var script: KanaScript { group.script }

    public init(character: String, romaji: String, group: KanaGroup) {
        self.character = character
        self.romaji = romaji
        self.group = group
    }
}

/// Hiragana vs Katakana.
public enum KanaScript: String, Sendable, CaseIterable, Codable {
    case hiragana
    case katakana
}

/// Kana section: base gojūon, dakuten (voiced), or combined yōon.
public enum KanaSection: String, Sendable, CaseIterable, Codable {
    case base
    case dakuten
    case combined
}
