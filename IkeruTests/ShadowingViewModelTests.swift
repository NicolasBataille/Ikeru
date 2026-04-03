#if canImport(Speech)
import Testing
import SwiftUI
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("ShadowingViewModel")
@MainActor
struct ShadowingViewModelTests {

    // MARK: - Helpers

    private func makeSampleVocabulary() -> [VocabularyItem] {
        [
            VocabularyItem(japanese: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5),
            VocabularyItem(japanese: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5),
            VocabularyItem(japanese: "鳥", reading: "とり", meaning: "bird", jlptLevel: .n5),
            VocabularyItem(japanese: "魚", reading: "さかな", meaning: "fish", jlptLevel: .n5)
        ]
    }

    private func makeViewModel() -> ShadowingViewModel {
        ShadowingViewModel(
            audioService: AudioService(),
            speechService: SpeechRecognitionService(),
            vocabulary: makeSampleVocabulary()
        )
    }

    // MARK: - Initial State Tests

    @Test("ViewModel initializes with default state")
    func defaultState() {
        let vm = makeViewModel()
        #expect(vm.currentExercise == nil)
        #expect(vm.exercisePhase == .listen)
        #expect(vm.isPlaying == false)
        #expect(vm.isRecording == false)
        #expect(vm.shadowingResult == nil)
        #expect(vm.playbackRate == .normal)
        #expect(vm.loadingState.isIdle)
    }

    // MARK: - Exercise Loading Tests

    @Test("loadExercise sets exercise and transitions to loaded")
    func loadExercise() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n5)

        #expect(vm.currentExercise != nil)
        #expect(vm.loadingState.isLoaded)
        #expect(vm.exercisePhase == .listen)
        #expect(vm.shadowingResult == nil)
    }

    @Test("loadExercise with no matching vocabulary stays idle")
    func loadExerciseNoMatch() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n1)

        #expect(vm.currentExercise == nil)
        #expect(vm.loadingState.isIdle)
    }

    @Test("loadExercise resets previous result")
    func loadExerciseResetsResult() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n5)

        #expect(vm.shadowingResult == nil)
        #expect(vm.exercisePhase == .listen)
    }

    // MARK: - Playback Rate Tests

    @Test("setPlaybackRate updates rate")
    func setPlaybackRate() {
        let vm = makeViewModel()
        vm.setPlaybackRate(.slow)
        #expect(vm.playbackRate == .slow)
    }

    @Test("setPlaybackRate with all rates", arguments: PlaybackRate.allCases)
    func setAllPlaybackRates(rate: PlaybackRate) {
        let vm = makeViewModel()
        vm.setPlaybackRate(rate)
        #expect(vm.playbackRate == rate)
    }

    // MARK: - Retry Tests

    @Test("retryExercise resets to listen phase")
    func retryExercise() async {
        let vm = makeViewModel()
        await vm.loadExercise(difficulty: .word, level: .n5)

        vm.retryExercise()

        #expect(vm.exercisePhase == .listen)
        #expect(vm.shadowingResult == nil)
    }

    // MARK: - Phase Transitions

    @Test("Exercise phase starts at listen")
    func initialPhase() {
        let vm = makeViewModel()
        #expect(vm.exercisePhase == .listen)
    }

    // MARK: - ExercisePhase Tests

    @Test("ExercisePhase supports equality")
    func phaseEquality() {
        #expect(ExercisePhase.listen == ExercisePhase.listen)
        #expect(ExercisePhase.record == ExercisePhase.record)
        #expect(ExercisePhase.feedback == ExercisePhase.feedback)
        #expect(ExercisePhase.listen != ExercisePhase.record)
    }

    // MARK: - Teardown

    @Test("tearDown does not crash")
    func tearDown() {
        let vm = makeViewModel()
        vm.tearDown()
        // Verify no crash and recording is stopped
        #expect(vm.isRecording == false)
    }
}

#endif
