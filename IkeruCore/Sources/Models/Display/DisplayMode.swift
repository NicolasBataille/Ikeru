import Foundation

/// Controls overall UI density and reading-aid defaults across the app.
///
/// - `.beginner`: SF Symbols + FR/EN chrome labels, furigana/romaji on by default,
///   glossary popovers expanded, mnemonics in locale, Sakura reading aids on.
/// - `.tatami`: Kanji-first chrome (legacy default), reading aids minimal.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case beginner
    case tatami
}
