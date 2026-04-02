import Testing
import Foundation
@testable import IkeruCore

@Suite("SkillBalance")
struct SkillBalanceTests {

    @Test("Default targets sum to 1.0")
    func defaultTargetsSumToOne() {
        let sum = SkillBalance.defaultTargets.targets.values.reduce(0, +)
        #expect(abs(sum - 1.0) < 0.001)
    }

    @Test("Default targets have all four skills")
    func defaultTargetsAllSkills() {
        let targets = SkillBalance.defaultTargets.targets
        #expect(targets.count == 4)
        for skill in SkillType.allCases {
            #expect(targets[skill] != nil, "Missing skill: \(skill)")
        }
    }

    @Test("Deficit weights sum to 1.0 for any input")
    func deficitWeightsSumToOne() {
        let balance = SkillBalance.defaultTargets

        let inputs: [[SkillType: Double]] = [
            [.reading: 0.5, .writing: 0.1, .listening: 0.3, .speaking: 0.1],
            [.reading: 1.0, .writing: 0.0, .listening: 0.0, .speaking: 0.0],
            [.reading: 0.25, .writing: 0.25, .listening: 0.25, .speaking: 0.25],
            [:], // empty
        ]

        for current in inputs {
            let weights = balance.deficitWeights(current: current)
            let sum = weights.values.reduce(0, +)
            #expect(abs(sum - 1.0) < 0.001, "Weights sum to \(sum) for input \(current)")
        }
    }

    @Test("Higher deficit produces higher weight")
    func higherDeficitHigherWeight() {
        let balance = SkillBalance.defaultTargets
        let current: [SkillType: Double] = [
            .reading: 0.60, // Over target (0.30)
            .writing: 0.05, // Under target (0.20) — deficit 0.15
            .listening: 0.30, // Over target (0.25)
            .speaking: 0.05  // Under target (0.25) — deficit 0.20
        ]

        let weights = balance.deficitWeights(current: current)

        // Speaking has the highest deficit
        #expect(weights[.speaking]! > weights[.writing]!)
        // Reading and listening are over target, so deficit = 0
        #expect(weights[.reading]! < weights[.writing]!)
        #expect(weights[.listening]! < weights[.writing]!)
    }

    @Test("All skills at or above target produces equal weights")
    func allAboveTargetProducesEqual() {
        let balance = SkillBalance.defaultTargets
        let current: [SkillType: Double] = [
            .reading: 0.40,
            .writing: 0.30,
            .listening: 0.30,
            .speaking: 0.30
        ]

        let weights = balance.deficitWeights(current: current)
        let values = Array(weights.values)
        let first = values[0]
        for value in values {
            #expect(abs(value - first) < 0.001, "All weights should be equal when no deficit")
        }
    }

    @Test("Imbalance score is zero for perfect balance")
    func imbalanceScoreZero() {
        let balance = SkillBalance.defaultTargets
        let score = balance.imbalanceScore(current: balance.targets)
        #expect(abs(score) < 0.001)
    }

    @Test("Imbalance score grows with deviation")
    func imbalanceScoreGrows() {
        let balance = SkillBalance.defaultTargets

        let small: [SkillType: Double] = [
            .reading: 0.32, .writing: 0.18, .listening: 0.25, .speaking: 0.25
        ]
        let large: [SkillType: Double] = [
            .reading: 0.90, .writing: 0.02, .listening: 0.05, .speaking: 0.03
        ]

        let smallScore = balance.imbalanceScore(current: small)
        let largeScore = balance.imbalanceScore(current: large)

        #expect(largeScore > smallScore)
    }
}

@Suite("SkillType")
struct SkillTypeTests {

    @Test("Reading and listening are receptive")
    func receptiveSkills() {
        #expect(SkillType.reading.isReceptive == true)
        #expect(SkillType.listening.isReceptive == true)
    }

    @Test("Writing and speaking are productive")
    func productiveSkills() {
        #expect(SkillType.writing.isReceptive == false)
        #expect(SkillType.speaking.isReceptive == false)
    }

    @Test("Listening and speaking require audio")
    func audioRequirement() {
        #expect(SkillType.listening.requiresAudio == true)
        #expect(SkillType.speaking.requiresAudio == true)
        #expect(SkillType.reading.requiresAudio == false)
        #expect(SkillType.writing.requiresAudio == false)
    }

    @Test("Pedagogical order: receptive before productive")
    func pedagogicalOrder() {
        let sorted = SkillType.allCases.sorted { $0.pedagogicalOrder < $1.pedagogicalOrder }
        #expect(sorted == [.reading, .listening, .writing, .speaking])
    }
}

@Suite("SessionDuration")
struct SessionDurationTests {

    @Test("Micro session classification")
    func microClassification() {
        #expect(SessionDuration.from(minutes: 1) == .micro)
        #expect(SessionDuration.from(minutes: 2) == .micro)
        #expect(SessionDuration.from(minutes: 5) == .micro)
    }

    @Test("Short session classification")
    func shortClassification() {
        #expect(SessionDuration.from(minutes: 6) == .short)
        #expect(SessionDuration.from(minutes: 10) == .short)
        #expect(SessionDuration.from(minutes: 15) == .short)
    }

    @Test("Standard session classification")
    func standardClassification() {
        #expect(SessionDuration.from(minutes: 16) == .standard)
        #expect(SessionDuration.from(minutes: 20) == .standard)
        #expect(SessionDuration.from(minutes: 29) == .standard)
    }

    @Test("Focused session classification")
    func focusedClassification() {
        #expect(SessionDuration.from(minutes: 30) == .focused)
        #expect(SessionDuration.from(minutes: 60) == .focused)
        #expect(SessionDuration.from(minutes: 120) == .focused)
    }

    @Test("Micro session SRS only")
    func microSRSOnly() {
        #expect(SessionDuration.micro.includesSupplementary == false)
        #expect(SessionDuration.micro.maxSRSCards == 10)
    }

    @Test("Short session includes supplementary")
    func shortIncludesSupplementary() {
        #expect(SessionDuration.short.includesSupplementary == true)
    }

    @Test("Focused session requires all skills")
    func focusedRequiresAllSkills() {
        #expect(SessionDuration.focused.requiresAllSkills == true)
        #expect(SessionDuration.micro.requiresAllSkills == false)
    }
}

@Suite("ExerciseItem")
struct ExerciseItemTests {

    @Test("SRS review skill is reading")
    func srsReviewSkill() {
        let card = CardDTO(
            id: UUID(),
            front: "Test",
            back: "Test",
            type: .kanji,
            fsrsState: FSRSState(),
            easeFactor: 2.5,
            interval: 0,
            dueDate: Date(),
            lapseCount: 0,
            leechFlag: false
        )
        let exercise = ExerciseItem.srsReview(card)
        #expect(exercise.skill == .reading)
        #expect(exercise.estimatedDurationSeconds == 15)
        #expect(exercise.requiresAudio == false)
    }

    @Test("Writing practice skill is writing")
    func writingPracticeSkill() {
        let exercise = ExerciseItem.writingPractice("test")
        #expect(exercise.skill == .writing)
        #expect(exercise.estimatedDurationSeconds == 90)
    }

    @Test("Listening exercise requires audio")
    func listeningRequiresAudio() {
        let exercise = ExerciseItem.listeningExercise(UUID())
        #expect(exercise.skill == .listening)
        #expect(exercise.requiresAudio == true)
    }

    @Test("Speaking exercise requires audio")
    func speakingRequiresAudio() {
        let exercise = ExerciseItem.speakingExercise(UUID())
        #expect(exercise.skill == .speaking)
        #expect(exercise.requiresAudio == true)
    }

    @Test("Kanji study skill is reading")
    func kanjiStudySkill() {
        let exercise = ExerciseItem.kanjiStudy("\u{4e00}")
        #expect(exercise.skill == .reading)
        #expect(exercise.estimatedDurationSeconds == 60)
    }

    @Test("Grammar exercise skill is reading")
    func grammarExerciseSkill() {
        let exercise = ExerciseItem.grammarExercise(UUID())
        #expect(exercise.skill == .reading)
        #expect(exercise.estimatedDurationSeconds == 45)
    }
}
