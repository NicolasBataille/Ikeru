import Foundation

/// Capability identifier for an exercise. Distinct from `ExerciseItem`
/// (which carries the content payload). Used by `ExerciseUnlockService`
/// and `SessionPlanner` to gate and select exercises by category.
public enum ExerciseType: String, Codable, CaseIterable, Sendable, Hashable {
    case kanaStudy
    case kanjiStudy
    case vocabularyStudy
    case listeningSubtitled
    case fillInBlank
    case grammarExercise
    case sentenceConstruction
    case readingPassage
    case writingPractice
    case listeningUnsubtitled
    case speakingPractice
    case sakuraConversation

    /// The primary skill this exercise type targets.
    public var skill: SkillType {
        switch self {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy,
             .fillInBlank, .grammarExercise, .readingPassage:
            .reading
        case .writingPractice, .sentenceConstruction:
            .writing
        case .listeningSubtitled, .listeningUnsubtitled:
            .listening
        case .speakingPractice, .sakuraConversation:
            .speaking
        }
    }

    /// Estimated duration in seconds.
    public var estimatedDurationSeconds: Int {
        switch self {
        case .kanaStudy: 25
        case .kanjiStudy: 60
        case .vocabularyStudy: 30
        case .listeningSubtitled: 60
        case .fillInBlank: 20
        case .grammarExercise: 45
        case .sentenceConstruction: 60
        case .readingPassage: 120
        case .writingPractice: 90
        case .listeningUnsubtitled: 75
        case .speakingPractice: 90
        case .sakuraConversation: 180
        }
    }
}
