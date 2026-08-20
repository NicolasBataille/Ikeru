import Foundation

/// Where a vocabulary word was encountered in the app.
public enum EncounterSource: String, Sendable, Codable, CaseIterable, Identifiable {
    case sakuraChat
    case srsSession
    case readingPassage
    case kanaDrill
    case kanjiStudy

    /// Met in a text the learner brought in themselves.
    ///
    /// ⚠️ A client that predates this case reads an unknown raw value and falls
    /// back to `.sakuraChat` — it will not crash, but it will **misfile** the
    /// encounter. Known and accepted: the alternative was a migration on a
    /// frozen entity, for a label.
    case importedText

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sakuraChat: "Sakura Chat"
        case .srsSession: "SRS Session"
        case .readingPassage: "Reading"
        case .kanaDrill: "Kana Drill"
        case .kanjiStudy: "Kanji Study"
        case .importedText: "Imported Text"
        }
    }

    public var icon: String {
        switch self {
        case .sakuraChat: "bubble.left"
        case .srsSession: "rectangle.stack"
        case .readingPassage: "book"
        case .kanaDrill: "character.hiragana"
        case .kanjiStudy: "character.ja"
        case .importedText: "doc.text"
        }
    }
}
