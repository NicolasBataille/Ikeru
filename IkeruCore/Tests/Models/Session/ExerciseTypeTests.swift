import Testing
@testable import IkeruCore

@Suite("ExerciseType")
struct ExerciseTypeTests {

    @Test("All 12 cases are present")
    func twelveCases() {
        #expect(ExerciseType.allCases.count == 12)
    }

    @Test("Skill mapping respects spec")
    func skillMapping() {
        #expect(ExerciseType.kanaStudy.skill == .reading)
        #expect(ExerciseType.kanjiStudy.skill == .reading)
        #expect(ExerciseType.vocabularyStudy.skill == .reading)
        #expect(ExerciseType.fillInBlank.skill == .reading)
        #expect(ExerciseType.grammarExercise.skill == .reading)
        #expect(ExerciseType.readingPassage.skill == .reading)
        #expect(ExerciseType.writingPractice.skill == .writing)
        #expect(ExerciseType.sentenceConstruction.skill == .writing)
        #expect(ExerciseType.listeningSubtitled.skill == .listening)
        #expect(ExerciseType.listeningUnsubtitled.skill == .listening)
        #expect(ExerciseType.speakingPractice.skill == .speaking)
        #expect(ExerciseType.sakuraConversation.skill == .speaking)
    }

    @Test("Duration estimates are positive integers in seconds")
    func durations() {
        for type in ExerciseType.allCases {
            #expect(type.estimatedDurationSeconds > 0)
            #expect(type.estimatedDurationSeconds <= 240)
        }
    }
}
