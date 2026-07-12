import Testing
import Foundation
@testable import IkeruCore

@Suite("DefaultSessionPlanner — Home recommendation")
struct DefaultSessionPlannerHomeTests {

    private let planner = DefaultSessionPlanner()

    @Test("Home session schedules only allowlisted (Tier-1 + SRS) kinds, never Tier-2/3")
    func homeSessionAllowlisted() async {
        let cards = (0..<30).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        // Phase 4.1: `finalize` is now an allowlist, not an SRS-only filter.
        // Tier-1 drill kinds MAY appear (they have wired views); the still-
        // unwired Tier-2/3 kinds must NOT. There must be some items (30 due
        // cards feed the review wave).
        #expect(plan.exercises.count > 0)
        let allAllowlisted = plan.exercises.allSatisfy { DefaultSessionPlanner.isLive($0) }
        #expect(allAllowlisted, "expected only allowlisted (Tier-1 + SRS) kinds, got \(plan.exercises)")

        // Explicitly: no filtered (Tier-2/3) kind ever survives finalize.
        let filtered = plan.exercises.filter { !DefaultSessionPlanner.isLive($0) }
        #expect(filtered.isEmpty, "Tier-2/3 kinds must be filtered: \(filtered)")
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

    @Test("Review wave drills most-overdue cards first, whatever the input order")
    func reviewsRespectDueOrder() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Input deliberately in reverse due order: latest-due card first.
        let cards = (0..<30).map { i in
            fixtureDueCard(dueDate: base.addingTimeInterval(TimeInterval((29 - i) * 3_600)))
        }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        let reviewedDueDates = plan.exercises.compactMap { item -> Date? in
            if case .srsReview(let card) = item { return card.dueDate }
            return nil
        }
        #expect(reviewedDueDates.count > 1)
        #expect(reviewedDueDates == reviewedDueDates.sorted())
        let expected = Array(cards.map(\.dueDate).sorted().prefix(reviewedDueDates.count))
        #expect(reviewedDueDates == expected)
    }

    private func fixtureDueCard(dueDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> CardDTO {
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
            dueDate: dueDate,
            lapseCount: 0,
            leechFlag: false
        )
    }
}

@Suite("DefaultSessionPlanner — Study custom")
struct DefaultSessionPlannerStudyTests {

    private let planner = DefaultSessionPlanner()

    @Test("Study-custom of still-filtered (Tier-2/3) types yields an empty session")
    func studyCustomPlaceholderOnlyIsEmpty() async {
        // study-custom synthesises only the selected typed exercises. Here they
        // resolve to still-filtered kinds — kanaStudy needs a kanji card (none
        // in this vocabulary-only pool → nil) and vocabularyStudy is Tier-2
        // (filtered) — so after the allowlist the plan is empty.
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

    @Test("Still-filtered (Tier-2/3) exercise types are never scheduled")
    func filteredTypesNeverScheduled() async {
        // speakingPractice → .speakingExercise (Tier-2) and grammarExercise →
        // .grammarExercise (Tier-3) are still filtered; kanaStudy needs a kanji
        // card (none here) so it synthesises nothing. Nothing survives finalize.
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
        // Post-allowlist assertion: no NON-allowlisted (Tier-2/3) kind appears.
        let filtered = plan.exercises.filter { !DefaultSessionPlanner.isLive($0) }
        #expect(filtered.isEmpty, "Tier-2/3 exercises should be filtered: \(filtered)")
    }

    @Test("Tier-1 sentenceConstruction survives finalize (allowlist un-filters it)")
    func tier1SentenceConstructionSurvives() async {
        // sentenceConstruction is self-sufficient (built-in templates, no card
        // needed) and is a wired Tier-1 drill, so a study-custom session that
        // selects it must now schedule real .sentenceConstruction items — the
        // positive counterpart to the filtered-kinds assertions above.
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.sentenceConstruction],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        #expect(!plan.exercises.isEmpty)
        let allSentence = plan.exercises.allSatisfy {
            if case .sentenceConstruction = $0 { return true } else { return false }
        }
        #expect(allSentence, "expected .sentenceConstruction items, got \(plan.exercises)")
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
