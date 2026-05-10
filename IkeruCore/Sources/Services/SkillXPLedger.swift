import Foundation

public actor SkillXPLedger {

    private var contribution: SessionSkillContribution = .zero

    public init() {}

    public func record(xp: Int, exerciseType: ExerciseType) {
        let split = SkillAttribution.split(for: exerciseType)
        let xpDouble = Double(xp)
        contribution.reading   += Int((xpDouble * split.reading).rounded())
        contribution.writing   += Int((xpDouble * split.writing).rounded())
        contribution.listening += Int((xpDouble * split.listening).rounded())
        contribution.speaking  += Int((xpDouble * split.speaking).rounded())
    }

    public func snapshot() -> SessionSkillContribution { contribution }
}
