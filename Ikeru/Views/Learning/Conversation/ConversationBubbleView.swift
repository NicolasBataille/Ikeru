import SwiftUI
import IkeruCore

// MARK: - Message Bubble Chrome
//
// Shared bubble variant used by both ConversationBubbleView (full
// ConversationMessage with corrections/hints/timestamp) and ChatBubbleView
// (plain content string with rich ChatContentParser blocks).
//
// Tatami DA: Rectangle + .sumiCorners; no RoundedRectangle/Capsule.
// companion = encre fill + goldDim corners; user = warm gold fill + primaryAccent corners.

enum MessageBubbleVariant {
    case companion  // left-aligned, encre fill, goldDim sumi marks
    case user       // right-aligned, warm gold fill, primaryAccent sumi marks
}

/// Provides the shared background fill and sumi-corner chrome for chat bubbles.
/// Wrap your content in this view to get the canonical Tatami bubble appearance.
struct MessageBubbleChrome<Content: View>: View {

    let variant: MessageBubbleVariant
    let padding: EdgeInsets
    let sumiInset: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        variant: MessageBubbleVariant,
        padding: EdgeInsets = .init(
            top: IkeruTheme.Spacing.md,
            leading: IkeruTheme.Spacing.md,
            bottom: IkeruTheme.Spacing.md,
            trailing: IkeruTheme.Spacing.md
        ),
        sumiInset: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.padding = padding
        self.sumiInset = sumiInset
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background { backgroundFill }
            .sumiCorners(color: cornerColor, size: 7, weight: 1.1, inset: sumiInset)
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch variant {
        case .companion:
            // Quiet ink fill — matches TatamiRoom .standard
            Rectangle()
                .fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.78))
        case .user:
            // Warmer gold-tinted ink so the sender reads at a glance
            Rectangle()
                .fill(Color(red: 0.122, green: 0.102, blue: 0.071).opacity(0.82))
        }
    }

    private var cornerColor: Color {
        switch variant {
        case .companion: TatamiTokens.goldDim
        case .user: .ikeruPrimaryAccent
        }
    }
}

// MARK: - Conversation Bubble View

/// Full-featured chat bubble for ConversationView: renders corrections,
/// vocabulary hints, timestamp, and furigana-aware text.
/// User messages are right-aligned; assistant messages are left-aligned.
struct ConversationBubbleView: View {

    let message: ConversationMessage
    @AppStorage("ikeru.furigana.enabled") private var furiganaEnabled = true
    @AppStorage("ikeru.furigana.userTouched") private var furiganaUserTouched = false
    @Environment(\.displayMode) private var displayMode
    @State private var selectedHint: VocabularyHint?

    private var effectiveFurigana: Bool {
        ReadingAidResolver(
            mode: displayMode,
            userTouched: furiganaUserTouched,
            storedValue: furiganaEnabled
        ).effective
    }

    private var variant: MessageBubbleVariant {
        message.role == .user ? .user : .companion
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            MessageBubbleChrome(variant: variant) {
                VStack(alignment: bubbleAlignment, spacing: IkeruTheme.Spacing.sm) {
                    messageContent
                    correctionsSection
                    vocabularySection
                    timestampLabel
                }
            }
            .sheet(item: $selectedHint) { hint in
                VocabularyDetailSheet(
                    hint: hint,
                    contextSnippet: message.content
                )
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            KanaRubyText(
                message.content,
                textColor: textColor,
                showFurigana: effectiveFurigana
            )
        } else {
            Text(message.content)
                .font(.ikeruBody)
                .foregroundStyle(textColor)
                .multilineTextAlignment(message.role == .user ? .trailing : .leading)
        }
    }

    // MARK: - Corrections

    @ViewBuilder
    private var correctionsSection: some View {
        if !message.corrections.isEmpty {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                ForEach(message.corrections) { correction in
                    CorrectionItemView(correction: correction)
                }
            }
        }
    }

    // MARK: - Vocabulary Hints

    @ViewBuilder
    private var vocabularySection: some View {
        if !message.vocabularyHints.isEmpty {
            IkeruFlowLayout(spacing: IkeruTheme.Spacing.xs) {
                ForEach(message.vocabularyHints) { hint in
                    VocabularyChipView(hint: hint) {
                        selectedHint = hint
                    }
                }
            }
        }
    }

    // MARK: - Timestamp

    private var timestampLabel: some View {
        Text(message.timestamp, style: .time)
            .font(.ikeruCaption)
            .foregroundStyle(.white.opacity(0.4))
    }

    // MARK: - Styling

    private var bubbleAlignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return .white
        case .assistant:
            return Color(hex: IkeruTheme.Colors.kanjiText)
        case .system:
            return .ikeruTextSecondary
        }
    }
}

// MARK: - Correction Item View

private struct CorrectionItemView: View {

    let correction: Correction

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                Text(correction.original)
                    .strikethrough()
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent).opacity(0.8))

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.ikeruTextSecondary)

                Text(correction.corrected)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.success))
            }
            .font(.ikeruCaption)

            if !correction.explanation.isEmpty {
                Text(correction.explanation)
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
        .padding(IkeruTheme.Spacing.sm)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
    }
}

// MARK: - Vocabulary Chip View

private struct VocabularyChipView: View {

    let hint: VocabularyHint
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                if !hint.reading.isEmpty {
                    Text(hint.reading)
                        .ikeruScaledFont(10, relativeTo: .caption2)
                        .foregroundStyle(.ikeruTextSecondary)
                }

                Text(hint.word)
                    .font(.ikeruCaption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
            }
            .padding(.horizontal, IkeruTheme.Spacing.sm)
            .padding(.vertical, IkeruTheme.Spacing.xs)
            .background(
                Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.12)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.3),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Conversation Bubbles") {
    ScrollView {
        VStack(spacing: IkeruTheme.Spacing.md) {
            ConversationBubbleView(
                message: ConversationMessage(
                    role: .user,
                    content: "こんにちは！今日はいい天気ですね。"
                )
            )

            ConversationBubbleView(
                message: ConversationMessage(
                    role: .assistant,
                    content: "こんにちは！はい、とてもいい天気(てんき)ですね。何(なに)をしましたか？",
                    corrections: [
                        Correction(
                            original: "天気がいい",
                            corrected: "いい天気",
                            explanation: "Adjective before noun is more natural here"
                        )
                    ],
                    vocabularyHints: [
                        VocabularyHint(word: "散歩", reading: "さんぽ", meaning: "walk"),
                        VocabularyHint(word: "公園", reading: "こうえん", meaning: "park")
                    ]
                )
            )
        }
        .padding(IkeruTheme.Spacing.md)
    }
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
