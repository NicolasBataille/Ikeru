import SwiftUI
import IkeruCore

// MARK: - SessionPreviewCard

/// Reusable card showing session preview details: estimated duration,
/// exercise count, skill balance bar, and exercise type breakdown.
struct SessionPreviewCard: View {

    let preview: SessionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            // Header row: estimated time + exercise count
            HStack {
                Label {
                    Text("~\(preview.estimatedMinutes) min")
                        .font(.system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold))
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }

                Spacer()

                Label {
                    Text("\(preview.cardCount) exercises")
                        .font(.system(size: IkeruTheme.Typography.Size.body))
                        .foregroundStyle(Color.ikeruTextSecondary)
                } icon: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }

            // Skill balance bar
            if !preview.skillSplit.isEmpty {
                SkillBalanceBar(skillSplit: preview.skillSplit)
            }

            // Exercise type breakdown
            if !preview.exerciseBreakdown.isEmpty {
                exerciseBreakdownList
            }
        }
        .ikeruCard(.elevated)
    }

    // MARK: - Exercise Breakdown

    @ViewBuilder
    private var exerciseBreakdownList: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            ForEach(sortedBreakdown, id: \.label) { entry in
                HStack {
                    Image(systemName: entry.icon)
                        .font(.system(size: IkeruTheme.Typography.Size.caption))
                        .foregroundStyle(entry.color)
                        .frame(width: 16)

                    Text(entry.label)
                        .font(.system(size: IkeruTheme.Typography.Size.stats))
                        .foregroundStyle(Color.ikeruTextSecondary)

                    Spacer()

                    Text("\(entry.count)")
                        .font(.system(size: IkeruTheme.Typography.Size.stats, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private struct BreakdownEntry: Hashable {
        let label: String
        let count: Int
        let icon: String
        let color: Color
    }

    private var sortedBreakdown: [BreakdownEntry] {
        preview.exerciseBreakdown
            .sorted { $0.key.pedagogicalOrder < $1.key.pedagogicalOrder }
            .map { skill, count in
                BreakdownEntry(
                    label: displayLabel(for: skill),
                    count: count,
                    icon: icon(for: skill),
                    color: color(for: skill)
                )
            }
    }

    private func displayLabel(for skill: SkillType) -> String {
        switch skill {
        case .reading: "Reading"
        case .writing: "Writing"
        case .listening: "Listening"
        case .speaking: "Speaking"
        }
    }

    private func icon(for skill: SkillType) -> String {
        switch skill {
        case .reading: "book"
        case .writing: "pencil.line"
        case .listening: "headphones"
        case .speaking: "mic"
        }
    }

    private func color(for skill: SkillType) -> Color {
        switch skill {
        case .reading: Color(hex: IkeruTheme.Colors.Skills.reading)
        case .writing: Color(hex: IkeruTheme.Colors.Skills.writing)
        case .listening: Color(hex: IkeruTheme.Colors.Skills.listening)
        case .speaking: Color(hex: IkeruTheme.Colors.Skills.speaking)
        }
    }
}

// MARK: - Preview

#Preview("Session Preview Card") {
    SessionPreviewCard(preview: SessionPreview(
        estimatedMinutes: 20,
        cardCount: 12,
        exerciseBreakdown: [
            .reading: 6,
            .writing: 2,
            .listening: 2,
            .speaking: 2
        ],
        skillSplit: [
            .reading: 0.50,
            .writing: 0.17,
            .listening: 0.17,
            .speaking: 0.16
        ]
    ))
    .padding(IkeruTheme.Spacing.md)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
