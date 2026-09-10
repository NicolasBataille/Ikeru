import Foundation

// MARK: - ListeningExerciseType

/// The type of listening exercise.
public enum ListeningExerciseType: String, Codable, CaseIterable, Sendable {
    /// "What did you hear?" — 4 text choices (one correct, three distractors)
    case wordRecognition

    /// Audio plays a word, learner picks the English meaning
    case meaningSelection

    /// Longer audio passage with comprehension questions
    case passageComprehension
}

// MARK: - ListeningExercise

/// A single listening exercise with audio, a question, and multiple-choice answers.
public struct ListeningExercise: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// The Japanese text to speak via TTS.
    public let audioText: String

    /// The comprehension question to display.
    public let question: String

    /// The correct answer string.
    public let correctAnswer: String

    /// Three distractor answer strings.
    public let distractors: [String]

    /// The type of exercise.
    public let exerciseType: ListeningExerciseType

    /// The JLPT difficulty level.
    public let jlptLevel: JLPTLevel

    /// Optional transcript for passage exercises (revealed after answering).
    public let transcript: String?

    /// Pre-shuffled answer choices (correct + distractors). Computed once at init
    /// so that SwiftUI view re-renders do not re-shuffle the order.
    public let allChoices: [String]

    public init(
        id: UUID = UUID(),
        audioText: String,
        question: String,
        correctAnswer: String,
        distractors: [String],
        exerciseType: ListeningExerciseType,
        jlptLevel: JLPTLevel,
        transcript: String? = nil
    ) {
        self.id = id
        self.audioText = audioText
        self.question = question
        self.correctAnswer = correctAnswer
        self.distractors = distractors
        self.exerciseType = exerciseType
        self.jlptLevel = jlptLevel
        self.transcript = transcript
        self.allChoices = ([correctAnswer] + distractors).shuffled()
    }

    /// Checks whether the given answer is correct.
    /// - Parameter answer: The selected answer string.
    /// - Returns: True if the answer matches the correct answer.
    public func isCorrect(answer: String) -> Bool {
        answer == correctAnswer
    }
}

// MARK: - VocabularyItem

/// A vocabulary item used for generating listening exercises.
public struct VocabularyItem: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// The kanji or written form.
    public let japanese: String

    /// The hiragana/katakana reading.
    public let reading: String

    /// The English meaning.
    public let meaning: String

    /// The JLPT level of this vocabulary item.
    public let jlptLevel: JLPTLevel

    public init(
        id: UUID = UUID(),
        japanese: String,
        reading: String,
        meaning: String,
        jlptLevel: JLPTLevel
    ) {
        self.id = id
        self.japanese = japanese
        self.reading = reading
        self.meaning = meaning
        self.jlptLevel = jlptLevel
    }
}

// MARK: - ListeningExercisePassage

/// A longer listening passage for passage comprehension exercises.
public struct ListeningExercisePassage: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// The full Japanese text of the passage.
    public let text: String

    /// The comprehension question.
    public let question: String

    /// The correct answer.
    public let correctAnswer: String

    /// Distractor answers.
    public let distractors: [String]

    /// The transcript text (may include kanji that requires furigana).
    public let transcript: String

    /// The JLPT level of this passage.
    public let jlptLevel: JLPTLevel

    public init(
        id: UUID = UUID(),
        text: String,
        question: String,
        correctAnswer: String,
        distractors: [String],
        transcript: String,
        jlptLevel: JLPTLevel
    ) {
        self.id = id
        self.text = text
        self.question = question
        self.correctAnswer = correctAnswer
        self.distractors = distractors
        self.transcript = transcript
        self.jlptLevel = jlptLevel
    }
}

// MARK: - ListeningExerciseGenerator

/// Generates listening exercises from vocabulary and passage content.
public enum ListeningExerciseGenerator {

    /// Number of distractor choices for each exercise.
    private static let distractorCount = 3

    /// Generates a word recognition exercise ("What did you hear?").
    /// - Parameters:
    ///   - target: The vocabulary item to test.
    ///   - pool: All available vocabulary items (for generating distractors).
    /// - Returns: A listening exercise.
    public static func generateWordRecognition(
        target: VocabularyItem,
        pool: [VocabularyItem]
    ) -> ListeningExercise {
        let distractors = selectDistractors(target: target, pool: pool)

        return ListeningExercise(
            audioText: target.reading,
            question: "What did you hear?",
            correctAnswer: target.meaning,
            distractors: distractors,
            exerciseType: .wordRecognition,
            jlptLevel: target.jlptLevel
        )
    }

    /// Generates a meaning selection exercise ("Select the meaning").
    /// - Parameters:
    ///   - target: The vocabulary item to test.
    ///   - pool: All available vocabulary items (for generating distractors).
    /// - Returns: A listening exercise.
    public static func generateMeaningSelection(
        target: VocabularyItem,
        pool: [VocabularyItem]
    ) -> ListeningExercise {
        let distractors = selectDistractors(target: target, pool: pool)

        return ListeningExercise(
            audioText: target.reading,
            question: "Select the meaning",
            correctAnswer: target.meaning,
            distractors: distractors,
            exerciseType: .meaningSelection,
            jlptLevel: target.jlptLevel
        )
    }

    /// Generates a passage comprehension exercise.
    /// - Parameter passage: The listening passage with pre-authored question and answers.
    /// - Returns: A listening exercise.
    public static func generatePassageComprehension(
        passage: ListeningExercisePassage
    ) -> ListeningExercise {
        ListeningExercise(
            audioText: passage.text,
            question: passage.question,
            correctAnswer: passage.correctAnswer,
            distractors: passage.distractors,
            exerciseType: .passageComprehension,
            jlptLevel: passage.jlptLevel,
            transcript: passage.transcript
        )
    }

    // MARK: - Private Helpers

    /// Selects distractor meanings from the pool.
    ///
    /// Excludes not only the correct answer but **every word that shares the
    /// target's reading**, because both exercises play `target.reading` as the
    /// audio: a homophone's meaning is a correct answer to what the learner
    /// actually heard, so offering it makes the question unanswerable and
    /// marks a right answer wrong.
    ///
    /// This filter used to be `meaning != correctMeaning` alone, and that was
    /// safe only by accident — the 205-word bundle happened to contain **zero**
    /// shared readings. The 2026-08-16 expansion to 693 words brought 26
    /// readings shared by 54 words (あつい → 暑い / 熱い / 厚い, おじ → 伯父 /
    /// 叔父, かわ → 川 / 河), which turned the accident into a live defect.
    /// Measured, not assumed: see `JOURNAL.md` and the guard test in
    /// `ListeningExerciseTests`.
    ///
    /// Deduplicates on meaning too: 朝ご飯 and 朝御飯 are different words with
    /// the identical gloss "breakfast", and two identical options in a
    /// four-choice question is its own kind of broken.
    private static func selectDistractors(
        target: VocabularyItem,
        pool: [VocabularyItem]
    ) -> [String] {
        var seen: Set<String> = [target.meaning]
        var candidates: [String] = []
        for item in pool.shuffled() where item.reading != target.reading {
            guard seen.insert(item.meaning).inserted else { continue }
            candidates.append(item.meaning)
            if candidates.count == distractorCount { break }
        }
        return candidates
    }
}
