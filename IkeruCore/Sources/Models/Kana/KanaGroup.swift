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
    // Full data for the 92 base kana (46 hiragana + 46 katakana).
    // Dakuten and yōon groups are scaffolded as empty arrays for now.
    // TODO: populate dakuten (g/z/d/b/p) and yōon (kya/sha/...) for both scripts.
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
    ]

    /// All 92 base kana across both scripts.
    public static var allBaseCharacters: [KanaCharacter] {
        KanaGroup.allCases
            .filter { $0.section == .base }
            .flatMap { $0.characters }
    }
}
