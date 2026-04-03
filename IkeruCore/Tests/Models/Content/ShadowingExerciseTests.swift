import Testing
import Foundation
@testable import IkeruCore

@Suite("ShadowingExercise")
struct ShadowingExerciseTests {

    // MARK: - ShadowingDifficulty Tests

    @Suite("ShadowingDifficulty")
    struct DifficultyTests {

        @Test("All difficulty levels are comparable in correct order")
        func comparableOrder() {
            #expect(ShadowingDifficulty.word < .shortPhrase)
            #expect(ShadowingDifficulty.shortPhrase < .sentence)
            #expect(ShadowingDifficulty.sentence < .conversation)
        }

        @Test("All cases are present")
        func allCases() {
            #expect(ShadowingDifficulty.allCases.count == 4)
        }

        @Test("Display labels are human-readable", arguments: [
            (ShadowingDifficulty.word, "Word"),
            (.shortPhrase, "Short Phrase"),
            (.sentence, "Sentence"),
            (.conversation, "Conversation")
        ])
        func displayLabels(difficulty: ShadowingDifficulty, expectedLabel: String) {
            #expect(difficulty.displayLabel == expectedLabel)
        }

        @Test("Raw values are stable for persistence", arguments: [
            (ShadowingDifficulty.word, "word"),
            (.shortPhrase, "shortPhrase"),
            (.sentence, "sentence"),
            (.conversation, "conversation")
        ])
        func rawValues(difficulty: ShadowingDifficulty, expectedRaw: String) {
            #expect(difficulty.rawValue == expectedRaw)
        }
    }

    // MARK: - ShadowingMode Tests

    @Suite("ShadowingMode")
    struct ModeTests {

        @Test("All modes are present")
        func allCases() {
            #expect(ShadowingMode.allCases.count == 2)
        }

        @Test("Listen and repeat raw value is stable")
        func listenAndRepeatRawValue() {
            #expect(ShadowingMode.listenAndRepeat.rawValue == "listen_and_repeat")
        }

        @Test("Shadowing raw value is stable")
        func shadowingRawValue() {
            #expect(ShadowingMode.shadowing.rawValue == "shadowing")
        }

        @Test("Display labels are human-readable", arguments: [
            (ShadowingMode.listenAndRepeat, "Listen & Repeat"),
            (.shadowing, "Shadowing")
        ])
        func displayLabels(mode: ShadowingMode, expectedLabel: String) {
            #expect(mode.displayLabel == expectedLabel)
        }
    }

    // MARK: - ShadowingExercise Model Tests

    @Suite("Model")
    struct ModelTests {

        @Test("Exercise initializes with all properties")
        func initialization() {
            let exercise = ShadowingExercise(
                targetText: "猫",
                reading: "ねこ",
                translation: "cat",
                difficulty: .word,
                exerciseMode: .listenAndRepeat,
                jlptLevel: .n5
            )

            #expect(exercise.targetText == "猫")
            #expect(exercise.reading == "ねこ")
            #expect(exercise.translation == "cat")
            #expect(exercise.difficulty == .word)
            #expect(exercise.exerciseMode == .listenAndRepeat)
            #expect(exercise.jlptLevel == .n5)
        }

        @Test("Exercise defaults to listen-and-repeat mode")
        func defaultMode() {
            let exercise = ShadowingExercise(
                targetText: "犬",
                reading: "いぬ",
                translation: "dog",
                difficulty: .word,
                jlptLevel: .n5
            )
            #expect(exercise.exerciseMode == .listenAndRepeat)
        }

        @Test("Exercise has a unique ID")
        func uniqueId() {
            let a = ShadowingExercise(
                targetText: "猫", reading: "ねこ", translation: "cat",
                difficulty: .word, jlptLevel: .n5
            )
            let b = ShadowingExercise(
                targetText: "猫", reading: "ねこ", translation: "cat",
                difficulty: .word, jlptLevel: .n5
            )
            #expect(a.id != b.id)
        }

        @Test("Exercise supports Equatable")
        func equatable() {
            let id = UUID()
            let a = ShadowingExercise(
                id: id, targetText: "猫", reading: "ねこ", translation: "cat",
                difficulty: .word, jlptLevel: .n5
            )
            let b = ShadowingExercise(
                id: id, targetText: "猫", reading: "ねこ", translation: "cat",
                difficulty: .word, jlptLevel: .n5
            )
            #expect(a == b)
        }
    }

    // MARK: - Generator Tests

    @Suite("ShadowingExerciseGenerator")
    struct GeneratorTests {

        private func makeSampleVocabulary() -> [VocabularyItem] {
            [
                VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
                VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
                VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
                VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5),
                VocabularyItem(japanese: "本", reading: "ほん", meaning: "book", jlptLevel: .n4)
            ]
        }

        @Test("generateFromVocabulary creates word-level exercise")
        func generateFromVocabulary() {
            let item = VocabularyItem(
                japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5
            )
            let exercise = ShadowingExerciseGenerator.generateFromVocabulary(item: item)
            #expect(exercise.targetText == "猫")
            #expect(exercise.reading == "ねこ")
            #expect(exercise.translation == "cat")
            #expect(exercise.difficulty == .word)
            #expect(exercise.jlptLevel == .n5)
        }

        @Test("generateExercises filters by JLPT level")
        func filtersbyJLPTLevel() {
            let vocab = makeSampleVocabulary()
            let exercises = ShadowingExerciseGenerator.generateExercises(
                from: vocab, difficulty: .word, level: .n5, count: 10
            )
            // Only 4 N5 items in pool
            #expect(exercises.count == 4)
            #expect(exercises.allSatisfy { $0.jlptLevel == .n5 })
        }

        @Test("generateExercises respects count limit")
        func respectsCountLimit() {
            let vocab = makeSampleVocabulary()
            let exercises = ShadowingExerciseGenerator.generateExercises(
                from: vocab, difficulty: .word, level: .n5, count: 2
            )
            #expect(exercises.count == 2)
        }

        @Test("generateExercises returns empty for no matching level")
        func noMatchingLevel() {
            let vocab = makeSampleVocabulary()
            let exercises = ShadowingExerciseGenerator.generateExercises(
                from: vocab, difficulty: .word, level: .n3, count: 5
            )
            #expect(exercises.isEmpty)
        }

        @Test("generateExercises applies specified difficulty")
        func appliesDifficulty() {
            let vocab = makeSampleVocabulary()
            let exercises = ShadowingExerciseGenerator.generateExercises(
                from: vocab, difficulty: .sentence, level: .n5, count: 2
            )
            #expect(exercises.allSatisfy { $0.difficulty == .sentence })
        }

        @Test("generateExercises applies specified mode")
        func appliesMode() {
            let vocab = makeSampleVocabulary()
            let exercises = ShadowingExerciseGenerator.generateExercises(
                from: vocab, difficulty: .word, level: .n5,
                mode: .shadowing, count: 2
            )
            #expect(exercises.allSatisfy { $0.exerciseMode == .shadowing })
        }
    }
}
