import Foundation

/// The type of learning card.
public enum CardType: String, Codable, CaseIterable, Sendable {
    case kanji
    case vocabulary
    case grammar
    case listening
}
