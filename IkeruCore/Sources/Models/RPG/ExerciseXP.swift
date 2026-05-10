import Foundation

public enum ExerciseXPRule: Sendable, Equatable {
    case perGrade(grade: Grade, bonus: Int)
    case perCompletion(base: Int)
}

public enum ExerciseXP {
    public static func rule(for type: ExerciseType, grade: Grade?) -> ExerciseXPRule {
        switch type {
        case .kanaStudy:           return .perGrade(grade: grade ?? .good, bonus: 0)
        case .kanjiStudy:          return .perGrade(grade: grade ?? .good, bonus: 2)
        case .vocabularyStudy:     return .perGrade(grade: grade ?? .good, bonus: 0)
        case .fillInBlank:         return .perGrade(grade: grade ?? .good, bonus: 1)
        case .grammarExercise:     return .perCompletion(base: 8)
        case .sentenceConstruction:return .perCompletion(base: 12)
        case .readingPassage:      return .perCompletion(base: 25)
        case .writingPractice:     return .perCompletion(base: 18)
        case .listeningSubtitled:  return .perCompletion(base: 10)
        case .listeningUnsubtitled:return .perCompletion(base: 14)
        case .speakingPractice:    return .perCompletion(base: 16)
        case .sakuraConversation:  return .perCompletion(base: 20)
        }
    }
}

extension ExerciseXP {
    public static func multiplier(for level: JLPTLevel) -> Double {
        switch level {
        case .n5: return 1.00
        case .n4: return 1.15
        case .n3: return 1.30
        case .n2: return 1.50
        case .n1: return 1.75
        }
    }
}

extension ExerciseXP {
    public static func award(type: ExerciseType, level: JLPTLevel, grade: Grade?) -> Int {
        let base: Int
        switch rule(for: type, grade: grade) {
        case .perGrade(let g, let bonus):
            base = RPGConstants.xpForGrade(g) + bonus
        case .perCompletion(let b):
            base = b
        }
        return Int((Double(base) * multiplier(for: level)).rounded())
    }
}
