import Testing
import Foundation
@testable import IkeruCore

@Suite("DefaultSessionPlanner — Home recommendation")
struct DefaultSessionPlannerHomeTests {

    private let planner = DefaultSessionPlanner()

    @Test("Home plan obeys ~40/30/20/10 segment split for 15 min")
    func segmentSplit() async {
        let cards = (0..<30).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        let totalSec = plan.exercises.map(\.estimatedDurationSeconds).reduce(0, +)
        let reviewSec = plan.exercises
            .filter { if case .srsReview = $0 { return true }; return false }
            .map(\.estimatedDurationSeconds).reduce(0, +)

        #expect(totalSec >= 700 && totalSec <= 1100, "totalSec=\(totalSec)")
        let fraction = Double(reviewSec) / Double(totalSec)
        #expect(fraction >= 0.25 && fraction <= 0.55, "reviewFraction=\(fraction)")
    }

    @Test("N5 learner never gets speakingPractice in Home, even if unlocked")
    func n5VarietyPool() async {
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: LearnerSnapshot.empty.withJLPT(.n5),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        let hasSpeaking = plan.exercises.contains {
            if case .speakingExercise = $0 { return true }
            return false
        }
        #expect(hasSpeaking == false)
    }

    private func fixtureDueCard() -> CardDTO {
        CardDTO(
            id: UUID(),
            front: "x",
            back: "y",
            type: .vocabulary,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: 5,
                reps: 1,
                lapses: 0,
                lastReview: nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
    }
}

@Suite("DefaultSessionPlanner — Study custom")
struct DefaultSessionPlannerStudyTests {

    private let planner = DefaultSessionPlanner()

    @Test("Study custom respects user-selected types only")
    func studyCustomRespectsTypes() async {
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .vocabularyStudy],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        for ex in plan.exercises {
            switch ex {
            case .kanjiStudy, .vocabularyStudy: continue
            default:
                Issue.record("Unexpected exercise type: \(ex)")
            }
        }
        #expect(plan.exercises.count > 0)
    }

    @Test("Study custom drops types the user picked but isn't actually unlocked")
    func studyCustomFiltersToUnlocked() async {
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .speakingPractice],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: [.kanaStudy],
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        for ex in plan.exercises {
            if case .speakingExercise = ex { Issue.record("speaking should be filtered out") }
        }
        #expect(plan.exercises.count > 0)
    }
}

// Test-only mutation helper.
extension LearnerSnapshot {
    fileprivate func withJLPT(_ level: JLPTLevel) -> LearnerSnapshot {
        LearnerSnapshot(
            jlptLevel: level,
            vocabularyMasteredFamiliarPlus: vocabularyMasteredFamiliarPlus,
            kanjiMasteredFamiliarPlus: kanjiMasteredFamiliarPlus,
            hiraganaMastered: hiraganaMastered,
            katakanaMastered: katakanaMastered,
            grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
            listeningAccuracyLast30: listeningAccuracyLast30,
            listeningRecallLast30Days: listeningRecallLast30Days,
            skillBalances: skillBalances,
            dueCardCount: dueCardCount,
            hasNewContentQueued: hasNewContentQueued,
            lastSessionAt: lastSessionAt
        )
    }
}
