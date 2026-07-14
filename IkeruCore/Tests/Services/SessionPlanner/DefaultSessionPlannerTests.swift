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

    /// Profile that forces `.writing` as the lowest-balance skill (used to
    /// steer the booster segment onto a *live* type — `.sentenceConstruction`
    /// — so this suite can observe it surviving `finalize` and interleaving
    /// with the review wave).
    private func writingBoosterProfile(jlptLevel: JLPTLevel = .n4) -> LearnerSnapshot {
        LearnerSnapshot(
            jlptLevel: jlptLevel,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 1.0, .listening: 1.0, .speaking: 1.0, .writing: 0.0],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
    }

    /// Coarse label for an `ExerciseItem`'s case, ignoring its (possibly
    /// non-deterministic, e.g. random `UUID()`) payload — used to compare
    /// plan *shape* across calls without depending on synthesised content IDs.
    private func kindLabel(_ item: ExerciseItem) -> String {
        switch item {
        case .srsReview: "srsReview"
        case .kanjiStudy: "kanjiStudy"
        case .grammarExercise: "grammarExercise"
        case .vocabularyStudy: "vocabularyStudy"
        case .fillInBlank: "fillInBlank"
        case .readingPassage: "readingPassage"
        case .writingPractice: "writingPractice"
        case .listeningExercise: "listeningExercise"
        case .speakingExercise: "speakingExercise"
        case .sentenceConstruction: "sentenceConstruction"
        }
    }

    @Test("Home session interleaves review + booster segments instead of scheduling four contiguous blocks")
    func homeSessionInterleavesSegments() async throws {
        // 40 already-started due cards feed a review wave large enough that,
        // absent interleaving, it would occupy one uninterrupted block before
        // any booster item ever appeared.
        let cards = (0..<40).map { _ in fixtureDueCard() }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 20,
            profile: writingBoosterProfile(),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        let kinds = plan.exercises.map(kindLabel)
        try #require(kinds.contains("srsReview"), "expected review items, got \(kinds)")
        try #require(kinds.contains("sentenceConstruction"), "expected a live booster item (writing → sentenceConstruction), got \(kinds)")

        let firstBoosterIndex = kinds.firstIndex(of: "sentenceConstruction")!
        let lastReviewIndex = kinds.lastIndex(of: "srsReview")!
        #expect(
            firstBoosterIndex < lastReviewIndex,
            "expected booster items interleaved among reviews, not appended after every review: \(kinds)"
        )
    }

    @Test("Home session merge order is deterministic — identical inputs produce identical plan shape")
    func homeSessionInterleaveIsDeterministic() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let cards = (0..<40).map { i in
            fixtureDueCard(dueDate: base.addingTimeInterval(TimeInterval(i * 3_600)))
        }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 20,
            profile: writingBoosterProfile(),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )

        let planA = await planner.compose(inputs: inputs)
        let planB = await planner.compose(inputs: inputs)

        // The plan's *shape* — kind sequence, skill sequence, counts, timing,
        // and breakdown — must be identical across calls with the same
        // inputs. (Synthesised placeholder content for non-card-backed kinds
        // uses a fresh `UUID()` per call by design — see the type's doc
        // comment — so this compares shape, not raw payload equality.)
        #expect(planA.exercises.count == planB.exercises.count)
        #expect(planA.exercises.map(kindLabel) == planB.exercises.map(kindLabel))
        #expect(planA.exercises.map(\.skill) == planB.exercises.map(\.skill))
        #expect(planA.estimatedDurationMinutes == planB.estimatedDurationMinutes)
        #expect(planA.exerciseBreakdown == planB.exerciseBreakdown)

        // Review items are fully deterministic (no `randomElement()` in
        // `pickReviews`), so those must match exactly, in the same order.
        let reviewA = planA.exercises.compactMap { item -> CardDTO? in
            if case .srsReview(let card) = item { return card }
            return nil
        }
        let reviewB = planB.exercises.compactMap { item -> CardDTO? in
            if case .srsReview(let card) = item { return card }
            return nil
        }
        #expect(reviewA == reviewB)
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
        // resolve to non-scheduling kinds — kanaStudy synthesises nothing (kana
        // is not an SRS card, so there is no in-session unit — see
        // kanaStudyNeverSynthesisesKanjiDrill) and grammarExercise is Tier-3
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
        // .fillInBlank (Tier-3) remain filtered; kanaStudy synthesises nothing
        // (kana is not an SRS card — see kanaStudyNeverSynthesisesKanjiDrill).
        // Nothing survives finalize.
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

    @Test("kanaStudy never synthesises a kanji drill, even when kanji cards are present")
    func kanaStudyNeverSynthesisesKanjiDrill() async {
        // Regression: kanaStudy used to share a branch with kanjiStudy and return
        // .kanjiStudy(card) from a kanji card — a kana request producing a kanji
        // handwriting drill on the wrong card type. Kana is not an SRS card, so a
        // kana study request must synthesise nothing, NOT a kanji drill. Supply
        // kanji cards (the pool that would have been mis-used) and assert no
        // .kanjiStudy leaks in and the plan is empty.
        let kanjiCards = (0..<10).map { _ in fixtureKanjiCard() }
        let inputs = SessionPlannerInputs(
            source: .studyCustom(
                types: [.kanaStudy],
                jlptLevels: [.n5]
            ),
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: kanjiCards
        )
        let plan = await planner.compose(inputs: inputs)
        let kanjiDrills = plan.exercises.filter {
            if case .kanjiStudy = $0 { return true } else { return false }
        }
        #expect(kanjiDrills.isEmpty, "kanaStudy must not synthesise a kanjiStudy: \(plan.exercises)")
        #expect(plan.exercises.isEmpty)
    }

    private func fixtureKanjiCard() -> CardDTO {
        CardDTO(
            id: UUID(),
            front: "日",
            back: "day",
            type: .kanji,
            fsrsState: FSRSState(difficulty: 5, stability: 5, reps: 1, lapses: 0, lastReview: nil),
            easeFactor: 2.5,
            interval: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            lapseCount: 0,
            leechFlag: false
        )
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
