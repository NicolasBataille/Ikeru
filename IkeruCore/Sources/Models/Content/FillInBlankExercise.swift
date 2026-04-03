import Foundation

// MARK: - FillInBlankType

/// The category of fill-in-the-blank exercise.
public enum FillInBlankType: String, Sendable, CaseIterable {
    /// Particle usage (は/が/を/に/で).
    case particle
    /// Verb conjugation forms.
    case conjugation
    /// Vocabulary word meaning.
    case vocabulary
}

// MARK: - FillInBlankExercise

/// A fill-in-the-blank exercise that tests particle usage, conjugation, or vocabulary.
public struct FillInBlankExercise: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// Full sentence with blank marker "___".
    public let sentence: String

    /// The correct answer to fill in.
    public let correctAnswer: String

    /// Multiple choice options (4 items). Always includes the correct answer.
    public let options: [String]

    /// Grammar or vocabulary hint.
    public let hint: String

    /// The type of exercise (particle, conjugation, or vocabulary).
    public let exerciseType: FillInBlankType

    public init(
        id: UUID = UUID(),
        sentence: String,
        correctAnswer: String,
        options: [String],
        hint: String,
        exerciseType: FillInBlankType
    ) {
        self.id = id
        self.sentence = sentence
        self.correctAnswer = correctAnswer
        self.options = options
        self.hint = hint
        self.exerciseType = exerciseType
    }
}
