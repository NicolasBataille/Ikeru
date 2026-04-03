import SwiftUI
import IkeruCore

// MARK: - InlineKanjiView

/// Tappable inline kanji display within a chat bubble.
/// Shows the kanji character; tapping reveals a brief definition popover.
struct InlineKanjiView: View {

    let character: String

    @State private var showDefinition = false

    var body: some View {
        Button {
            showDefinition.toggle()
        } label: {
            Text(character)
                .font(.custom(
                    IkeruTheme.Typography.FontFamily.kanjiSerif,
                    size: IkeruTheme.Typography.Size.heading2
                ))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                .padding(.horizontal, IkeruTheme.Spacing.xs)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .fill(Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.1))
                }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDefinition) {
            kanjiPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var kanjiPopover: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text(character)
                .font(.kanjiDisplay)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))

            Text("Tap & hold in study mode for full details")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(IkeruTheme.Spacing.md)
        .background(Color(hex: IkeruTheme.Colors.surface))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#Preview("InlineKanjiView") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background).ignoresSafeArea()
        InlineKanjiView(character: "食")
    }
    .preferredColorScheme(.dark)
}
