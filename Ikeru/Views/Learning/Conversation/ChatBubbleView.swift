import SwiftUI
import IkeruCore

// MARK: - ChatBubbleVariant
//
// Typealias kept for source compatibility. `MessageBubbleVariant` (defined in
// ConversationBubbleView.swift) is the canonical enum; ChatBubbleVariant
// mirrors its cases so existing callers compile without changes.

typealias ChatBubbleVariant = MessageBubbleVariant

// MARK: - ChatBubbleView
//
// Chat bubble for CompanionChatSheet. Renders companion/user messages with
// full ChatContentParser block support (kanji cards, mnemonics, quizzes).
// Chrome delegates to MessageBubbleChrome for the shared Tatami appearance.

/// Chat bubble with rich content support (kanji/mnemonic/quiz embeds).
/// Uses MessageBubbleChrome for the canonical Tatami bubble chrome.
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

    private var alignment: HorizontalAlignment {
        variant == .companion ? .leading : .trailing
    }

    // MARK: - Body

    var body: some View {
        HStack {
            if variant == .user { Spacer(minLength: 48) }

            // inset: 0 keeps sumi marks flush with the bubble edge so they
            // never overflow into the scroll view's leading margin and get
            // clipped — fixes the leading-character clip in CompanionChatSheet.
            MessageBubbleChrome(
                variant: variant,
                padding: .init(
                    top: IkeruTheme.Spacing.sm + 2,
                    leading: IkeruTheme.Spacing.md,
                    bottom: IkeruTheme.Spacing.sm + 2,
                    trailing: IkeruTheme.Spacing.md
                ),
                sumiInset: 0
            ) {
                VStack(alignment: alignment, spacing: IkeruTheme.Spacing.xs) {
                    richContentView
                }
            }

            if variant == .companion { Spacer(minLength: 48) }
        }
        // Ensure the HStack fills the available container width so the
        // companion bubble always anchors to the leading edge.
        .frame(maxWidth: .infinity)
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
