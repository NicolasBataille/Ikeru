import SwiftUI
import IkeruCore

// MARK: - DensityAwareStatChip
//
// Mode-aware variant of the RPG header chip (reviews / items / attributes).
// In `.beginner` it renders an SF Symbol + numeral + caps label.
// In `.tatami` it renders the original kanji glyph + numeral + caps.

struct DensityAwareStatChip: View {

    let kanjiGlyph: String
    let symbolName: String
    let value: Int
    let label: LocalizedStringKey
    let tint: Color

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        HStack(spacing: 8) {
            switch displayMode {
            case .beginner:
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            case .tatami:
                Text(kanjiGlyph)
                    .font(.system(size: 16, weight: .light, design: .serif))
                    .foregroundStyle(tint)
            }
            SerifNumeral(value, size: 16, color: Color.ikeruTextPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TatamiTokens.paperGhost)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .sumiCorners(color: tint, size: 6, weight: 1.0, inset: -1)
    }
}

// MARK: - ReadingAidResolver
//
// Resolves a reading-aid's effective value:
//   - If the user has explicitly toggled it: use stored value.
//   - Else: use the mode-default (true in beginner, false in tatami).
struct ReadingAidResolver {
    let mode: DisplayMode
    let userTouched: Bool
    let storedValue: Bool

    var effective: Bool {
        userTouched ? storedValue : (mode == .beginner)
    }
}
