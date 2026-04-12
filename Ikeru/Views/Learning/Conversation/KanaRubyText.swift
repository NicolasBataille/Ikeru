import SwiftUI
import IkeruCore

// MARK: - KanaRomajiLookup

enum KanaRomajiLookup {

    static let table: [String: String] = {
        var dict: [String: String] = [:]
        for entry in KanaData.all {
            dict[entry.character] = entry.romanization
        }
        return dict
    }()

    static func romaji(for character: String) -> String? {
        table[character]
    }
}

// MARK: - KanaRubyText

/// Renders a Japanese string with pronunciation annotations:
/// - **Kana** get their romaji drawn above (from the static KanaData table)
/// - **Kanji** annotated as `漢字(かんじ)` in the AI response get the hiragana
///   reading drawn above (parsed from the text itself)
/// - Latin/punctuation pass through unchanged
///
/// Set `showFurigana: false` to strip all annotations and render clean text.
struct KanaRubyText: View {

    let content: String
    let textColor: Color
    let showFurigana: Bool
    let baseFont: Font
    let rubyFont: Font
    let rubyColor: Color
    let maxWidth: CGFloat?

    init(
        _ content: String,
        textColor: Color,
        showFurigana: Bool = true,
        maxWidth: CGFloat? = nil,
        baseFont: Font = .ikeruBody,
        rubyFont: Font = .system(size: 9, weight: .medium, design: .rounded),
        rubyColor: Color? = nil
    ) {
        self.content = content
        self.textColor = textColor
        self.showFurigana = showFurigana
        self.maxWidth = maxWidth
        self.baseFont = baseFont
        self.rubyFont = rubyFont
        self.rubyColor = rubyColor ?? textColor.opacity(0.55)
    }

    var body: some View {
        if showFurigana {
            let tokens = Self.tokenize(content)
            KanaRubyFlowLayout(
                spacing: 0,
                maxWidth: maxWidth ?? (UIScreen.main.bounds.width - 120)
            ) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    tokenView(token)
                }
            }
        } else {
            Text(Self.stripReadings(content))
                .font(baseFont)
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private func tokenView(_ token: Token) -> some View {
        switch token {
        case .kana(let character, let romaji):
            VStack(spacing: 0) {
                Text(romaji)
                    .font(rubyFont)
                    .foregroundStyle(rubyColor)
                    .lineLimit(1)
                    .fixedSize()
                Text(character)
                    .font(baseFont)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 0.5)

        case .kanji(let base, let reading):
            VStack(spacing: 0) {
                Text(reading)
                    .font(rubyFont)
                    .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
                Text(base)
                    .font(baseFont)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 0.5)

        case .other(let run):
            VStack(spacing: 0) {
                Text(" ")
                    .font(rubyFont)
                    .lineLimit(1)
                    .hidden()
                Text(run)
                    .font(baseFont)
                    .foregroundStyle(textColor)
            }
        }
    }

    // MARK: - Tokenisation

    enum Token {
        case kana(character: String, romaji: String)
        case kanji(base: String, reading: String)
        case other(String)
    }

    /// Parse a string that may contain:
    /// - Bare kana (annotated via KanaRomajiLookup)
    /// - Kanji with AI-provided readings as `漢字(かんじ)` (only matched when
    ///   the base contains CJK characters and the reading is hiragana/katakana)
    /// - Everything else (Latin, punctuation, spaces)
    static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            tokens.append(.other(buffer))
            buffer = ""
        }

        while i < chars.count {
            let char = chars[i]
            let asString = String(char)

            // Check for kana
            if let romaji = KanaRomajiLookup.romaji(for: asString) {
                flushBuffer()
                tokens.append(.kana(character: asString, romaji: romaji))
                i += 1
                continue
            }

            // Check for CJK character potentially followed by (reading)
            if char.isCJK {
                // Collect consecutive CJK characters
                var kanjiRun = String(char)
                var j = i + 1
                while j < chars.count && chars[j].isCJK {
                    kanjiRun.append(chars[j])
                    j += 1
                }

                // Check if followed by (hiragana/katakana reading)
                if j < chars.count && chars[j] == "(" {
                    if let closeIdx = findMatchingParen(chars, from: j),
                       isJapaneseReading(chars, from: j + 1, to: closeIdx) {
                        flushBuffer()
                        let reading = String(chars[(j + 1)..<closeIdx])
                        tokens.append(.kanji(base: kanjiRun, reading: reading))
                        i = closeIdx + 1
                        continue
                    }
                }

                // No reading annotation — emit as plain text
                buffer.append(kanjiRun)
                i = j
                continue
            }

            // Regular character
            buffer.append(char)
            i += 1
        }
        flushBuffer()
        return tokens
    }

    // MARK: - Strip Readings

    /// Remove `(reading)` annotations after kanji for plain-text display.
    /// English/French parenthetical text like `(Today I watched)` is preserved
    /// because the text before `(` must contain CJK and the content inside must
    /// be hiragana/katakana for removal.
    static func stripReadings(_ input: String) -> String {
        var result = ""
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            if chars[i] == "(" && i > 0 {
                // Check if preceded by CJK
                let prevIdx = i - 1
                if chars[prevIdx].isCJK,
                   let closeIdx = findMatchingParen(chars, from: i),
                   isJapaneseReading(chars, from: i + 1, to: closeIdx) {
                    i = closeIdx + 1
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    // MARK: - Helpers

    private static func findMatchingParen(_ chars: [Character], from openIdx: Int) -> Int? {
        guard openIdx < chars.count && chars[openIdx] == "(" else { return nil }
        var j = openIdx + 1
        while j < chars.count {
            if chars[j] == ")" { return j }
            if chars[j] == "(" { return nil } // nested parens — bail
            j += 1
        }
        return nil
    }

    private static func isJapaneseReading(_ chars: [Character], from start: Int, to end: Int) -> Bool {
        guard start < end else { return false }
        for k in start..<end {
            let c = chars[k]
            guard c.isHiragana || c.isKatakana else { return false }
        }
        return true
    }
}

// MARK: - Character Extensions

extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)    // CJK Unified
            || (0x3400...0x4DBF).contains(scalar.value)    // CJK Extension A
            || (0xF900...0xFAFF).contains(scalar.value)    // CJK Compatibility
    }

    var isHiragana: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x3040...0x309F).contains(scalar.value)
    }

    var isKatakana: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x30A0...0x30FF).contains(scalar.value)
    }
}

// MARK: - KanaRubyFlowLayout

private struct KanaRubyFlowLayout: Layout {

    let spacing: CGFloat
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let size: CGSize
    }

    private func layout(
        subviews: Subviews
    ) -> LayoutResult {
        let maxWidth = self.maxWidth
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: currentY + lineHeight)
        )
    }
}

// MARK: - Preview

#Preview("KanaRubyText — with furigana") {
    VStack(alignment: .leading, spacing: 16) {
        KanaRubyText(
            "こんにちは！元気(げんき)ですか？",
            textColor: .white
        )
        KanaRubyText(
            "今日(きょう)は友達(ともだち)と映画(えいが)を見(み)ました。(Today I watched a movie.)",
            textColor: .white
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("KanaRubyText — furigana OFF") {
    VStack(alignment: .leading, spacing: 16) {
        KanaRubyText(
            "今日(きょう)は友達(ともだち)と映画(えいが)を見(み)ました。(Today I watched a movie.)",
            textColor: .white,
            showFurigana: false
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
