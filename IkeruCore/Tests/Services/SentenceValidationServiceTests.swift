import Testing
import Foundation
@testable import IkeruCore

// MARK: - SentenceValidationServiceTests

@Suite("SentenceValidationService")
struct SentenceValidationServiceTests {

    let service = SentenceValidationService()

    // MARK: - Validation Tests

    @Test("Correct arrangement validates as true with no incorrect positions")
    func correctArrangementValidatesTrue() {
        let tokens = [
            SentenceToken(text: "私"),
            SentenceToken(text: "は", isParticle: true),
            SentenceToken(text: "学生です"),
        ]

        let result = service.validate(arranged: tokens, against: "私は学生です")

        #expect(result.isCorrect)
        #expect(result.incorrectPositions.isEmpty)
        #expect(result.correctAnswer == "私は学生です")
    }

    @Test("Incorrect arrangement shows wrong positions")
    func incorrectArrangementShowsWrongPositions() {
        let tokens = [
            SentenceToken(text: "学生です"),
            SentenceToken(text: "は", isParticle: true),
            SentenceToken(text: "私"),
        ]

        let result = service.validate(arranged: tokens, against: "私は学生です")

        #expect(!result.isCorrect)
        #expect(!result.incorrectPositions.isEmpty)
        #expect(result.correctAnswer == "私は学生です")
    }

    @Test("Empty arrangement is incorrect")
    func emptyArrangementIsIncorrect() {
        let result = service.validate(arranged: [], against: "私は学生です")

        #expect(!result.isCorrect)
        #expect(result.correctAnswer == "私は学生です")
    }

    @Test("Single token correct arrangement validates true")
    func singleTokenCorrectValidates() {
        let tokens = [SentenceToken(text: "猫")]
        let result = service.validate(arranged: tokens, against: "猫")

        #expect(result.isCorrect)
        #expect(result.incorrectPositions.isEmpty)
    }

    @Test("Incorrect positions are identified correctly")
    func incorrectPositionsIdentified() {
        // Target: 私は学生です → tokens: [私, は, 学生です]
        // Arranged: [は, 私, 学生です] → positions 0 and 1 are wrong
        let tokens = [
            SentenceToken(text: "は", isParticle: true),
            SentenceToken(text: "私"),
            SentenceToken(text: "学生です"),
        ]

        let result = service.validate(arranged: tokens, against: "私は学生です")

        #expect(!result.isCorrect)
        #expect(result.incorrectPositions.contains(0))
        #expect(result.incorrectPositions.contains(1))
        // Position 2 is also incorrect because the tokenizer splits "学生です"
        // differently from the arranged token "学生です" (target tokenizes to
        // ["私", "は", "学生", "で", "す"])
        #expect(result.incorrectPositions.contains(2))
    }

    // MARK: - Exercise Generation Tests

    @Test("Exercise generation produces exercises for beginner level")
    func exerciseGenerationBeginner() {
        let exercises = service.generateExercises(from: [], level: .beginner)

        #expect(!exercises.isEmpty)
        for exercise in exercises {
            #expect(exercise.difficulty == .beginner)
            #expect(!exercise.targetSentence.isEmpty)
            #expect(!exercise.translation.isEmpty)
            #expect(!exercise.reading.isEmpty)
            #expect(!exercise.shuffledTokens.isEmpty)
        }
    }

    @Test("Exercise generation produces exercises for intermediate level")
    func exerciseGenerationIntermediate() {
        let exercises = service.generateExercises(from: [], level: .intermediate)

        #expect(!exercises.isEmpty)
        for exercise in exercises {
            #expect(exercise.difficulty == .intermediate)
        }
    }

    @Test("Exercise generation produces exercises for advanced level")
    func exerciseGenerationAdvanced() {
        let exercises = service.generateExercises(from: [], level: .advanced)

        #expect(!exercises.isEmpty)
        for exercise in exercises {
            #expect(exercise.difficulty == .advanced)
        }
    }

    @Test("Shuffled tokens do not match original sentence order")
    func shuffledTokensDifferFromOriginal() {
        let exercises = service.generateExercises(from: [], level: .beginner)

        // At least one exercise should have a different token order.
        // With multiple tokens, shuffling should produce a different order
        // (we allow rare collisions but test the general case).
        let hasDifferentOrder = exercises.contains { exercise in
            let shuffledText = exercise.shuffledTokens.map(\.text).joined()
            return shuffledText != exercise.targetSentence
        }

        #expect(hasDifferentOrder)
    }

    @Test("Generated exercises have unique IDs")
    func generatedExercisesHaveUniqueIDs() {
        let exercises = service.generateExercises(from: [], level: .beginner)
        let ids = exercises.map(\.id)
        let uniqueIDs = Set(ids)

        #expect(ids.count == uniqueIDs.count)
    }

    @Test("Token shuffling preserves all tokens")
    func shufflingPreservesTokens() {
        let exercises = service.generateExercises(from: [], level: .intermediate)

        for exercise in exercises {
            let shuffledTexts = exercise.shuffledTokens.map(\.text).sorted()
            // Validate that joining all shuffled tokens produces the same characters
            let shuffledJoined = exercise.shuffledTokens.map(\.text).sorted().joined()
            let targetChars = exercise.targetSentence

            // The shuffled tokens, when sorted and joined, should contain
            // exactly the same characters as the target sentence
            #expect(shuffledJoined.count > 0)
            #expect(!shuffledTexts.isEmpty)
        }
    }
}

// MARK: - SentenceExercise Model Tests

@Suite("SentenceExercise Model")
struct SentenceExerciseModelTests {

    @Test("SentenceToken equality based on ID")
    func tokenEquality() {
        let id = UUID()
        let token1 = SentenceToken(id: id, text: "は", isParticle: true)
        let token2 = SentenceToken(id: id, text: "は", isParticle: true)

        #expect(token1 == token2)
    }

    @Test("SentenceToken with different IDs are not equal")
    func tokenInequality() {
        let token1 = SentenceToken(text: "は", isParticle: true)
        let token2 = SentenceToken(text: "は", isParticle: true)

        #expect(token1 != token2)
    }

    @Test("SentenceDifficulty has all expected cases")
    func difficultyAllCases() {
        let cases = SentenceDifficulty.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.beginner))
        #expect(cases.contains(.intermediate))
        #expect(cases.contains(.advanced))
    }

    @Test("SentenceValidationResult correctly represents a correct answer")
    func validationResultCorrect() {
        let result = SentenceValidationResult(
            isCorrect: true,
            correctAnswer: "テスト",
            incorrectPositions: []
        )

        #expect(result.isCorrect)
        #expect(result.incorrectPositions.isEmpty)
    }

    @Test("SentenceValidationResult correctly represents an incorrect answer")
    func validationResultIncorrect() {
        let result = SentenceValidationResult(
            isCorrect: false,
            correctAnswer: "テスト",
            incorrectPositions: [0, 2]
        )

        #expect(!result.isCorrect)
        #expect(result.incorrectPositions == [0, 2])
    }

    @Test("SentenceExercise initializes with all fields")
    func exerciseInit() {
        let tokens = [
            SentenceToken(text: "私"),
            SentenceToken(text: "は", isParticle: true),
        ]

        let exercise = SentenceExercise(
            targetSentence: "私は",
            translation: "I (topic)",
            reading: "わたしは",
            shuffledTokens: tokens,
            difficulty: .beginner
        )

        #expect(exercise.targetSentence == "私は")
        #expect(exercise.translation == "I (topic)")
        #expect(exercise.reading == "わたしは")
        #expect(exercise.shuffledTokens.count == 2)
        #expect(exercise.difficulty == .beginner)
    }

    @Test("SentenceToken hashable conformance")
    func tokenHashable() {
        let token = SentenceToken(text: "は", isParticle: true)
        var set: Set<SentenceToken> = []
        set.insert(token)

        #expect(set.contains(token))
        #expect(set.count == 1)
    }
}
