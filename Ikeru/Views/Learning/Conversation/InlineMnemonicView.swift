import SwiftUI
import IkeruCore

// MARK: - InlineMnemonicView

/// Small card embedded in a chat bubble showing a mnemonic for a kanji.
struct InlineMnemonicView: View {

    let character: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            HStack(spacing: IkeruTheme.Spacing.sm) {
                Text(character)
                    .font(.custom(
                        IkeruTheme.Typography.FontFamily.kanjiSerif,
                        size: IkeruTheme.Typography.Size.heading3
                    ))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

                Text("Mnemonic")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
            }

            Text(hint)
                .font(.ikeruCaption)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.kanjiText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(IkeruTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                .fill(Color(hex: IkeruTheme.Colors.surface, opacity: 0.6))
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview("InlineMnemonicView") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background).ignoresSafeArea()

        InlineMnemonicView(
            character: "食",
            hint: "A person eating from a tray under a roof"
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
