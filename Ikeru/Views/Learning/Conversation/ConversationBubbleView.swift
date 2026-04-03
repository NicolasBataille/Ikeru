import SwiftUI
import IkeruCore

// MARK: - Conversation Bubble View

/// A reusable chat bubble component for conversation messages.
/// User messages are right-aligned with glass material; assistant messages
/// are left-aligned with a warm amber/jade tint.
struct ConversationBubbleView: View {

    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: bubbleAlignment, spacing: IkeruTheme.Spacing.sm) {
                messageContent
                correctionsSection
                vocabularySection
                timestampLabel
            }
            .padding(IkeruTheme.Spacing.md)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg))
            .shadow(
                color: .black.opacity(0.2),
                radius: 4,
                y: 2
            )

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Content

    private var messageContent: some View {
        Text(message.content)
            .font(.ikeruBody)
            .foregroundStyle(textColor)
            .multilineTextAlignment(message.role == .user ? .trailing : .leading)
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
            FlowLayout(spacing: IkeruTheme.Spacing.xs) {
                ForEach(message.vocabularyHints) { hint in
                    VocabularyChipView(hint: hint)
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

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Rectangle().fill(.ultraThinMaterial)
        case .assistant:
            Color(hex: IkeruTheme.Colors.surface)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.08),
                            Color(hex: IkeruTheme.Colors.success).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .system:
            Color.clear
        }
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

    var body: some View {
        VStack(spacing: 1) {
            if !hint.reading.isEmpty {
                Text(hint.reading)
                    .font(.system(size: 10))
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
}

// MARK: - Flow Layout

/// A simple flow layout that wraps items to the next line when they exceed
/// the available width.
private struct FlowLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = arrangeSubviews(
            proposal: proposal,
            subviews: subviews
        )
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrangeSubviews(
            proposal: proposal,
            subviews: subviews
        )

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        let size: CGSize
        let positions: [CGPoint]
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
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
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return ArrangementResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
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
