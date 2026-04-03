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
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg))

            if variant == .companion { Spacer(minLength: 48) }
        }
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
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg)
                .fill(Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.15))
        case .user:
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Rich Content

    @ViewBuilder
    private var richContentView: some View {
        let blocks = ChatContentParser.parse(content)

        FlowLayout(spacing: 0) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: ChatContentBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.ikeruBody)
                .foregroundStyle(textColor)

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

// MARK: - FlowLayout

/// Simple horizontal flow layout that wraps content.
private struct FlowLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let size: CGSize
    }

    private func layoutSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> LayoutResult {
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
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
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
