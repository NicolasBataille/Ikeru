import Foundation

/// Result of evaluating an `ExerciseType` against a `ProfileSnapshot`.
public enum ExerciseUnlockState: Sendable, Equatable {
    case unlocked
    case locked(reason: ExerciseLockReason)

    public var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}

/// Why an exercise type is currently locked. The associated values let
/// the UI surface concrete progress (`current` / `required`).
public enum ExerciseLockReason: Sendable, Equatable {
    case vocabularyMastered(required: Int, current: Int)
    case kanjiMastered(required: Int, current: Int)
    case kanaMastered(syllabary: KanaScript)
    case grammarPointsMastered(required: Int, current: Int)
    case listeningAccuracyOver(required: Double, current: Double, window: Int)
    case listeningRecallOver(required: Double, current: Double, days: Int)
    case jlptLevelReached(required: JLPTLevel, current: JLPTLevel)
}
