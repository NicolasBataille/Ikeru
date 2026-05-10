import Foundation

/// Pure: maps a learner's JLPT estimate to the eligible variety pool.
/// JLPT ordering is N5 < N4 < N3 < N2 < N1 (lower number = harder).
/// Higher levels stack onto lower levels — N4 includes N5; N3 adds more.
public enum VarietyPoolResolver {

    /// Raw pool by JLPT level (before unlocking constraints).
    public static func pool(for level: JLPTLevel) -> Set<ExerciseType> {
        var result: Set<ExerciseType> = [.listeningSubtitled, .fillInBlank]
        if level >= .n4 {
            result.formUnion([.grammarExercise, .sentenceConstruction])
        }
        if level >= .n3 {
            result.formUnion([.readingPassage, .writingPractice, .listeningUnsubtitled])
        }
        if level >= .n2 {
            result.formUnion([.speakingPractice, .sakuraConversation])
        }
        return result
    }

    /// Pool intersected with the unlocked set the learner can actually use.
    public static func effectivePool(
        for level: JLPTLevel,
        unlockedTypes: Set<ExerciseType>
    ) -> Set<ExerciseType> {
        pool(for: level).intersection(unlockedTypes)
    }
}
