import Testing
import Foundation
@testable import IkeruCore

@Suite("ListeningExercise")
struct ListeningExerciseTests {

    // MARK: - Model Tests

    @Test("ListeningExercise stores all properties correctly")
    func exerciseStoresProperties() {
        let exercise = ListeningExercise(
            audioText: "こんにちは",
            question: "What did you hear?",
            correctAnswer: "Hello",
            distractors: ["Goodbye", "Thank you", "Sorry"],
            exerciseType: .wordRecognition,
            jlptLevel: .n5
        )

        #expect(exercise.audioText == "こんにちは")
        #expect(exercise.question == "What did you hear?")
        #expect(exercise.correctAnswer == "Hello")
        #expect(exercise.distractors.count == 3)
        #expect(exercise.exerciseType == .wordRecognition)
        #expect(exercise.jlptLevel == .n5)
    }

    @Test("ListeningExercise allChoices includes correct answer and distractors")
    func allChoicesIncludesAll() {
        let exercise = ListeningExercise(
            audioText: "ありがとう",
            question: "Select the meaning",
            correctAnswer: "Thank you",
            distractors: ["Hello", "Goodbye", "Sorry"],
            exerciseType: .meaningSelection,
            jlptLevel: .n5
        )

        let choices = exercise.allChoices
        #expect(choices.count == 4)
        #expect(choices.contains("Thank you"))
        #expect(choices.contains("Hello"))
        #expect(choices.contains("Goodbye"))
        #expect(choices.contains("Sorry"))
    }

    @Test("ListeningExercise isCorrect validates answer")
    func isCorrectValidatesAnswer() {
        let exercise = ListeningExercise(
            audioText: "さようなら",
            question: "What did you hear?",
            correctAnswer: "Goodbye",
            distractors: ["Hello", "Thank you", "Sorry"],
            exerciseType: .wordRecognition,
            jlptLevel: .n5
        )

        #expect(exercise.isCorrect(answer: "Goodbye") == true)
        #expect(exercise.isCorrect(answer: "Hello") == false)
        #expect(exercise.isCorrect(answer: "") == false)
    }

    // MARK: - ExerciseType Tests

    @Test("ListeningExerciseType has all expected cases")
    func exerciseTypeAllCases() {
        let allCases = ListeningExerciseType.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.wordRecognition))
        #expect(allCases.contains(.meaningSelection))
        #expect(allCases.contains(.passageComprehension))
    }

    // MARK: - JLPTLevel Tests

    @Test("JLPTLevel has all 5 levels")
    func jlptLevelAllCases() {
        let allCases = JLPTLevel.allCases
        #expect(allCases.count == 5)
    }

    @Test("JLPTLevel ordering from easiest to hardest", arguments: [
        (JLPTLevel.n5, 5),
        (JLPTLevel.n4, 4),
        (JLPTLevel.n3, 3),
        (JLPTLevel.n2, 2),
        (JLPTLevel.n1, 1)
    ])
    func jlptLevelOrdering(level: JLPTLevel, expectedNumber: Int) {
        #expect(level.number == expectedNumber)
    }

    @Test("JLPTLevel display labels")
    func jlptLevelDisplayLabels() {
        #expect(JLPTLevel.n5.displayLabel == "N5")
        #expect(JLPTLevel.n1.displayLabel == "N1")
    }

    // MARK: - Exercise Generator Tests

    @Test("ListeningExerciseGenerator generates word recognition exercise")
    func generatesWordRecognitionExercise() {
        let vocabulary = VocabularyItem(
            japanese: "猫",
            reading: "ねこ",
            meaning: "cat",
            jlptLevel: .n5
        )
        let allVocabulary = [
            vocabulary,
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
        ]

        let exercise = ListeningExerciseGenerator.generateWordRecognition(
            target: vocabulary,
            pool: allVocabulary
        )

        #expect(exercise.audioText == "ねこ")
        #expect(exercise.correctAnswer == "cat")
        #expect(exercise.distractors.count == 3)
        #expect(!exercise.distractors.contains("cat"))
        #expect(exercise.exerciseType == .wordRecognition)
        #expect(exercise.jlptLevel == .n5)
    }

    @Test("ListeningExerciseGenerator generates meaning selection exercise")
    func generatesMeaningSelectionExercise() {
        let vocabulary = VocabularyItem(
            japanese: "水",
            reading: "みず",
            meaning: "water",
            jlptLevel: .n5
        )
        let allVocabulary = [
            vocabulary,
            VocabularyItem(japanese: "火", reading: "ひ", meaning: "fire", jlptLevel: .n5),
            VocabularyItem(japanese: "風", reading: "かぜ", meaning: "wind", jlptLevel: .n5),
            VocabularyItem(japanese: "土", reading: "つち", meaning: "earth", jlptLevel: .n5)
        ]

        let exercise = ListeningExerciseGenerator.generateMeaningSelection(
            target: vocabulary,
            pool: allVocabulary
        )

        #expect(exercise.audioText == "みず")
        #expect(exercise.correctAnswer == "water")
        #expect(exercise.distractors.count == 3)
        #expect(exercise.exerciseType == .meaningSelection)
    }

    @Test("ListeningExerciseGenerator generates passage comprehension exercise")
    func generatesPassageComprehensionExercise() {
        let passage = ListeningExercisePassage(
            text: "今日は天気がいいです。",
            question: "How is the weather today?",
            correctAnswer: "Good",
            distractors: ["Bad", "Cold", "Hot"],
            transcript: "今日は天気がいいです。",
            jlptLevel: .n5
        )

        let exercise = ListeningExerciseGenerator.generatePassageComprehension(
            passage: passage
        )

        #expect(exercise.audioText == "今日は天気がいいです。")
        #expect(exercise.correctAnswer == "Good")
        #expect(exercise.distractors.count == 3)
        #expect(exercise.exerciseType == .passageComprehension)
        #expect(exercise.jlptLevel == .n5)
    }

    @Test("ListeningExerciseGenerator generates exercises with unique distractors")
    func generatesUniqueDistractors() {
        let vocabulary = VocabularyItem(
            japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5
        )
        let allVocabulary = [
            vocabulary,
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5),
            VocabularyItem(japanese: "馬", reading: "うま", meaning: "horse", jlptLevel: .n5)
        ]

        let exercise = ListeningExerciseGenerator.generateWordRecognition(
            target: vocabulary,
            pool: allVocabulary
        )

        let uniqueDistractors = Set(exercise.distractors)
        #expect(uniqueDistractors.count == 3)
    }
}
