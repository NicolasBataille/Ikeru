import Foundation

/// Read-only aggregator the unlock service + planner consume. Built once
/// per session-planning request from real models (`RPGState`, cards,
/// listening history) by `LearnerSnapshotBuilder`.
public struct LearnerSnapshot: Sendable, Equatable {

    public let jlptLevel: JLPTLevel
    public let vocabularyMasteredFamiliarPlus: Int
    public let kanjiMasteredFamiliarPlus: Int
    public let hiraganaMastered: Bool
    public let katakanaMastered: Bool
    public let grammarPointsFamiliarPlus: Int
    public let listeningAccuracyLast30: Double
    public let listeningRecallLast30Days: Double
    public let skillBalances: [SkillType: Double]
    public let dueCardCount: Int
    public let hasNewContentQueued: Bool
    public let lastSessionAt: Date?

    public init(
        jlptLevel: JLPTLevel,
        vocabularyMasteredFamiliarPlus: Int,
        kanjiMasteredFamiliarPlus: Int,
        hiraganaMastered: Bool,
        katakanaMastered: Bool,
        grammarPointsFamiliarPlus: Int,
        listeningAccuracyLast30: Double,
        listeningRecallLast30Days: Double,
        skillBalances: [SkillType: Double],
        dueCardCount: Int,
        hasNewContentQueued: Bool,
        lastSessionAt: Date?
    ) {
        self.jlptLevel = jlptLevel
        self.vocabularyMasteredFamiliarPlus = vocabularyMasteredFamiliarPlus
        self.kanjiMasteredFamiliarPlus = kanjiMasteredFamiliarPlus
        self.hiraganaMastered = hiraganaMastered
        self.katakanaMastered = katakanaMastered
        self.grammarPointsFamiliarPlus = grammarPointsFamiliarPlus
        self.listeningAccuracyLast30 = listeningAccuracyLast30
        self.listeningRecallLast30Days = listeningRecallLast30Days
        self.skillBalances = skillBalances
        self.dueCardCount = dueCardCount
        self.hasNewContentQueued = hasNewContentQueued
        self.lastSessionAt = lastSessionAt
    }

    /// `(maxSkill - minSkill) / maxSkill`. Returns 0 when no balances or
    /// when the spread is exactly zero.
    public var skillImbalance: Double {
        let values = skillBalances.values
        guard let maxV = values.max(), maxV > 0,
              let minV = values.min() else { return 0 }
        return (maxV - minV) / maxV
    }

    public static let empty = LearnerSnapshot(
        jlptLevel: .n5,
        vocabularyMasteredFamiliarPlus: 0,
        kanjiMasteredFamiliarPlus: 0,
        hiraganaMastered: false,
        katakanaMastered: false,
        grammarPointsFamiliarPlus: 0,
        listeningAccuracyLast30: 0,
        listeningRecallLast30Days: 0,
        skillBalances: [:],
        dueCardCount: 0,
        hasNewContentQueued: false,
        lastSessionAt: nil
    )
}
