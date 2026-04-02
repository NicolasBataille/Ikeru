import Foundation

/// Target skill balance ratios — the ideal distribution of learning time across skills.
public struct SkillBalance: Sendable, Equatable {

    /// Target ratio per skill. Values sum to 1.0.
    public let targets: [SkillType: Double]

    /// Default balanced target: reading 30%, writing 20%, listening 25%, speaking 25%.
    public static let defaultTargets = SkillBalance(targets: [
        .reading: 0.30,
        .writing: 0.20,
        .listening: 0.25,
        .speaking: 0.25
    ])

    public init(targets: [SkillType: Double]) {
        self.targets = targets
    }

    /// Computes the deficit for each skill relative to the target.
    /// deficit = max(0, target - current)
    /// - Parameter current: Current skill ratios from recent activity.
    /// - Returns: Normalized weights (summing to 1.0) proportional to each skill's deficit.
    public func deficitWeights(current: [SkillType: Double]) -> [SkillType: Double] {
        var deficits: [SkillType: Double] = [:]
        for skill in SkillType.allCases {
            let target = targets[skill] ?? 0
            let actual = current[skill] ?? 0
            deficits[skill] = max(0, target - actual)
        }

        let totalDeficit = deficits.values.reduce(0, +)

        // If no deficit (perfectly balanced or over-target), distribute equally
        guard totalDeficit > 0 else {
            let equal = 1.0 / Double(SkillType.allCases.count)
            return Dictionary(uniqueKeysWithValues: SkillType.allCases.map { ($0, equal) })
        }

        // Normalize deficits to sum to 1.0
        return deficits.mapValues { $0 / totalDeficit }
    }

    /// Computes the imbalance score: sum of absolute deviations from target.
    /// A score of 0.0 means perfectly balanced.
    /// - Parameter current: Current skill ratios from recent activity.
    /// - Returns: Imbalance score (0.0 = balanced, higher = more imbalanced).
    public func imbalanceScore(current: [SkillType: Double]) -> Double {
        var total = 0.0
        for skill in SkillType.allCases {
            let target = targets[skill] ?? 0
            let actual = current[skill] ?? 0
            total += abs(target - actual)
        }
        return total
    }
}
