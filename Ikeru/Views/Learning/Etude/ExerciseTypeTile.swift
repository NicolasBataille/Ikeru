import SwiftUI
import IkeruCore

struct ExerciseTypeTile: View {

    let type: ExerciseType
    let state: ExerciseUnlockState
    let onTap: () -> Void

    private var isUnlocked: Bool { state.isUnlocked }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ExerciseTileTokens.glyph(for: type))
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(isUnlocked ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost)
                Text(ExerciseTileTokens.label(for: type))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isUnlocked ? Color.ikeruTextPrimary : Color.ikeruTextSecondary)
                if !isUnlocked, case .locked(let reason) = state {
                    Text(lockHint(reason))
                        .font(.system(size: 10))
                        .italic()
                        .foregroundStyle(TatamiTokens.paperGhost)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(isUnlocked ? 0.04 : 0.02))
            .overlay(Rectangle().strokeBorder(
                isUnlocked ? TatamiTokens.goldDim : TatamiTokens.goldDim.opacity(0.3),
                lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }

    private func lockHint(_ reason: ExerciseLockReason) -> String {
        switch reason {
        case .vocabularyMastered(let req, let cur):
            return String(localized: "Etude.Lock.Vocab \(cur) \(req)")
        case .kanjiMastered(let req, let cur):
            return String(localized: "Etude.Lock.Kanji \(cur) \(req)")
        case .kanaMastered(let script):
            return script == .hiragana
                ? String(localized: "Etude.Lock.Hiragana")
                : String(localized: "Etude.Lock.Katakana")
        case .grammarPointsMastered(let req, let cur):
            return String(localized: "Etude.Lock.Grammar \(cur) \(req)")
        case .listeningAccuracyOver(let req, _, let win):
            return String(localized: "Etude.Lock.ListenAccuracy \(Int(req * 100)) \(win)")
        case .listeningRecallOver(let req, _, let days):
            return String(localized: "Etude.Lock.ListenRecall \(Int(req * 100)) \(days)")
        case .jlptLevelReached(let req, _):
            return String(localized: "Etude.Lock.JLPT \(req.displayLabel)")
        }
    }
}
