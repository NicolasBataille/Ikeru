import SwiftUI
import IkeruCore

// MARK: - BilingualLabel
//
// Mode-aware section header. In `.tatami` it's the original kanji-first
// pattern (mon + serif Japanese + middot + uppercase chrome). In
// `.beginner` it inverts: chrome label is primary, with an optional faint
// romaji suffix to keep the language hint without dominating.
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
    /// Optional romaji rendered as a faint suffix in beginner mode.
    /// Pass nil to render no romaji caption.
    var romaji: String? = nil

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        switch displayMode {
        case .beginner:
            beginnerBody
        case .tatami:
            tatamiBody
        }
    }

    private var beginnerBody: some View {
        HStack(spacing: 6) {
            if let mon {
                MonCrest(kind: mon, size: 10, color: TatamiTokens.goldDim.opacity(0.55))
            }
            Text(chrome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextPrimary)
            if let romaji {
                Text(romaji)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(TatamiTokens.paperGhost.opacity(0.7))
            }
        }
    }

    private var tatamiBody: some View {
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
