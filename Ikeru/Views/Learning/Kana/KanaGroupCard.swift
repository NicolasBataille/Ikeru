import SwiftUI
import IkeruCore

/// A single kana group cell with checkbox, characters, per-char mastery and
/// group aggregate row. Tapping anywhere toggles selection.
struct KanaGroupCard: View {

    let group: KanaGroup
    let isSelected: Bool
    let mastery: GroupMastery?
    let charMastery: [String: MasteryLevel]
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 10) {
                header
                characterRow
                footer
            }
            .tatamiRoom(isSelected ? .accent : .standard, padding: CGFloat(IkeruTheme.Spacing.md))
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.55), lineWidth: 1)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            checkbox
            Text(LocalizedStringKey(group.displayName))
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var checkbox: some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? Color.ikeruPrimaryAccent.opacity(0.85) : Color.clear)
                .frame(width: 18, height: 18)
                .overlay(
                    Rectangle().strokeBorder(
                        isSelected ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim.opacity(0.6),
                        lineWidth: 1.2
                    )
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ikeruBackground)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Characters

    private var characterRow: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(group.characters) { kana in
                VStack(spacing: 3) {
                    Text(kana.character)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    // Romaji reading, tinted by per-char mastery. The prior
                    // MasteryBadge kanji glyph (初/学/…) read as a rendering
                    // bug to the exact audience of this screen — beginners
                    // who can't read kanji yet. The reading is the useful
                    // info; progress lives in the tint (quiet → gold → green).
                    Text(kana.romaji)
                        .font(.ikeruMicro)
                        .foregroundStyle(masteryTint(charMastery[kana.character] ?? .new))
                }
                .frame(maxWidth: .infinity)
            }
            // Pad out rows shorter than 5 so layout stays even
            let padCount = max(0, 5 - group.characters.count)
            if padCount > 0 {
                ForEach(0..<padCount, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Mastery: \(masteryPercentString)")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Spacer(minLength: 4)
            Text(nextDueString)
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
                .lineLimit(1)
        }
    }

    /// Mastery encoded as tint on the romaji: neutral while untouched, warming
    /// toward gold as it's learned, settling green once anchored.
    private func masteryTint(_ level: MasteryLevel) -> Color {
        switch level {
        case .new:       return Color.ikeruTextTertiary
        case .learning:  return Color.ikeruTextSecondary
        case .familiar:  return Color.ikeruPrimaryAccent.opacity(0.75)
        case .mastered:  return Color.ikeruPrimaryAccent
        case .anchored:  return Color.ikeruSuccess
        }
    }

    private var masteryPercentString: String {
        guard let m = mastery else { return "—" }
        return "\(Int(m.aggregatePercent.rounded()))%"
    }

    private var nextDueString: String {
        guard let due = mastery?.nextDueDate else { return "" }
        let now = Date()
        let interval = due.timeIntervalSince(now)
        if interval <= 0 {
            return String(localized: "Today")
        }
        let days = Int((interval / 86_400).rounded(.up))
        if days <= 1 { return String(localized: "Tomorrow") }
        return String(localized: "in \(days)d")
    }
}
