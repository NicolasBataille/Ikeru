import Foundation

/// Static kana dataset for quizzes and drills.
/// Contains all basic hiragana and katakana with romanization.
public enum KanaData {

    /// A single kana entry with its character and reading.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        public let character: String
        public let romanization: String
        public let type: KanaType

        public init(character: String, romanization: String, type: KanaType) {
            self.id = "\(type.rawValue)-\(character)"
            self.character = character
            self.romanization = romanization
            self.type = type
        }
    }

    public enum KanaType: String, Sendable {
        case hiragana
        case katakana
    }

    // MARK: - Hiragana

    public static let hiragana: [Entry] = [
        // Vowels
        Entry(character: "あ", romanization: "a", type: .hiragana),
        Entry(character: "い", romanization: "i", type: .hiragana),
        Entry(character: "う", romanization: "u", type: .hiragana),
        Entry(character: "え", romanization: "e", type: .hiragana),
        Entry(character: "お", romanization: "o", type: .hiragana),
        // K-row
        Entry(character: "か", romanization: "ka", type: .hiragana),
        Entry(character: "き", romanization: "ki", type: .hiragana),
        Entry(character: "く", romanization: "ku", type: .hiragana),
        Entry(character: "け", romanization: "ke", type: .hiragana),
        Entry(character: "こ", romanization: "ko", type: .hiragana),
        // S-row
        Entry(character: "さ", romanization: "sa", type: .hiragana),
        Entry(character: "し", romanization: "shi", type: .hiragana),
        Entry(character: "す", romanization: "su", type: .hiragana),
        Entry(character: "せ", romanization: "se", type: .hiragana),
        Entry(character: "そ", romanization: "so", type: .hiragana),
        // T-row
        Entry(character: "た", romanization: "ta", type: .hiragana),
        Entry(character: "ち", romanization: "chi", type: .hiragana),
        Entry(character: "つ", romanization: "tsu", type: .hiragana),
        Entry(character: "て", romanization: "te", type: .hiragana),
        Entry(character: "と", romanization: "to", type: .hiragana),
        // N-row
        Entry(character: "な", romanization: "na", type: .hiragana),
        Entry(character: "に", romanization: "ni", type: .hiragana),
        Entry(character: "ぬ", romanization: "nu", type: .hiragana),
        Entry(character: "ね", romanization: "ne", type: .hiragana),
        Entry(character: "の", romanization: "no", type: .hiragana),
        // H-row
        Entry(character: "は", romanization: "ha", type: .hiragana),
        Entry(character: "ひ", romanization: "hi", type: .hiragana),
        Entry(character: "ふ", romanization: "fu", type: .hiragana),
        Entry(character: "へ", romanization: "he", type: .hiragana),
        Entry(character: "ほ", romanization: "ho", type: .hiragana),
        // M-row
        Entry(character: "ま", romanization: "ma", type: .hiragana),
        Entry(character: "み", romanization: "mi", type: .hiragana),
        Entry(character: "む", romanization: "mu", type: .hiragana),
        Entry(character: "め", romanization: "me", type: .hiragana),
        Entry(character: "も", romanization: "mo", type: .hiragana),
        // Y-row
        Entry(character: "や", romanization: "ya", type: .hiragana),
        Entry(character: "ゆ", romanization: "yu", type: .hiragana),
        Entry(character: "よ", romanization: "yo", type: .hiragana),
        // R-row
        Entry(character: "ら", romanization: "ra", type: .hiragana),
        Entry(character: "り", romanization: "ri", type: .hiragana),
        Entry(character: "る", romanization: "ru", type: .hiragana),
        Entry(character: "れ", romanization: "re", type: .hiragana),
        Entry(character: "ろ", romanization: "ro", type: .hiragana),
        // W-row + N
        Entry(character: "わ", romanization: "wa", type: .hiragana),
        Entry(character: "を", romanization: "wo", type: .hiragana),
        Entry(character: "ん", romanization: "n", type: .hiragana),
    ]

    // MARK: - Katakana

    public static let katakana: [Entry] = [
        Entry(character: "ア", romanization: "a", type: .katakana),
        Entry(character: "イ", romanization: "i", type: .katakana),
        Entry(character: "ウ", romanization: "u", type: .katakana),
        Entry(character: "エ", romanization: "e", type: .katakana),
        Entry(character: "オ", romanization: "o", type: .katakana),
        Entry(character: "カ", romanization: "ka", type: .katakana),
        Entry(character: "キ", romanization: "ki", type: .katakana),
        Entry(character: "ク", romanization: "ku", type: .katakana),
        Entry(character: "ケ", romanization: "ke", type: .katakana),
        Entry(character: "コ", romanization: "ko", type: .katakana),
        Entry(character: "サ", romanization: "sa", type: .katakana),
        Entry(character: "シ", romanization: "shi", type: .katakana),
        Entry(character: "ス", romanization: "su", type: .katakana),
        Entry(character: "セ", romanization: "se", type: .katakana),
        Entry(character: "ソ", romanization: "so", type: .katakana),
        Entry(character: "タ", romanization: "ta", type: .katakana),
        Entry(character: "チ", romanization: "chi", type: .katakana),
        Entry(character: "ツ", romanization: "tsu", type: .katakana),
        Entry(character: "テ", romanization: "te", type: .katakana),
        Entry(character: "ト", romanization: "to", type: .katakana),
        Entry(character: "ナ", romanization: "na", type: .katakana),
        Entry(character: "ニ", romanization: "ni", type: .katakana),
        Entry(character: "ヌ", romanization: "nu", type: .katakana),
        Entry(character: "ネ", romanization: "ne", type: .katakana),
        Entry(character: "ノ", romanization: "no", type: .katakana),
        Entry(character: "ハ", romanization: "ha", type: .katakana),
        Entry(character: "ヒ", romanization: "hi", type: .katakana),
        Entry(character: "フ", romanization: "fu", type: .katakana),
        Entry(character: "ヘ", romanization: "he", type: .katakana),
        Entry(character: "ホ", romanization: "ho", type: .katakana),
        Entry(character: "マ", romanization: "ma", type: .katakana),
        Entry(character: "ミ", romanization: "mi", type: .katakana),
        Entry(character: "ム", romanization: "mu", type: .katakana),
        Entry(character: "メ", romanization: "me", type: .katakana),
        Entry(character: "モ", romanization: "mo", type: .katakana),
        Entry(character: "ヤ", romanization: "ya", type: .katakana),
        Entry(character: "ユ", romanization: "yu", type: .katakana),
        Entry(character: "ヨ", romanization: "yo", type: .katakana),
        Entry(character: "ラ", romanization: "ra", type: .katakana),
        Entry(character: "リ", romanization: "ri", type: .katakana),
        Entry(character: "ル", romanization: "ru", type: .katakana),
        Entry(character: "レ", romanization: "re", type: .katakana),
        Entry(character: "ロ", romanization: "ro", type: .katakana),
        Entry(character: "ワ", romanization: "wa", type: .katakana),
        Entry(character: "ヲ", romanization: "wo", type: .katakana),
        Entry(character: "ン", romanization: "n", type: .katakana),
    ]

    /// All kana (hiragana + katakana).
    public static let all: [Entry] = hiragana + katakana

    /// Generates a quiz question: one target kana + 3 random distractors from the same type.
    /// - Parameter pool: The kana pool to draw from.
    /// - Returns: A tuple of (target, allChoices) where allChoices is shuffled and includes target.
    public static func generateQuizQuestion(
        from pool: [Entry]
    ) -> (target: Entry, choices: [Entry])? {
        guard pool.count >= 4 else { return nil }
        let target = pool.randomElement()!
        let distractors = pool.filter { $0.id != target.id }.shuffled().prefix(3)
        var choices = Array(distractors) + [target]
        choices.shuffle()
        return (target: target, choices: choices)
    }
}
