import SwiftUI
import IkeruCore

// MARK: - SkillBalanceBar

/// A horizontal stacked bar showing skill split percentages.
/// Each skill gets a proportional colored segment with labels below.
struct SkillBalanceBar: View {

    /// Skill split ratios (0.0-1.0 per skill).
    let skillSplit: [SkillType: Double]

    /// Height of the bar.
    var barHeight: CGFloat = 8

    /// Whether to show labels below the bar.
    var showLabels: Bool = true

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(sortedSkills, id: \.skill) { entry in
                        let width = max(0, geometry.size.width * entry.ratio)
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(color(for: entry.skill))
                            .frame(width: width, height: barHeight)
                    }
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: barHeight / 2))
            .animation(.easeInOut(duration: IkeruTheme.Animation.standardDuration), value: skillSplit)

            if showLabels {
                HStack(spacing: IkeruTheme.Spacing.md) {
                    ForEach(sortedSkills, id: \.skill) { entry in
                        skillLabel(skill: entry.skill, ratio: entry.ratio)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private struct SkillEntry: Hashable {
        let skill: SkillType
        let ratio: Double
    }

    private var sortedSkills: [SkillEntry] {
        SkillType.allCases
            .filter { (skillSplit[$0] ?? 0) > 0 }
            .sorted { $0.pedagogicalOrder < $1.pedagogicalOrder }
            .map { SkillEntry(skill: $0, ratio: skillSplit[$0] ?? 0) }
    }

    private func color(for skill: SkillType) -> Color {
        switch skill {
        case .reading:
            Color(hex: IkeruTheme.Colors.Skills.reading)
        case .writing:
            Color(hex: IkeruTheme.Colors.Skills.writing)
        case .listening:
            Color(hex: IkeruTheme.Colors.Skills.listening)
        case .speaking:
            Color(hex: IkeruTheme.Colors.Skills.speaking)
        }
    }

    @ViewBuilder
    private func skillLabel(skill: SkillType, ratio: Double) -> some View {
        HStack(spacing: IkeruTheme.Spacing.xs) {
            Circle()
                .fill(color(for: skill))
                .frame(width: 6, height: 6)

            Text("\(skill.rawValue.capitalized) \(Int(ratio * 100))%")
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }
}

// MARK: - Preview

#Preview("Skill Balance Bar") {
    VStack(spacing: IkeruTheme.Spacing.lg) {
        SkillBalanceBar(skillSplit: [
            .reading: 0.35,
            .writing: 0.20,
            .listening: 0.25,
            .speaking: 0.20
        ])

        SkillBalanceBar(skillSplit: [
            .reading: 0.50,
            .writing: 0.50
        ])

        SkillBalanceBar(skillSplit: [:])
    }
    .padding(IkeruTheme.Spacing.md)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
