import Foundation

/// Where a vocabulary word was encountered in the app.
public enum EncounterSource: String, Sendable, Codable, CaseIterable, Identifiable {
    case sakuraChat
    case srsSession
    case readingPassage
    case kanaDrill
    case kanjiStudy

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sakuraChat: "Sakura Chat"
        case .srsSession: "SRS Session"
        case .readingPassage: "Reading"
        case .kanaDrill: "Kana Drill"
        case .kanjiStudy: "Kanji Study"
        }
    }

    public var icon: String {
        switch self {
        case .sakuraChat: "bubble.left"
        case .srsSession: "rectangle.stack"
        case .readingPassage: "book"
        case .kanaDrill: "character.hiragana"
        case .kanjiStudy: "character.ja"
        }
    }
}
