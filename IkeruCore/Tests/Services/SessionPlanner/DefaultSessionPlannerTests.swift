import Testing
import Foundation
@testable import IkeruCore

@Suite("DefaultSessionPlanner — Home recommendation")
struct DefaultSessionPlannerHomeTests {

    private let planner = DefaultSessionPlanner()

    @Test("Home session schedules only allowlisted (Tier-1/2 + SRS) kinds, never filtered ones")
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

        // Phase 4.1: `finalize` is an allowlist, not an SRS-only filter. Wired
        // drill kinds (Tier-1 + Tier-2 audio) MAY appear; the still-unwired
        // kinds (vocabularyStudy + Tier-3) must NOT. There must be some items
        // (30 due cards feed the review wave).
        #expect(plan.exercises.count > 0)
        let allAllowlisted = plan.exercises.allSatisfy { DefaultSessionPlanner.isLive($0) }
        #expect(allAllowlisted, "expected only allowlisted (Tier-1/2 + SRS) kinds, got \(plan.exercises)")

        // Explicitly: no still-filtered kind ever survives finalize.
        let filtered = plan.exercises.filter { !DefaultSessionPlanner.isLive($0) }
        #expect(filtered.isEmpty, "still-filtered kinds must not appear: \(filtered)")
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

    @Test("Study-custom of still-filtered (Tier-3) types yields an empty session")
    func studyCustomPlaceholderOnlyIsEmpty() async {
        // study-custom synthesises only the selected typed exercises. Here they
        // resolve to still-filtered kinds — kanaStudy needs a kanji card (none
        // in this vocabulary-only pool → nil) and grammarExercise is Tier-3
        // (filtered) — so after the allowlist the plan is empty. (vocabularyStudy
        // is now LIVE — see vocabularyStudySurvives — so it is excluded here.)
        let cards = (0..<10).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .grammarExercise],
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

    @Test("Still-filtered (Tier-3) exercise types are never scheduled")
    func filteredTypesNeverScheduled() async {
        // grammarExercise → .grammarExercise (Tier-3) and fillInBlank →
        // .fillInBlank (Tier-3) remain filtered; kanaStudy needs a kanji card
        // (none here) so it synthesises nothing. Nothing survives finalize.
        // (speakingPractice / listeningSubtitled / vocabularyStudy are now LIVE
        // — see tier2AudioDrillsSurvive / vocabularyStudySurvives — so they are
        // deliberately excluded here.)
        let cards = (0..<10).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy, .grammarExercise, .fillInBlank],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)
        // Post-allowlist assertion: no NON-allowlisted (still-filtered) kind appears.
        let filtered = plan.exercises.filter { !DefaultSessionPlanner.isLive($0) }
        #expect(filtered.isEmpty, "still-filtered exercises should not appear: \(filtered)")
    }

    @Test("Tier-2 speaking/listening survive finalize (allowlist un-filters them)")
    func tier2AudioDrillsSurvive() async {
        // speakingPractice → .speakingExercise and listeningSubtitled →
        // .listeningExercise are now wired Tier-2 drills, so a study-custom
        // session that selects them must schedule real audio-drill items — the
        // positive counterpart to filteredTypesNeverScheduled.
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.speakingPractice, .listeningSubtitled],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        #expect(!plan.exercises.isEmpty)
        let allAudio = plan.exercises.allSatisfy {
            switch $0 {
            case .speakingExercise, .listeningExercise: return true
            default: return false
            }
        }
        #expect(allAudio, "expected only .speakingExercise/.listeningExercise, got \(plan.exercises)")
    }

    @Test("Tier-2 vocabularyStudy survives finalize (allowlist un-filters it)")
    func vocabularyStudySurvives() async {
        // vocabularyStudy → .vocabularyStudy is now a wired Tier-2 drill
        // (VocabularyRecallView, XP-only), so a study-custom session that
        // selects it must schedule real .vocabularyStudy items — the positive
        // counterpart to filteredTypesNeverScheduled. It needs no backing card
        // (the recall question is built from the session vocabulary pool at
        // render time), so an empty card pool still yields items.
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.vocabularyStudy],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: []
        )
        let plan = await planner.compose(inputs: inputs)
        #expect(!plan.exercises.isEmpty)
        let allVocab = plan.exercises.allSatisfy {
            if case .vocabularyStudy = $0 { return true } else { return false }
        }
        #expect(allVocab, "expected .vocabularyStudy items, got \(plan.exercises)")
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
