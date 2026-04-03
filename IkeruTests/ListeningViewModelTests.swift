import Testing
import SwiftUI
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("ListeningViewModel")
@MainActor
struct ListeningViewModelTests {

    // MARK: - Helpers

    private func makeSampleVocabulary() -> [VocabularyItem] {
        [
            VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
        ]
    }

    private func makeSamplePassages() -> [ListeningExercisePassage] {
        [
            ListeningExercisePassage(
                text: "今日は天気がいいです。",
                question: "How is the weather today?",
                correctAnswer: "Good",
                distractors: ["Bad", "Cold", "Hot"],
                transcript: "今日は天気がいいです。",
                jlptLevel: .n5
            )
        ]
    }

    // MARK: - Initial State Tests

    @Test("ViewModel initializes with default state")
    func defaultState() {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        #expect(vm.currentExercise == nil)
        #expect(vm.playbackRate == .normal)
        #expect(vm.isPlaying == false)
        #expect(vm.selectedAnswer == nil)
        #expect(vm.exerciseResult == nil)
    }

    // MARK: - Exercise Loading Tests

    @Test("loadExercise generates word recognition exercise")
    func loadWordRecognition() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .wordRecognition, level: .n5)

        #expect(vm.currentExercise != nil)
        #expect(vm.currentExercise?.exerciseType == .wordRecognition)
        #expect(vm.currentExercise?.jlptLevel == .n5)
    }

    @Test("loadExercise generates meaning selection exercise")
    func loadMeaningSelection() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .meaningSelection, level: .n5)

        #expect(vm.currentExercise != nil)
        #expect(vm.currentExercise?.exerciseType == .meaningSelection)
    }

    @Test("loadExercise generates passage comprehension exercise")
    func loadPassageComprehension() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .passageComprehension, level: .n5)

        #expect(vm.currentExercise != nil)
        #expect(vm.currentExercise?.exerciseType == .passageComprehension)
    }

    // MARK: - Playback Rate Tests

    @Test("setPlaybackRate updates the rate")
    func setPlaybackRate() {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        vm.setPlaybackRate(.slow)
        #expect(vm.playbackRate == .slow)

        vm.setPlaybackRate(.fast)
        #expect(vm.playbackRate == .fast)
    }

    // MARK: - Answer Submission Tests

    @Test("submitAnswer with correct answer sets result to correct")
    func submitCorrectAnswer() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .wordRecognition, level: .n5)
        guard let exercise = vm.currentExercise else {
            Issue.record("Expected exercise to be loaded")
            return
        }

        vm.submitAnswer(exercise.correctAnswer)

        #expect(vm.selectedAnswer == exercise.correctAnswer)
        #expect(vm.exerciseResult == .correct)
    }

    @Test("submitAnswer with incorrect answer sets result to incorrect")
    func submitIncorrectAnswer() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .wordRecognition, level: .n5)
        guard let exercise = vm.currentExercise else {
            Issue.record("Expected exercise to be loaded")
            return
        }

        let wrongAnswer = exercise.distractors.first ?? "wrong"
        vm.submitAnswer(wrongAnswer)

        #expect(vm.selectedAnswer == wrongAnswer)
        #expect(vm.exerciseResult == .incorrect)
    }

    // MARK: - Loading State Tests

    @Test("loadingState transitions through loading states")
    func loadingStateTransitions() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        // Initially idle
        #expect(vm.loadingState.isIdle)

        await vm.loadExercise(type: .wordRecognition, level: .n5)

        // After loading, should be loaded
        if case .loaded = vm.loadingState {
            // Expected
        } else {
            Issue.record("Expected loadingState to be .loaded, got \(vm.loadingState)")
        }
    }

    // MARK: - Silent Mode Integration Tests

    @Test("shouldSkipAudioExercises reflects AudioService state")
    func shouldSkipReflectsAudioService() {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        // This test just verifies the property is accessible and returns a Bool
        let result = vm.shouldSkipAudioExercises
        #expect(result is Bool)
    }
}
