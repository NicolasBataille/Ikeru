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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IkeruTheme.Spacing.md)
            .background {
                IkeruGlassSurface(
                    cornerRadius: IkeruTheme.Radius.lg,
                    tint: isSelected ? Color.ikeruPrimaryAccent : .clear,
                    tintOpacity: isSelected ? 0.10 : 0.04,
                    highlight: 0.14,
                    strokeOpacity: isSelected ? 0.45 : 0.16
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous)
                        .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.55), lineWidth: 1)
                }
            }
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            checkbox
            Text(group.displayName)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.35),
                    lineWidth: 1.2
                )
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.ikeruPrimaryAccent.opacity(0.85) : Color.clear)
                }
                .frame(width: 18, height: 18)

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
                    MasteryBadge(level: charMastery[kana.character] ?? .new)
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

    private var masteryPercentString: String {
        guard let m = mastery else { return "—" }
        return "\(Int(m.aggregatePercent.rounded()))%"
    }

    private var nextDueString: String {
        guard let due = mastery?.nextDueDate else { return "" }
        let now = Date()
        let interval = due.timeIntervalSince(now)
        if interval <= 0 {
            return "Today"
        }
        let days = Int((interval / 86_400).rounded(.up))
        if days <= 1 { return "Tomorrow" }
        return "in \(days)d"
    }
}
