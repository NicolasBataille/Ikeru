import Foundation

public enum ExerciseXPRule: Sendable, Equatable {
    case perGrade(grade: Grade, bonus: Int)
    case perCompletion(base: Int)
}
