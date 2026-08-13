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
        // any booster item ever appeared. Kanji cards steer the writing
        // booster onto .writingPractice — the only live writing kind left in
        // Home pools since untaught-content types (sentenceConstruction et
        // al.) were excluded from booster/variety.
        let cards = (0..<32).map { _ in fixtureDueCard() }
            + (0..<8).map { _ in fixtureDueCard(type: .kanji) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 20,
            profile: writingBoosterProfile(jlptLevel: .n3),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        let kinds = plan.exercises.map(kindLabel)
        try #require(kinds.contains("srsReview"), "expected review items, got \(kinds)")
        try #require(kinds.contains("writingPractice"), "expected a live booster item (writing → writingPractice), got \(kinds)")

        let firstBoosterIndex = kinds.firstIndex(of: "writingPractice")!
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

    private func fixtureDueCard(
        dueDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        type: CardType = .vocabulary
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: "x",
            back: "y",
            type: type,
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

// MARK: - Foundation mode

@Suite("DefaultSessionPlanner — Foundation mode")
struct DefaultSessionPlannerFoundationTests {

    private let planner = DefaultSessionPlanner()

    @Test("Fresh kana learner gets one curriculum row — never audio/vocab drills about unknown words")
    func freshLearnerGetsFoundationRow() async {
        // 20 unseen kana, input deliberately in reverse curriculum order.
        let kana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ",
                    "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と"]
        let cards = kana.reversed().map { fixtureKanaCard(front: $0) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        // Exactly one gojūon row, in curriculum order, all SRS — no booster
        // or variety kinds (they draw on content the learner has never met).
        let fronts = plan.exercises.compactMap { item -> String? in
            if case .srsReview(let card) = item { return card.front }
            return nil
        }
        #expect(fronts == ["あ", "い", "う", "え", "お"])
        #expect(plan.exercises.count == DefaultSessionPlanner.foundationRowSize)
    }

    @Test("Foundation interleaves due reviews of begun kana with the new row")
    func foundationKeepsDueReviews() async {
        let begun = ["あ", "い", "う"].map {
            fixtureKanaCard(front: $0, reps: 2, dueDate: Date(timeIntervalSince1970: 1_700_000_000))
        }
        let unseen = ["か", "き", "く", "け", "こ", "さ", "し"].map { fixtureKanaCard(front: $0) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: begun + unseen
        )
        let plan = await planner.compose(inputs: inputs)

        let fronts = plan.exercises.compactMap { item -> String? in
            if case .srsReview(let card) = item { return card.front }
            return nil
        }
        // 3 due reviews + one 5-kana row, nothing else.
        #expect(plan.exercises.count == 8)
        #expect(Set(fronts) == Set(["あ", "い", "う", "か", "き", "く", "け", "こ"]))
        // The row itself is introduced in curriculum order.
        let introduced = fronts.filter { ["か", "き", "く", "け", "こ"].contains($0) }
        #expect(introduced == ["か", "き", "く", "け", "こ"])
    }

    @Test("Foundation holds as long as ANY chosen kana is unseen — begun count is irrelevant")
    func foundationHoldsWhileUnseenKanaRemain() async {
        // 10 begun kana (two full sessions' worth) + 10 still unseen: the
        // first cut's begun-card threshold expired here and re-served vocab
        // audio drills mid-syllabary (Nico's session 3). Foundation must hold.
        let begun = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"].map {
            fixtureKanaCard(front: $0, reps: 3, dueDate: Date(timeIntervalSince1970: 1_800_000_000))
        }
        let unseen = ["さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と"].map { fixtureKanaCard(front: $0) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: begun + unseen
        )
        let plan = await planner.compose(inputs: inputs)

        let allSRS = plan.exercises.allSatisfy { item in
            if case .srsReview = item { return true }
            return false
        }
        #expect(allSRS, "foundation sessions are SRS-only: \(plan.exercises)")
        let newFronts = plan.exercises.compactMap { item -> String? in
            if case .srsReview(let card) = item, card.fsrsState.reps == 0 { return card.front }
            return nil
        }
        #expect(newFronts == ["さ", "し", "す", "せ", "そ"])
    }

    @Test("Once every chosen kana is begun, the 40/30/20/10 mix resumes")
    func allKanaBegunResumesNormalMix() async {
        let begunKana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"].map {
            fixtureKanaCard(front: $0, reps: 3, dueDate: Date(timeIntervalSince1970: 1_700_000_000))
        }
        // Begun kanji cards give the post-foundation booster/variety pools a
        // legitimate (card-backed = actually met) content source — the
        // untaught-content types are excluded from Home pools, so without
        // kanji cards those segments are rightly empty.
        let begunKanji = (0..<5).map { i in
            fixtureKanaCard(front: "漢字\(i)", reps: 3, dueDate: Date(timeIntervalSince1970: 1_700_000_000), type: .kanji)
        }
        // An unseen NON-kana card must not re-trigger foundation.
        let unseenVocab = fixtureKanaCard(front: "食べる", reps: 0)
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 15,
            profile: LearnerSnapshot.empty.withJLPT(.n3),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: begunKana + begunKanji + [unseenVocab]
        )
        let plan = await planner.compose(inputs: inputs)

        // Normal mix: card-backed booster/variety kinds return, new drip back
        // to a single card.
        let newFronts = plan.exercises.compactMap { item -> String? in
            if case .srsReview(let card) = item, card.fsrsState.reps == 0 { return card.front }
            return nil
        }
        #expect(newFronts.count <= 1)
        let hasNonReview = plan.exercises.contains { item in
            if case .srsReview = item { return false }
            return true
        }
        #expect(hasNonReview, "expected card-backed booster/variety kinds once foundation is over")
    }

    @Test("Home never schedules untaught-content drills — even post-foundation")
    func homeNeverSchedulesUntaughtContent() async {
        let begunKana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"].map {
            fixtureKanaCard(front: $0, reps: 3, dueDate: Date(timeIntervalSince1970: 1_700_000_000))
        }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 20,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: begunKana
        )
        let plan = await planner.compose(inputs: inputs)

        // Nothing in the plan may quiz content the app never taught: no
        // listening, no speaking, no vocab recall, no sentence construction.
        let untaught = plan.exercises.filter { item in
            switch item {
            case .listeningExercise, .speakingExercise, .vocabularyStudy, .sentenceConstruction:
                return true
            default:
                return false
            }
        }
        #expect(untaught.isEmpty, "untaught-content drills leaked into Home: \(untaught)")
    }

    private func fixtureKanaCard(
        front: String,
        reps: Int = 0,
        dueDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        type: CardType = .vocabulary
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "reading",
            type: type,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: 5,
                reps: reps,
                lapses: 0,
                lastReview: reps > 0 ? dueDate : nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: dueDate,
            lapseCount: 0,
            leechFlag: false
        )
    }
}

// MARK: - Due-priority + stage profiles (P2 chantier #19/#20, 2026-08-13)

@Suite("DefaultSessionPlanner — Due-priority + stage profiles")
struct DefaultSessionPlannerDuePriorityTests {

    private let planner = DefaultSessionPlanner()

    /// Card with configurable maturity (`reps`/`stability`/`lapses`), unlike
    /// the simpler fixtures in the sibling suites — needed here to steer
    /// `MasteryLevel.from(fsrsState:)` and exercise the duration/backlog
    /// logic directly. `stability: 100, reps: 5, lapses: 0` lands on
    /// `.anchored`; `stability: 5, reps: 1` lands on `.learning` (same as
    /// the other suites' plain fixtures).
    private func card(
        front: String = "x",
        type: CardType = .vocabulary,
        dueDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        reps: Int = 1,
        stability: Double = 5,
        lapses: Int = 0
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "y",
            type: type,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: stability,
                reps: reps,
                lapses: lapses,
                lastReview: nil
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: dueDate,
            lapseCount: 0,
            leechFlag: false
        )
    }

    /// Same profile shape as the sibling suite's `writingBoosterProfile` —
    /// forces `.writing` as the lowest-balance skill so a `construction`
    /// session's booster targets a *live* type (`.writingPractice`), given
    /// kanji cards in the pool and an N3 `jlptLevel` (unlocks
    /// `.writingPractice` in `VarietyPoolResolver`).
    private func writingBoosterProfile(jlptLevel: JLPTLevel = .n3) -> LearnerSnapshot {
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

    private func isSrsReview(_ item: ExerciseItem) -> Bool {
        if case .srsReview = item { return true }
        return false
    }

    @Test("A backlog bigger than the budget consumes the ENTIRE budget in reviews — nothing left for booster/variety/new")
    func backlogBiggerThanBudgetConsumesEntireBudget() async {
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        // reps: 1, stability: 5 → `.learning` → unmodulated 15s/review.
        let cards = (0..<60).map { _ in card(dueDate: due) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 5, // 300s
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: cards
        )
        let plan = await planner.compose(inputs: inputs)

        // 300s / 15s per review = exactly 20 reviews, consuming the WHOLE
        // budget — none left over for booster/variety/new, and the 40
        // still-due cards that didn't fit are simply not this session's
        // problem to solve (they stay due for the next session).
        #expect(plan.exercises.count == 20, "expected the full 300s budget spent on review: \(plan.exercises.count) items")
        #expect(plan.exercises.allSatisfy(isSrsReview), "a backlog-dominated session must be honestly all-review: \(plan.exercises)")
    }

    @Test("Once dues are scheduled, the 30/20/10 quotas apply to what's LEFT, not to the nominal fraction of the total")
    func quotasApplyToRemainderNotTotal() async {
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        // 30 due cards (all `.learning`, 15s each) = 450s of review.
        let dueCards = (0..<22).map { _ in card(dueDate: due) }
            + (0..<8).map { _ in card(type: .kanji, dueDate: due) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 10, // 600s
            profile: writingBoosterProfile(),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: dueCards
        )
        let plan = await planner.compose(inputs: inputs)

        let reviewCount = plan.exercises.filter(isSrsReview).count
        #expect(reviewCount == 30, "all 30 due cards should fit in the 600s budget (450s spent): got \(reviewCount)")

        let writingPracticeCount = plan.exercises.filter {
            if case .writingPractice = $0 { return true }
            return false
        }.count
        // Remainder after review = 600 - 450 = 150s. One writingPractice
        // (90s) fits; a second would need 180s more (270s total), which
        // does not fit in 150s. If the booster quota were still computed
        // against the nominal 30% of the FULL 600s budget (180s) instead of
        // the 150s actually left over, TWO would fit instead of one — that
        // is exactly the bug this test pins.
        #expect(writingPracticeCount == 1, "booster should be capped by the 150s remainder (1 item), not the nominal 180s (2 items): got \(writingPracticeCount)")
    }

    @Test("Below the cruising mastery threshold, the session stays in 'construction' and still schedules the skill-balance booster")
    func belowMasteryThresholdStaysInConstruction() async {
        // 10 anchored (mature) + 10 still-learning = 50% mature — under the
        // 60% cruising threshold (`cruisingMasteryThreshold`) despite having
        // enough started cards (`cruisingMinStartedCards`) to qualify by count.
        let future = Date(timeIntervalSince1970: 1_900_000_000)
        let mature = (0..<10).map { _ in card(dueDate: future, reps: 5, stability: 100) }
        let young = (0..<10).map { _ in card(dueDate: future, reps: 1, stability: 5) }
        let kanjiCards = (0..<5).map { _ in card(type: .kanji, dueDate: future, reps: 3, stability: 5) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 10,
            profile: writingBoosterProfile(),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: mature + young + kanjiCards
        )
        let plan = await planner.compose(inputs: inputs)

        let hasWritingPractice = plan.exercises.contains {
            if case .writingPractice = $0 { return true }
            return false
        }
        #expect(hasWritingPractice, "expected the construction profile's skill-balance booster to fire below the cruising threshold: \(plan.exercises)")
    }

    @Test("Once most of the started deck is FSRS-mature, the session switches to 'croisière': reviews + a small new-content drip only, no booster/variety even with budget and candidates to spare")
    func aboveMasteryThresholdSwitchesToCruising() async {
        // 20 anchored started cards (100% mature, well past the 60%
        // threshold, and meeting `cruisingMinStartedCards`): 3 due now (a
        // small review cost) + 17 due later (ample leftover budget).
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let future = Date(timeIntervalSince1970: 1_900_000_000)
        let dueMature = (0..<3).map { _ in card(dueDate: due, reps: 5, stability: 100) }
        let notYetDueMature = (0..<17).map { _ in card(dueDate: future, reps: 5, stability: 100) }
        // Same kanji-card + skewed-skill-balance setup as
        // `belowMasteryThresholdStaysInConstruction` — if this session went
        // through `composeConstruction` instead, these would let a
        // `.writingPractice` item through.
        let kanjiCards = (0..<5).map { _ in card(type: .kanji, dueDate: future, reps: 3, stability: 5) }
        let inputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 10,
            profile: writingBoosterProfile(),
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: dueMature + notYetDueMature + kanjiCards
        )
        let plan = await planner.compose(inputs: inputs)

        #expect(!plan.exercises.isEmpty)
        #expect(plan.exercises.allSatisfy(isSrsReview), "cruising sessions only ever produce .srsReview items (review wave + new-content drip): \(plan.exercises)")
    }

    @Test("The same time budget fits more mature (anchored) reviews than young (learning) reviews")
    func matureCardsConsumeLessBudgetThanYoungCards() async {
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let youngCards = (0..<20).map { _ in card(dueDate: due, reps: 1, stability: 5) }
        let matureCards = (0..<20).map { _ in card(dueDate: due, reps: 5, stability: 100) }

        let youngInputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 2, // 120s
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: youngCards
        )
        let matureInputs = SessionPlannerInputs(
            source: .homeRecommendation,
            durationMinutes: 2,
            profile: .empty,
            unlockedTypes: Set(ExerciseType.allCases),
            availableCards: matureCards
        )

        let youngPlan = await planner.compose(inputs: youngInputs)
        let maturePlan = await planner.compose(inputs: matureInputs)

        let youngCount = youngPlan.exercises.filter(isSrsReview).count
        let matureCount = maturePlan.exercises.filter(isSrsReview).count

        // 120s / 15s (young, unmodulated baseline) = 8 reviews.
        // 120s / 6s (anchored, 0.4× multiplier, rounded) = 20 reviews.
        #expect(youngCount == 8, "expected 8 young reviews to fill 120s at 15s/card: got \(youngCount)")
        #expect(matureCount == 20, "expected all 20 mature reviews to fit 120s at 6s/card: got \(matureCount)")
        #expect(matureCount > youngCount, "a mature-heavy backlog should fit more reviews in the same budget: young=\(youngCount) mature=\(matureCount)")
    }
}
