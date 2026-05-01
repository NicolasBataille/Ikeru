import SwiftUI

// MARK: - LanguagePickerView
//
// Sheet presented from the Settings "言語 / Language" row. Three options
// (Auto / English / Français) — tap an option to set the preference; the
// `\.locale` environment update propagates immediately, so every visible
// `Text` re-renders without an app relaunch.
//
// Visual style matches the Tatami direction: tatami room with fusuma rows,
// hanko on the active row, kanji on the left of each label.

struct LanguagePickerView: View {
    @Environment(AppLocale.self) private var appLocale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MarbleBackground(variant: .auxiliary)

            VStack(alignment: .leading, spacing: 24) {
                header
                rows
                Spacer()
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("‹")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
            BilingualLabel(japanese: "言語", chrome: "Language")
            Spacer()
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(.system, japanese: "自動", english: "Auto")
            row(.en,     japanese: "英語", english: "English")
            row(.fr,     japanese: "仏語", english: "Français")
        }
        .tatamiRoom(.standard, padding: 0)
    }

    @ViewBuilder
    private func row(_ pref: LanguagePreference, japanese: String, english: String) -> some View {
        let isActive = appLocale.preference == pref
        Button {
            appLocale.setPreference(pref)
        } label: {
            HStack(spacing: 16) {
                Text(japanese)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .frame(width: 36, alignment: .leading)
                Text(english)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                if isActive { HankoStamp(kanji: "選", size: 24) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("LanguagePickerView") {
    LanguagePickerView()
        .environment(AppLocale(preference: .system))
        .preferredColorScheme(.dark)
}
