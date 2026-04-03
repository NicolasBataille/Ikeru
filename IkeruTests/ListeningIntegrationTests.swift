import Testing
import SwiftUI
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("Listening Integration Tests")
@MainActor
struct ListeningIntegrationTests {

    // MARK: - Helpers

    private func makeSampleVocabulary() -> [VocabularyItem] {
        [
            VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5),
            VocabularyItem(japanese: "本", reading: "ほん", meaning: "book", jlptLevel: .n5),
            VocabularyItem(japanese: "車", reading: "くるま", meaning: "car", jlptLevel: .n4),
            VocabularyItem(japanese: "電車", reading: "でんしゃ", meaning: "train", jlptLevel: .n4),
            VocabularyItem(japanese: "飛行機", reading: "ひこうき", meaning: "airplane", jlptLevel: .n4),
            VocabularyItem(japanese: "自転車", reading: "じてんしゃ", meaning: "bicycle", jlptLevel: .n4)
        ]
    }

    private func makeSamplePassages() -> [ListeningExercisePassage] {
        [
            ListeningExercisePassage(
                text: "今日は天気がいいです。公園に行きましょう。",
                question: "What does the speaker suggest?",
                correctAnswer: "Going to the park",
                distractors: ["Going home", "Going shopping", "Going to school"],
                transcript: "今日は天気がいいです。公園に行きましょう。",
                jlptLevel: .n5
            ),
            ListeningExercisePassage(
                text: "駅の近くに新しいレストランができました。",
                question: "What opened near the station?",
                correctAnswer: "A new restaurant",
                distractors: ["A new school", "A new hospital", "A new park"],
                transcript: "駅の近くに新しいレストランができました。",
                jlptLevel: .n4
            )
        ]
    }

    // MARK: - Exercise Generation Produces Valid Questions

    @Test("Exercise generation produces valid word recognition exercise with correct answers")
    func exerciseGenerationWordRecognition() async {
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

        // Exercise should have valid structure
        #expect(!exercise.audioText.isEmpty)
        #expect(!exercise.correctAnswer.isEmpty)
        #expect(exercise.distractors.count == 3)
        #expect(!exercise.distractors.contains(exercise.correctAnswer))
        #expect(exercise.exerciseType == .wordRecognition)
        #expect(exercise.jlptLevel == .n5)
    }

    @Test("Exercise generation produces plausible distractors")
    func exerciseGenerationPlausibleDistractors() async {
        let audioService = AudioService()
        let vocabulary = makeSampleVocabulary()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: vocabulary,
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .meaningSelection, level: .n5)

        guard let exercise = vm.currentExercise else {
            Issue.record("Expected exercise to be loaded")
            return
        }

        // Distractors should come from the vocabulary pool
        let allMeanings = Set(vocabulary.filter { $0.jlptLevel == .n5 }.map(\.meaning))
        for distractor in exercise.distractors {
            #expect(allMeanings.contains(distractor), "Distractor '\(distractor)' not in vocabulary pool")
        }
    }

    // MARK: - ViewModel State Transitions

    @Test("ViewModel state transitions: loading -> playing -> answered -> feedback")
    func viewModelStateTransitions() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        // Initial state
        #expect(vm.currentExercise == nil)
        #expect(vm.exerciseResult == nil)
        #expect(vm.selectedAnswer == nil)

        // Load exercise
        await vm.loadExercise(type: .wordRecognition, level: .n5)
        #expect(vm.currentExercise != nil)
        #expect(vm.loadingState.isLoaded)

        // Submit correct answer
        guard let exercise = vm.currentExercise else { return }
        vm.submitAnswer(exercise.correctAnswer)

        #expect(vm.selectedAnswer == exercise.correctAnswer)
        #expect(vm.exerciseResult == .correct)
    }

    @Test("ViewModel handles incorrect answer feedback")
    func viewModelIncorrectFeedback() async {
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

        #expect(vm.exerciseResult == .incorrect)
        #expect(vm.selectedAnswer == wrongAnswer)
    }

    // MARK: - Passage Exercises by JLPT Level

    @Test("Passage exercises load content filtered by JLPT level")
    func passageExercisesByLevel() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .passageComprehension, level: .n5)
        #expect(vm.currentExercise?.jlptLevel == .n5)

        await vm.loadExercise(type: .passageComprehension, level: .n4)
        #expect(vm.currentExercise?.jlptLevel == .n4)
    }

    @Test("Passage exercises include transcript for reveal")
    func passageExercisesIncludeTranscript() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .passageComprehension, level: .n5)
        #expect(vm.currentExercise?.transcript != nil)
        #expect(!vm.isTranscriptRevealed)

        vm.revealTranscript()
        #expect(vm.isTranscriptRevealed)
    }

    // MARK: - Playback Rate Integration

    @Test("Playback rate changes propagate to AudioService")
    func playbackRatePropagation() {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        vm.setPlaybackRate(.slow)
        #expect(vm.playbackRate == .slow)
        #expect(audioService.currentRate == .slow)

        vm.setPlaybackRate(.fast)
        #expect(vm.playbackRate == .fast)
        #expect(audioService.currentRate == .fast)
    }

    // MARK: - Silent Mode Integration

    @Test("Silent mode detection is accessible from ViewModel")
    func silentModeAccessible() {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        // Property should be accessible (actual value depends on device state)
        let _ = vm.shouldSkipAudioExercises
    }

    // MARK: - AudioService TTS Playback Tests

    @Test("AudioService initializes without crashing")
    func audioServiceInit() {
        let service = AudioService()
        #expect(service.isPlaying == false)
        #expect(service.currentRate == .normal)
    }

    @Test("AudioService stop is safe when nothing is playing")
    func audioServiceStopSafe() {
        let service = AudioService()
        service.stop()
        #expect(service.isPlaying == false)
    }

    @Test("AudioService rate change persists")
    func audioServiceRateChange() {
        let service = AudioService()
        service.currentRate = .slow
        #expect(service.currentRate == .slow)

        service.currentRate = .fast
        #expect(service.currentRate == .fast)
    }

    // MARK: - Reset Flow

    @Test("ViewModel reset clears all answer state")
    func viewModelReset() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        await vm.loadExercise(type: .wordRecognition, level: .n5)
        guard let exercise = vm.currentExercise else { return }

        vm.submitAnswer(exercise.correctAnswer)
        #expect(vm.exerciseResult != nil)

        vm.reset()
        #expect(vm.selectedAnswer == nil)
        #expect(vm.exerciseResult == nil)
        #expect(vm.isTranscriptRevealed == false)
    }

    // MARK: - Edge Cases

    @Test("Loading exercise with no matching vocabulary handles gracefully")
    func noMatchingVocabulary() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(), // All N5 and N4
            passages: makeSamplePassages()
        )

        // N1 has no vocabulary in our pool
        await vm.loadExercise(type: .wordRecognition, level: .n1)
        #expect(vm.currentExercise == nil)
    }

    @Test("Loading passage with no matching level handles gracefully")
    func noMatchingPassage() async {
        let audioService = AudioService()
        let vm = ListeningViewModel(
            audioService: audioService,
            vocabulary: makeSampleVocabulary(),
            passages: makeSamplePassages()
        )

        // N1 has no passages in our pool
        await vm.loadExercise(type: .passageComprehension, level: .n1)
        // Exercise from previous load (if any) might still be there
        // but the loading state should be idle
        #expect(vm.loadingState.isIdle)
    }
}
