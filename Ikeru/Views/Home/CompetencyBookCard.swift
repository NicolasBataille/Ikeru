import SwiftUI
import IkeruCore

// MARK: - CompetencyBookCard
//
// The "livret de compétence" (competency booklet) — a quiet mirror of what
// the learner actually knows right now, aggregated from kana cards + the
// personal vocabulary dictionary via `MasteryBookCounts`.
//
// This is the direct answer to the 2026-08-10 review's erreur de conception
// #4: removing streaks/leagues was the right call, but it left silence where
// a signal should be. This card is that signal — and DELIBERATELY reuses the
// New/Learning/Familiar/Mastered/Anchored vocabulary (glyph + label) already
// shipped in the personal vocabulary dictionary's filter chips
// (`VocabMasteryFilter`, `MasteryLevel`), per OBS-026: "a competency booklet
// without a cover page" — this is that cover page, not a second vocabulary
// of progress terms invented from scratch.
//
// Sobriety by design: no color-coded gamification, no celebratory copy, no
// streak framing. A weekly delta is shown only when it exists and is
// nonzero — a flat week is left silent rather than padded with a fake "+0".

struct CompetencyBookCard: View {
    let masteryBook: MasteryBookCounts
    let weeklyDelta: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chipRow
        }
        .tatamiRoom(.standard, padding: 14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Home.CompetencyBook.Eyebrow")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text("Home.CompetencyBook.Subtitle")
                    .ikeruScaledFont(13, weight: .regular, design: .serif, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
            Spacer()
            if let weeklyDelta, weeklyDelta != 0 {
                weeklyDeltaBadge(weeklyDelta)
            }
        }
    }

    private func weeklyDeltaBadge(_ delta: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(delta > 0 ? "+\(delta)" : "\(delta)")
                .ikeruScaledFont(15, weight: .semibold, design: .serif, relativeTo: .body)
                .monospacedDigit()
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("Home.CompetencyBook.WeeklyDelta")
                .ikeruScaledFont(9, relativeTo: .caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        HStack(spacing: 0) {
            ForEach(MasteryLevel.allCases, id: \.rawValue) { level in
                masteryChip(level: level, count: masteryBook.count(level))
                // `.anchored` is the last case in declaration order (New →
                // Learning → Familiar → Mastered → Anchored), so this simply
                // skips the trailing divider after the final chip.
                if level.rawValue != MasteryLevel.anchored.rawValue {
                    Divider()
                        .frame(width: 0.6, height: 30)
                        .overlay(Color.white.opacity(0.10))
                }
            }
        }
    }

    private func masteryChip(level: MasteryLevel, count: Int) -> some View {
        VStack(spacing: 3) {
            Text(level.glyph)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text("\(count)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text(LocalizedStringKey(level.label))
                .ikeruScaledFont(8, weight: .semibold, relativeTo: .caption2)
                .textCase(.uppercase)
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("CompetencyBookCard") {
    ZStack {
        IkeruScreenBackground(variant: .home)
        VStack(spacing: 16) {
            CompetencyBookCard(
                masteryBook: MasteryBookCounts(
                    newCount: 40, learningCount: 12, familiarCount: 8, masteredCount: 3, anchoredCount: 1
                ),
                weeklyDelta: 5
            )
            CompetencyBookCard(
                masteryBook: MasteryBookCounts(newCount: 20, learningCount: 4),
                weeklyDelta: nil
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
