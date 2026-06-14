import Testing
import Foundation
@testable import IkeruCore

@Suite("DefaultSessionPlanner — Home recommendation")
struct DefaultSessionPlannerHomeTests {

    private let planner = DefaultSessionPlanner()

    @Test("Home session contains only SRS review (placeholder exercises filtered)")
    func srsOnlyHomeSession() async {
        let cards = (0..<30).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        // Only SRS flashcard review is a real in-session exercise today; the
        // planner filters out the placeholder exercise kinds. Every item must
        // be an SRS review and there must be some (30 cards are due).
        #expect(plan.exercises.count > 0)
        let allSRS = plan.exercises.allSatisfy {
            if case .srsReview = $0 { return true } else { return false }
        }
        #expect(allSRS, "expected only .srsReview, got \(plan.exercises)")
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

    @Test("Study-custom of placeholder-only types yields an empty session")
    func studyCustomPlaceholderOnlyIsEmpty() async {
        // study-custom synthesises only the selected typed exercises; none of
        // them are real yet, so after the SRS-only filter the plan is empty.
        // (The Compose feature is deferred until real exercise content exists.)
        let cards = (0..<10).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .vocabularyStudy],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)
        #expect(plan.exercises.isEmpty)
    }

    @Test("Placeholder (non-SRS) exercise types are never scheduled")
    func placeholderTypesNeverScheduled() async {
        let cards = (0..<10).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .speakingPractice, .grammarExercise],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)
        let nonSRS = plan.exercises.filter {
            if case .srsReview = $0 { return false } else { return true }
        }
        #expect(nonSRS.isEmpty, "non-SRS exercises should be filtered: \(nonSRS)")
    }

    private func fixtureDueCard() -> CardDTO {
        CardDTO(
            id: UUID(),
            front: "x",
            back: "y",
            type: .vocabulary,
            fsrsState: FSRSState(difficulty: 5, stability: 5, reps: 1, lapses: 0, lastReview: nil),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
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
