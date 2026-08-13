import Foundation

/// All kana groups across hiragana and katakana, base/dakuten/yōon sections.
public enum KanaGroup: String, Sendable, CaseIterable, Codable, Identifiable {
    // Hiragana base (gojūon)
    case hVowels, hK, hS, hT, hN, hH, hM, hY, hR, hWN
    // Hiragana dakuten
    case hG, hZ, hD, hB, hP
    // Hiragana yōon
    case hKY, hSH, hCH, hNY, hHY, hMY, hRY, hGY, hJ, hBY, hPY
    // Katakana base
    case kVowels, kK, kS, kT, kN, kH, kM, kY, kR, kWN
    // Katakana dakuten
    case kG, kZ, kD, kB, kP
    // Katakana yōon
    case kKY, kSH, kCH, kNY, kHY, kMY, kRY, kGY, kJ, kBY, kPY

    public var id: String { rawValue }

    public var script: KanaScript {
        rawValue.hasPrefix("h") ? .hiragana : .katakana
    }

    public var section: KanaSection {
        switch self {
        case .hVowels, .hK, .hS, .hT, .hN, .hH, .hM, .hY, .hR, .hWN,
             .kVowels, .kK, .kS, .kT, .kN, .kH, .kM, .kY, .kR, .kWN:
            return .base
        case .hG, .hZ, .hD, .hB, .hP,
             .kG, .kZ, .kD, .kB, .kP:
            return .dakuten
        default:
            return .combined
        }
    }

    public var displayName: String {
        switch self {
        case .hVowels, .kVowels: return "Voyelles"
        case .hK, .kK: return "Groupe K"
        case .hS, .kS: return "Groupe S"
        case .hT, .kT: return "Groupe T"
        case .hN, .kN: return "Groupe N"
        case .hH, .kH: return "Groupe H"
        case .hM, .kM: return "Groupe M"
        case .hY, .kY: return "Groupe Y"
        case .hR, .kR: return "Groupe R"
        case .hWN, .kWN: return "Groupe W/N"
        case .hG, .kG: return "Groupe G"
        case .hZ, .kZ: return "Groupe Z"
        case .hD, .kD: return "Groupe D"
        case .hB, .kB: return "Groupe B"
        case .hP, .kP: return "Groupe P"
        case .hKY, .kKY: return "Groupe KY"
        case .hSH, .kSH: return "Groupe SH"
        case .hCH, .kCH: return "Groupe CH"
        case .hNY, .kNY: return "Groupe NY"
        case .hHY, .kHY: return "Groupe HY"
        case .hMY, .kMY: return "Groupe MY"
        case .hRY, .kRY: return "Groupe RY"
        case .hGY, .kGY: return "Groupe GY"
        case .hJ, .kJ: return "Groupe J"
        case .hBY, .kBY: return "Groupe BY"
        case .hPY, .kPY: return "Groupe PY"
        }
    }

    public var characters: [KanaCharacter] {
        KanaGroup.characterTable[self] ?? []
    }

    // MARK: - Character Table
    //
    // Full data for the 92 base kana (46 hiragana + 46 katakana), plus their
    // dakuten (voiced) and yōon (combined digraph) extensions. `allBaseCharacters`
    // below intentionally only covers the .base section — dakuten/yōon groups
    // are additional content, not part of the beginner "X / 92" completion goal.
    private static let characterTable: [KanaGroup: [KanaCharacter]] = [
        // MARK: Hiragana base
        .hVowels: [
            KanaCharacter(character: "あ", romaji: "a", group: .hVowels),
            KanaCharacter(character: "い", romaji: "i", group: .hVowels),
            KanaCharacter(character: "う", romaji: "u", group: .hVowels),
            KanaCharacter(character: "え", romaji: "e", group: .hVowels),
            KanaCharacter(character: "お", romaji: "o", group: .hVowels),
        ],
        .hK: [
            KanaCharacter(character: "か", romaji: "ka", group: .hK),
            KanaCharacter(character: "き", romaji: "ki", group: .hK),
            KanaCharacter(character: "く", romaji: "ku", group: .hK),
            KanaCharacter(character: "け", romaji: "ke", group: .hK),
            KanaCharacter(character: "こ", romaji: "ko", group: .hK),
        ],
        .hS: [
            KanaCharacter(character: "さ", romaji: "sa", group: .hS),
            KanaCharacter(character: "し", romaji: "shi", group: .hS),
            KanaCharacter(character: "す", romaji: "su", group: .hS),
            KanaCharacter(character: "せ", romaji: "se", group: .hS),
            KanaCharacter(character: "そ", romaji: "so", group: .hS),
        ],
        .hT: [
            KanaCharacter(character: "た", romaji: "ta", group: .hT),
            KanaCharacter(character: "ち", romaji: "chi", group: .hT),
            KanaCharacter(character: "つ", romaji: "tsu", group: .hT),
            KanaCharacter(character: "て", romaji: "te", group: .hT),
            KanaCharacter(character: "と", romaji: "to", group: .hT),
        ],
        .hN: [
            KanaCharacter(character: "な", romaji: "na", group: .hN),
            KanaCharacter(character: "に", romaji: "ni", group: .hN),
            KanaCharacter(character: "ぬ", romaji: "nu", group: .hN),
            KanaCharacter(character: "ね", romaji: "ne", group: .hN),
            KanaCharacter(character: "の", romaji: "no", group: .hN),
        ],
        .hH: [
            KanaCharacter(character: "は", romaji: "ha", group: .hH),
            KanaCharacter(character: "ひ", romaji: "hi", group: .hH),
            KanaCharacter(character: "ふ", romaji: "fu", group: .hH),
            KanaCharacter(character: "へ", romaji: "he", group: .hH),
            KanaCharacter(character: "ほ", romaji: "ho", group: .hH),
        ],
        .hM: [
            KanaCharacter(character: "ま", romaji: "ma", group: .hM),
            KanaCharacter(character: "み", romaji: "mi", group: .hM),
            KanaCharacter(character: "む", romaji: "mu", group: .hM),
            KanaCharacter(character: "め", romaji: "me", group: .hM),
            KanaCharacter(character: "も", romaji: "mo", group: .hM),
        ],
        .hY: [
            KanaCharacter(character: "や", romaji: "ya", group: .hY),
            KanaCharacter(character: "ゆ", romaji: "yu", group: .hY),
            KanaCharacter(character: "よ", romaji: "yo", group: .hY),
        ],
        .hR: [
            KanaCharacter(character: "ら", romaji: "ra", group: .hR),
            KanaCharacter(character: "り", romaji: "ri", group: .hR),
            KanaCharacter(character: "る", romaji: "ru", group: .hR),
            KanaCharacter(character: "れ", romaji: "re", group: .hR),
            KanaCharacter(character: "ろ", romaji: "ro", group: .hR),
        ],
        .hWN: [
            KanaCharacter(character: "わ", romaji: "wa", group: .hWN),
            KanaCharacter(character: "を", romaji: "wo", group: .hWN),
            KanaCharacter(character: "ん", romaji: "n", group: .hWN),
        ],

        // MARK: Hiragana dakuten
        .hG: [
            KanaCharacter(character: "が", romaji: "ga", group: .hG),
            KanaCharacter(character: "ぎ", romaji: "gi", group: .hG),
            KanaCharacter(character: "ぐ", romaji: "gu", group: .hG),
            KanaCharacter(character: "げ", romaji: "ge", group: .hG),
            KanaCharacter(character: "ご", romaji: "go", group: .hG),
        ],
        .hZ: [
            KanaCharacter(character: "ざ", romaji: "za", group: .hZ),
            KanaCharacter(character: "じ", romaji: "ji", group: .hZ),
            KanaCharacter(character: "ず", romaji: "zu", group: .hZ),
            KanaCharacter(character: "ぜ", romaji: "ze", group: .hZ),
            KanaCharacter(character: "ぞ", romaji: "zo", group: .hZ),
        ],
        .hD: [
            KanaCharacter(character: "だ", romaji: "da", group: .hD),
            KanaCharacter(character: "ぢ", romaji: "ji", group: .hD),
            KanaCharacter(character: "づ", romaji: "zu", group: .hD),
            KanaCharacter(character: "で", romaji: "de", group: .hD),
            KanaCharacter(character: "ど", romaji: "do", group: .hD),
        ],
        .hB: [
            KanaCharacter(character: "ば", romaji: "ba", group: .hB),
            KanaCharacter(character: "び", romaji: "bi", group: .hB),
            KanaCharacter(character: "ぶ", romaji: "bu", group: .hB),
            KanaCharacter(character: "べ", romaji: "be", group: .hB),
            KanaCharacter(character: "ぼ", romaji: "bo", group: .hB),
        ],
        .hP: [
            KanaCharacter(character: "ぱ", romaji: "pa", group: .hP),
            KanaCharacter(character: "ぴ", romaji: "pi", group: .hP),
            KanaCharacter(character: "ぷ", romaji: "pu", group: .hP),
            KanaCharacter(character: "ぺ", romaji: "pe", group: .hP),
            KanaCharacter(character: "ぽ", romaji: "po", group: .hP),
        ],

        // MARK: Hiragana yōon
        .hKY: [
            KanaCharacter(character: "きゃ", romaji: "kya", group: .hKY),
            KanaCharacter(character: "きゅ", romaji: "kyu", group: .hKY),
            KanaCharacter(character: "きょ", romaji: "kyo", group: .hKY),
        ],
        .hSH: [
            KanaCharacter(character: "しゃ", romaji: "sha", group: .hSH),
            KanaCharacter(character: "しゅ", romaji: "shu", group: .hSH),
            KanaCharacter(character: "しょ", romaji: "sho", group: .hSH),
        ],
        .hCH: [
            KanaCharacter(character: "ちゃ", romaji: "cha", group: .hCH),
            KanaCharacter(character: "ちゅ", romaji: "chu", group: .hCH),
            KanaCharacter(character: "ちょ", romaji: "cho", group: .hCH),
        ],
        .hNY: [
            KanaCharacter(character: "にゃ", romaji: "nya", group: .hNY),
            KanaCharacter(character: "にゅ", romaji: "nyu", group: .hNY),
            KanaCharacter(character: "にょ", romaji: "nyo", group: .hNY),
        ],
        .hHY: [
            KanaCharacter(character: "ひゃ", romaji: "hya", group: .hHY),
            KanaCharacter(character: "ひゅ", romaji: "hyu", group: .hHY),
            KanaCharacter(character: "ひょ", romaji: "hyo", group: .hHY),
        ],
        .hMY: [
            KanaCharacter(character: "みゃ", romaji: "mya", group: .hMY),
            KanaCharacter(character: "みゅ", romaji: "myu", group: .hMY),
            KanaCharacter(character: "みょ", romaji: "myo", group: .hMY),
        ],
        .hRY: [
            KanaCharacter(character: "りゃ", romaji: "rya", group: .hRY),
            KanaCharacter(character: "りゅ", romaji: "ryu", group: .hRY),
            KanaCharacter(character: "りょ", romaji: "ryo", group: .hRY),
        ],
        .hGY: [
            KanaCharacter(character: "ぎゃ", romaji: "gya", group: .hGY),
            KanaCharacter(character: "ぎゅ", romaji: "gyu", group: .hGY),
            KanaCharacter(character: "ぎょ", romaji: "gyo", group: .hGY),
        ],
        .hJ: [
            KanaCharacter(character: "じゃ", romaji: "ja", group: .hJ),
            KanaCharacter(character: "じゅ", romaji: "ju", group: .hJ),
            KanaCharacter(character: "じょ", romaji: "jo", group: .hJ),
        ],
        .hBY: [
            KanaCharacter(character: "びゃ", romaji: "bya", group: .hBY),
            KanaCharacter(character: "びゅ", romaji: "byu", group: .hBY),
            KanaCharacter(character: "びょ", romaji: "byo", group: .hBY),
        ],
        .hPY: [
            KanaCharacter(character: "ぴゃ", romaji: "pya", group: .hPY),
            KanaCharacter(character: "ぴゅ", romaji: "pyu", group: .hPY),
            KanaCharacter(character: "ぴょ", romaji: "pyo", group: .hPY),
        ],

        // MARK: Katakana base
        .kVowels: [
            KanaCharacter(character: "ア", romaji: "a", group: .kVowels),
            KanaCharacter(character: "イ", romaji: "i", group: .kVowels),
            KanaCharacter(character: "ウ", romaji: "u", group: .kVowels),
            KanaCharacter(character: "エ", romaji: "e", group: .kVowels),
            KanaCharacter(character: "オ", romaji: "o", group: .kVowels),
        ],
        .kK: [
            KanaCharacter(character: "カ", romaji: "ka", group: .kK),
            KanaCharacter(character: "キ", romaji: "ki", group: .kK),
            KanaCharacter(character: "ク", romaji: "ku", group: .kK),
            KanaCharacter(character: "ケ", romaji: "ke", group: .kK),
            KanaCharacter(character: "コ", romaji: "ko", group: .kK),
        ],
        .kS: [
            KanaCharacter(character: "サ", romaji: "sa", group: .kS),
            KanaCharacter(character: "シ", romaji: "shi", group: .kS),
            KanaCharacter(character: "ス", romaji: "su", group: .kS),
            KanaCharacter(character: "セ", romaji: "se", group: .kS),
            KanaCharacter(character: "ソ", romaji: "so", group: .kS),
        ],
        .kT: [
            KanaCharacter(character: "タ", romaji: "ta", group: .kT),
            KanaCharacter(character: "チ", romaji: "chi", group: .kT),
            KanaCharacter(character: "ツ", romaji: "tsu", group: .kT),
            KanaCharacter(character: "テ", romaji: "te", group: .kT),
            KanaCharacter(character: "ト", romaji: "to", group: .kT),
        ],
        .kN: [
            KanaCharacter(character: "ナ", romaji: "na", group: .kN),
            KanaCharacter(character: "ニ", romaji: "ni", group: .kN),
            KanaCharacter(character: "ヌ", romaji: "nu", group: .kN),
            KanaCharacter(character: "ネ", romaji: "ne", group: .kN),
            KanaCharacter(character: "ノ", romaji: "no", group: .kN),
        ],
        .kH: [
            KanaCharacter(character: "ハ", romaji: "ha", group: .kH),
            KanaCharacter(character: "ヒ", romaji: "hi", group: .kH),
            KanaCharacter(character: "フ", romaji: "fu", group: .kH),
            KanaCharacter(character: "ヘ", romaji: "he", group: .kH),
            KanaCharacter(character: "ホ", romaji: "ho", group: .kH),
        ],
        .kM: [
            KanaCharacter(character: "マ", romaji: "ma", group: .kM),
            KanaCharacter(character: "ミ", romaji: "mi", group: .kM),
            KanaCharacter(character: "ム", romaji: "mu", group: .kM),
            KanaCharacter(character: "メ", romaji: "me", group: .kM),
            KanaCharacter(character: "モ", romaji: "mo", group: .kM),
        ],
        .kY: [
            KanaCharacter(character: "ヤ", romaji: "ya", group: .kY),
            KanaCharacter(character: "ユ", romaji: "yu", group: .kY),
            KanaCharacter(character: "ヨ", romaji: "yo", group: .kY),
        ],
        .kR: [
            KanaCharacter(character: "ラ", romaji: "ra", group: .kR),
            KanaCharacter(character: "リ", romaji: "ri", group: .kR),
            KanaCharacter(character: "ル", romaji: "ru", group: .kR),
            KanaCharacter(character: "レ", romaji: "re", group: .kR),
            KanaCharacter(character: "ロ", romaji: "ro", group: .kR),
        ],
        .kWN: [
            KanaCharacter(character: "ワ", romaji: "wa", group: .kWN),
            KanaCharacter(character: "ヲ", romaji: "wo", group: .kWN),
            KanaCharacter(character: "ン", romaji: "n", group: .kWN),
        ],

        // MARK: Katakana dakuten
        .kG: [
            KanaCharacter(character: "ガ", romaji: "ga", group: .kG),
            KanaCharacter(character: "ギ", romaji: "gi", group: .kG),
            KanaCharacter(character: "グ", romaji: "gu", group: .kG),
            KanaCharacter(character: "ゲ", romaji: "ge", group: .kG),
            KanaCharacter(character: "ゴ", romaji: "go", group: .kG),
        ],
        .kZ: [
            KanaCharacter(character: "ザ", romaji: "za", group: .kZ),
            KanaCharacter(character: "ジ", romaji: "ji", group: .kZ),
            KanaCharacter(character: "ズ", romaji: "zu", group: .kZ),
            KanaCharacter(character: "ゼ", romaji: "ze", group: .kZ),
            KanaCharacter(character: "ゾ", romaji: "zo", group: .kZ),
        ],
        .kD: [
            KanaCharacter(character: "ダ", romaji: "da", group: .kD),
            KanaCharacter(character: "ヂ", romaji: "ji", group: .kD),
            KanaCharacter(character: "ヅ", romaji: "zu", group: .kD),
            KanaCharacter(character: "デ", romaji: "de", group: .kD),
            KanaCharacter(character: "ド", romaji: "do", group: .kD),
        ],
        .kB: [
            KanaCharacter(character: "バ", romaji: "ba", group: .kB),
            KanaCharacter(character: "ビ", romaji: "bi", group: .kB),
            KanaCharacter(character: "ブ", romaji: "bu", group: .kB),
            KanaCharacter(character: "ベ", romaji: "be", group: .kB),
            KanaCharacter(character: "ボ", romaji: "bo", group: .kB),
        ],
        .kP: [
            KanaCharacter(character: "パ", romaji: "pa", group: .kP),
            KanaCharacter(character: "ピ", romaji: "pi", group: .kP),
            KanaCharacter(character: "プ", romaji: "pu", group: .kP),
            KanaCharacter(character: "ペ", romaji: "pe", group: .kP),
            KanaCharacter(character: "ポ", romaji: "po", group: .kP),
        ],

        // MARK: Katakana yōon
        .kKY: [
            KanaCharacter(character: "キャ", romaji: "kya", group: .kKY),
            KanaCharacter(character: "キュ", romaji: "kyu", group: .kKY),
            KanaCharacter(character: "キョ", romaji: "kyo", group: .kKY),
        ],
        .kSH: [
            KanaCharacter(character: "シャ", romaji: "sha", group: .kSH),
            KanaCharacter(character: "シュ", romaji: "shu", group: .kSH),
            KanaCharacter(character: "ショ", romaji: "sho", group: .kSH),
        ],
        .kCH: [
            KanaCharacter(character: "チャ", romaji: "cha", group: .kCH),
            KanaCharacter(character: "チュ", romaji: "chu", group: .kCH),
            KanaCharacter(character: "チョ", romaji: "cho", group: .kCH),
        ],
        .kNY: [
            KanaCharacter(character: "ニャ", romaji: "nya", group: .kNY),
            KanaCharacter(character: "ニュ", romaji: "nyu", group: .kNY),
            KanaCharacter(character: "ニョ", romaji: "nyo", group: .kNY),
        ],
        .kHY: [
            KanaCharacter(character: "ヒャ", romaji: "hya", group: .kHY),
            KanaCharacter(character: "ヒュ", romaji: "hyu", group: .kHY),
            KanaCharacter(character: "ヒョ", romaji: "hyo", group: .kHY),
        ],
        .kMY: [
            KanaCharacter(character: "ミャ", romaji: "mya", group: .kMY),
            KanaCharacter(character: "ミュ", romaji: "myu", group: .kMY),
            KanaCharacter(character: "ミョ", romaji: "myo", group: .kMY),
        ],
        .kRY: [
            KanaCharacter(character: "リャ", romaji: "rya", group: .kRY),
            KanaCharacter(character: "リュ", romaji: "ryu", group: .kRY),
            KanaCharacter(character: "リョ", romaji: "ryo", group: .kRY),
        ],
        .kGY: [
            KanaCharacter(character: "ギャ", romaji: "gya", group: .kGY),
            KanaCharacter(character: "ギュ", romaji: "gyu", group: .kGY),
            KanaCharacter(character: "ギョ", romaji: "gyo", group: .kGY),
        ],
        .kJ: [
            KanaCharacter(character: "ジャ", romaji: "ja", group: .kJ),
            KanaCharacter(character: "ジュ", romaji: "ju", group: .kJ),
            KanaCharacter(character: "ジョ", romaji: "jo", group: .kJ),
        ],
        .kBY: [
            KanaCharacter(character: "ビャ", romaji: "bya", group: .kBY),
            KanaCharacter(character: "ビュ", romaji: "byu", group: .kBY),
            KanaCharacter(character: "ビョ", romaji: "byo", group: .kBY),
        ],
        .kPY: [
            KanaCharacter(character: "ピャ", romaji: "pya", group: .kPY),
            KanaCharacter(character: "ピュ", romaji: "pyu", group: .kPY),
            KanaCharacter(character: "ピョ", romaji: "pyo", group: .kPY),
        ],
    ]

    /// All 92 base kana across both scripts.
    public static var allBaseCharacters: [KanaCharacter] {
        KanaGroup.allCases
            .filter { $0.section == .base }
            .flatMap { $0.characters }
    }
}
