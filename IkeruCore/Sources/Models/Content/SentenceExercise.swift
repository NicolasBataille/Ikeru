import Foundation

// MARK: - SentenceToken

/// A single token (word or particle) in a sentence construction exercise.
public struct SentenceToken: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID

    /// The displayed text of this token.
    public let text: String

    /// Whether this token is a particle (は, が, を, に, で, と, も, etc.).
    /// Particles are highlighted differently in the UI.
    public let isParticle: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        isParticle: Bool = false
    ) {
        self.id = id
        self.text = text
        self.isParticle = isParticle
    }
}

// MARK: - SentenceDifficulty

/// Difficulty level for sentence construction exercises.
public enum SentenceDifficulty: String, Sendable, CaseIterable {
    /// 3-4 tokens
    case beginner
    /// 5-6 tokens
    case intermediate
    /// 7+ tokens
    case advanced
}

// MARK: - SentenceExercise

/// A single sentence construction exercise where the learner arranges
/// shuffled tokens to form a correct Japanese sentence.
public struct SentenceExercise: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// The full correct sentence (tokens joined).
    public let targetSentence: String

    /// English translation shown as the prompt.
    public let translation: String

    /// Hiragana reading of the full sentence.
    public let reading: String

    /// Scrambled word tiles for the learner to arrange.
    public let shuffledTokens: [SentenceToken]

    /// Difficulty level of this exercise.
    public let difficulty: SentenceDifficulty

    public init(
        id: UUID = UUID(),
        targetSentence: String,
        translation: String,
        reading: String,
        shuffledTokens: [SentenceToken],
        difficulty: SentenceDifficulty
    ) {
        self.id = id
        self.targetSentence = targetSentence
        self.translation = translation
        self.reading = reading
        self.shuffledTokens = shuffledTokens
        self.difficulty = difficulty
    }
}

// MARK: - SentenceValidationResult

/// The result of validating a sentence arrangement.
public struct SentenceValidationResult: Sendable, Equatable {
    /// Whether the arranged tokens form the correct sentence.
    public let isCorrect: Bool

    /// The expected correct answer string.
    public let correctAnswer: String

    /// Indices in the arranged array that are in the wrong position.
    /// Empty when `isCorrect` is true.
    public let incorrectPositions: [Int]

    public init(
        isCorrect: Bool,
        correctAnswer: String,
        incorrectPositions: [Int]
    ) {
        self.isCorrect = isCorrect
        self.correctAnswer = correctAnswer
        self.incorrectPositions = incorrectPositions
    }
}
