#if canImport(Speech)
import Testing
import SwiftUI
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("Shadowing Integration Tests")
@MainActor
struct ShadowingIntegrationTests {

    // MARK: - Helpers

    private func makeSampleVocabulary() -> [VocabularyItem] {
        [
            VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5),
            VocabularyItem(japanese: "本", reading: "ほん", meaning: "book", jlptLevel: .n5),
            VocabularyItem(japanese: "車", reading: "くるま", meaning: "car", jlptLevel: .n4),
            VocabularyItem(japanese: "電車", reading: "でんしゃ", meaning: "train", jlptLevel: .n4)
        ]
    }

    private func makeViewModel() -> ShadowingViewModel {
        ShadowingViewModel(
            audioService: AudioService(),
            speechService: SpeechRecognitionService(),
            vocabulary: makeSampleVocabulary()
        )
    }

    // MARK: - Exercise Generation Integration

    @Test("Exercise generation produces exercises filtered by JLPT level")
    func exerciseGenerationFiltersByLevel() {
        let vocab = makeSampleVocabulary()
        let n5Exercises = ShadowingExerciseGenerator.generateExercises(
            from: vocab, difficulty: .word, level: .n5, count: 10
        )
        let n4Exercises = ShadowingExerciseGenerator.generateExercises(
            from: vocab, difficulty: .word, level: .n4, count: 10
        )

        #expect(n5Exercises.count == 5)
        #expect(n4Exercises.count == 2)
        #expect(n5Exercises.allSatisfy { $0.jlptLevel == .n5 })
        #expect(n4Exercises.allSatisfy { $0.jlptLevel == .n4 })
    }

    @Test("Exercise generation produces exercises with correct difficulty")
    func exerciseGenerationAppliesDifficulty() {
        let vocab = makeSampleVocabulary()
        let exercises = ShadowingExerciseGenerator.generateExercises(
            from: vocab, difficulty: .sentence, level: .n5, count: 3
        )
        #expect(exercises.allSatisfy { $0.difficulty == .sentence })
    }

    // MARK: - ViewModel Phase Transitions

    @Test("ViewModel transitions: listen -> load -> listen")
    func loadTransition() async {
        let vm = makeViewModel()
        #expect(vm.exercisePhase == .listen)

        await vm.loadExercise(difficulty: .word, level: .n5)

        #expect(vm.exercisePhase == .listen)
        #expect(vm.currentExercise != nil)
    }

    @Test("ViewModel retry resets to listen phase")
    func retryTransition() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n5)

        vm.retryExercise()

        #expect(vm.exercisePhase == .listen)
        #expect(vm.shadowingResult == nil)
    }

    // MARK: - Pronunciation Scoring Integration

    @Test("Scoring Japanese text pairs at various accuracy levels")
    func scoringIntegration() {
        // Perfect match
        let perfect = PronunciationScorer.score(
            recognized: "こんにちは", expected: "こんにちは"
        )
        #expect(perfect.accuracy == 1.0)

        // High accuracy (one character off)
        let high = PronunciationScorer.score(
            recognized: "こんにちわ", expected: "こんにちは"
        )
        #expect(high.accuracy >= 0.7)

        // Low accuracy
        let low = PronunciationScorer.score(
            recognized: "さようなら", expected: "こんにちは"
        )
        #expect(low.accuracy < 0.5)

        // Zero accuracy (completely different characters)
        let zero = PronunciationScorer.score(
            recognized: "あいうえお", expected: "かきくけこ"
        )
        #expect(zero.accuracy == 0.0)
    }

    @Test("Scoring handles katakana-hiragana equivalence")
    func scoringKatakanaEquivalence() {
        let result = PronunciationScorer.score(
            recognized: "ネコ", expected: "ねこ"
        )
        #expect(result.accuracy == 1.0)
    }

    // MARK: - DiffSegment Rendering Integration

    @Test("DiffSegments produce correct types for known inputs")
    func diffSegmentTypes() {
        // Exact match -> all match segments
        let exact = PronunciationScorer.score(
            recognized: "ねこ", expected: "ねこ"
        )
        let matchCount = exact.diffSegments.filter {
            if case .match = $0 { return true }
            return false
        }.count
        #expect(matchCount == 1) // Merged into one match segment

        // Missing character
        let missing = PronunciationScorer.score(
            recognized: "ね", expected: "ねこ"
        )
        let hasMissing = missing.diffSegments.contains {
            if case .missing = $0 { return true }
            return false
        }
        #expect(hasMissing)

        // Extra character
        let extra = PronunciationScorer.score(
            recognized: "ねこだ", expected: "ねこ"
        )
        let hasExtra = extra.diffSegments.contains {
            if case .extra = $0 { return true }
            return false
        }
        #expect(hasExtra)
    }

    // MARK: - Audio Session Category

    @Test("ViewModel tearDown does not crash with no active exercise")
    func tearDownNoExercise() {
        let vm = makeViewModel()
        vm.tearDown()
        #expect(vm.isRecording == false)
        #expect(vm.isPlaying == false)
    }

    @Test("ViewModel tearDown after loading exercise does not crash")
    func tearDownAfterLoad() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n5)
        vm.tearDown()
        #expect(vm.isRecording == false)
    }
}

#endif
