import Foundation

/// Unique identifiers for non-card exercise content.
public typealias GrammarPointID = UUID
public typealias ListeningExerciseID = UUID
public typealias SpeakingExerciseID = UUID
public typealias SentenceExerciseID = UUID

/// A single exercise in an adaptive session plan.
/// Each item maps to a skill and has an estimated duration.
public enum ExerciseItem: Sendable, Equatable {
    /// An SRS flashcard review.
    case srsReview(CardDTO)
    /// A kanji study exercise (character to learn).
    case kanjiStudy(String)
    /// A grammar point exercise.
    case grammarExercise(GrammarPointID)
    /// A writing practice exercise.
    case writingPractice(String)
    /// A listening comprehension exercise.
    case listeningExercise(ListeningExerciseID)
    /// A speaking practice exercise.
    case speakingExercise(SpeakingExerciseID)
    /// A sentence construction exercise.
    case sentenceConstruction(SentenceExerciseID)

    /// The skill this exercise targets.
    public var skill: SkillType {
        switch self {
        case .srsReview: .reading
        case .kanjiStudy: .reading
        case .grammarExercise: .reading
        case .writingPractice: .writing
        case .listeningExercise: .listening
        case .speakingExercise: .speaking
        case .sentenceConstruction: .writing
        }
    }

    /// Estimated duration in seconds for this exercise type.
    public var estimatedDurationSeconds: Int {
        switch self {
        case .srsReview: 15
        case .kanjiStudy: 60
        case .grammarExercise: 45
        case .writingPractice: 90
        case .listeningExercise: 60
        case .speakingExercise: 90
        case .sentenceConstruction: 60
        }
    }

    /// Whether this exercise requires audio playback.
    public var requiresAudio: Bool {
        switch self {
        case .listeningExercise, .speakingExercise: true
        case .srsReview, .kanjiStudy, .grammarExercise, .writingPractice, .sentenceConstruction: false
        }
    }
}

// MARK: - CardDTO Equatable conformance for ExerciseItem

extension CardDTO: Equatable {
    public static func == (lhs: CardDTO, rhs: CardDTO) -> Bool {
        lhs.id == rhs.id
    }
}
