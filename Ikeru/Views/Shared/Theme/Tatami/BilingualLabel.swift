import SwiftUI

// MARK: - BilingualLabel
//
// The section-header pattern: optional mon + serif Japanese + middot +
// uppercase chrome label (EN or FR). Used everywhere a "TODAY", "DECKS",
// "SETTINGS"-style label lives in the current app.
//
// The Japanese half is fixed content (it's what the app teaches); the
// `chrome` parameter flows through localization so it switches with the
// app language.

struct BilingualLabel: View {
    let japanese: String
    /// The localized chrome label. Pass either a `LocalizedStringKey` (e.g.
    /// `"TODAY"`) so it auto-translates, or a literal `String` if the value
    /// is already localized at the call site.
    let chrome: LocalizedStringKey
    var mon: MonKind? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let mon {
                MonCrest(kind: mon, size: 11, color: TatamiTokens.goldDim)
            }
            Text(japanese)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextSecondary)
                .tracking(1.5)
            Text("·")
                .foregroundStyle(TatamiTokens.paperGhost)
            Text(chrome)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TatamiTokens.paperGhost)
                .tracking(2.4)
                .textCase(.uppercase)
        }
    }
}

#Preview("BilingualLabel") {
    VStack(alignment: .leading, spacing: 16) {
        BilingualLabel(japanese: "本日", chrome: "Today", mon: .asanoha)
        BilingualLabel(japanese: "稽古場", chrome: "Decks", mon: .kikkou)
        BilingualLabel(japanese: "進歩", chrome: "Progress")
    }
    .padding(40)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
