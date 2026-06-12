import SwiftUI
import IkeruCore

// MARK: - ChatBubbleVariant

enum ChatBubbleVariant {
    case companion
    case user
}

// MARK: - ChatBubbleView

/// Chat bubble that renders companion messages (warm tint, left-aligned)
/// and user messages (glass, right-aligned) with inline content embeds.
struct ChatBubbleView: View {

    let content: String
    let variant: ChatBubbleVariant
    @AppStorage("ikeru.furigana.enabled") private var furiganaEnabled = true
    @AppStorage("ikeru.furigana.userTouched") private var furiganaUserTouched = false
    @Environment(\.displayMode) private var displayMode

    private var effectiveFurigana: Bool {
        ReadingAidResolver(
            mode: displayMode,
            userTouched: furiganaUserTouched,
            storedValue: furiganaEnabled
        ).effective
    }

    // MARK: - Body

    var body: some View {
        HStack {
            if variant == .user { Spacer(minLength: 48) }

            VStack(alignment: alignment, spacing: IkeruTheme.Spacing.xs) {
                richContentView
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm + 2)
            .background { bubbleBackground }
            // inset: 0 keeps sumi marks flush with the bubble edge so they
            // never overflow into the scroll view's leading margin and get
            // clipped — fixes the leading-character clip in CompanionChatSheet.
            .sumiCorners(color: cornerColor, size: 7, weight: 1.1, inset: 0)

            if variant == .companion { Spacer(minLength: 48) }
        }
        // Ensure the HStack fills the available container width so the
        // companion bubble always anchors to the leading edge.
        .frame(maxWidth: .infinity)
    }

    // MARK: - Alignment

    private var alignment: HorizontalAlignment {
        variant == .companion ? .leading : .trailing
    }

    // MARK: - Background

    @ViewBuilder
    private var bubbleBackground: some View {
        switch variant {
        case .companion:
            // Quiet ink fill (matches TatamiRoom .standard).
            Rectangle()
                .fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.78))
        case .user:
            // Warmer gold-tinted ink so the sender reads at a glance.
            Rectangle()
                .fill(Color(red: 0.122, green: 0.102, blue: 0.071).opacity(0.82))
        }
    }

    // MARK: - Corner Color

    private var cornerColor: Color {
        switch variant {
        case .companion: return TatamiTokens.goldDim
        case .user: return .ikeruPrimaryAccent
        }
    }

    // MARK: - Rich Content

    @ViewBuilder
    private var richContentView: some View {
        let blocks = ChatContentParser.parse(content)

        VStack(alignment: alignment, spacing: IkeruTheme.Spacing.xs) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: ChatContentBlock) -> some View {
        switch block {
        case .text(let text):
            KanaRubyText(
                text,
                textColor: textColor,
                showFurigana: variant == .companion && effectiveFurigana
            )

        case .kanji(let character):
            InlineKanjiView(character: character)

        case .mnemonic(let character, let hint):
            InlineMnemonicView(character: character, hint: hint)

        case .quiz(let character, let correctAnswer, let options):
            InlineQuizView(
                character: character,
                correctAnswer: correctAnswer,
                options: options
            )
        }
    }

    // MARK: - Text Color

    private var textColor: Color {
        switch variant {
        case .companion:
            return Color(hex: IkeruTheme.Colors.kanjiText)
        case .user:
            return .white
        }
    }
}

// MARK: - Preview

#Preview("ChatBubbleView") {
    ScrollView {
        VStack(spacing: IkeruTheme.Spacing.md) {
            ChatBubbleView(
                content: "こんにちは! Let me teach you about [KANJI:食] today.",
                variant: .companion
            )

            ChatBubbleView(
                content: "Yes, I'd like to learn that kanji!",
                variant: .user
            )

            ChatBubbleView(
                content: "Here's a memory trick: [MNEMONIC:食|A person eating from a tray under a roof]",
                variant: .companion
            )

            ChatBubbleView(
                content: "Now test yourself: [QUIZ:食|to eat|to drink|to read]",
                variant: .companion
            )
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .background(Color(hex: IkeruTheme.Colors.background))
    .preferredColorScheme(.dark)
}
