import Testing
import SwiftUI
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// MARK: - Kana Session End-to-End (2026-08 pedagogy P2 debt)
//
// After the last remediation lot, `SessionIntegrationTests` migrated its four
// `ContentSeedService.seedBeginnerKanaIfNeeded` fixtures to synthetic
// non-kana cards + a `MockSessionPlanner` (see that file's helper doc
// comments) — a legitimate move for the plumbing those tests actually cover,
// but the net effect was that NOTHING left in CI exercised a real kana
// session end to end anymore. That is exactly the path
// `NewCardPresentationScheduler` (`SessionComposer.swift`) and
// `SessionViewModel.isPresentingNewCard` / `completeNewCardPresentation`
// changed in depth. This suite closes that gap: real seeded kana content
// (`ContentSeedService`, the same production seeder), the real
// `DefaultSessionPlanner` (no `MockSessionPlanner` here — every other test in
// this target that touches `NewCardPresentationScheduler` composes its own
// fixed plan), driven through `SessionViewModel` exactly as
// `ActiveSessionView` would.
@Suite("Kana Session End-to-End (real planner + real content)")
@MainActor
struct KanaSessionEndToEndTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        // Full current (V4) schema — see `SessionDecouplingTests.makeContainer`'s
        // identical doc comment for why V3 would silently bind the wrong
        // entity identity (V3 is now frozen: cloud-sync lot 0, 2026-08-13).
        let schema = Schema(versionedSchema: IkeruSchemaV4.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        ActiveProfileResolver.setActiveProfileID(nil)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @discardableResult
    private func ensureProfile(container: ModelContainer) throws -> UserProfile {
        let context = container.mainContext
        if let existing = ActiveProfileResolver.fetchActiveProfile(in: context) {
            return existing
        }
        let profile = UserProfile(displayName: "Test")
        context.insert(profile)
        try context.save()
        ActiveProfileResolver.setActiveProfileID(profile.id)
        return profile
    }

    /// Marks the active profile's RPGState as "already had a session today"
    /// so the first-session-of-day bonus doesn't perturb assertions.
    private func suppressFirstSessionBonus(container: ModelContainer) throws {
        let context = container.mainContext
        _ = try ensureProfile(container: container)
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        state.lastSessionDate = Date()
        try context.save()
    }

    /// Inserts `count` already-started (`reps > 0`), overdue `.kanji` filler
    /// cards attached to the active profile — NOT kana, so they never
    /// interact with `NewCardPresentationScheduler`'s `isKana` gate.
    ///
    /// `DefaultSessionPlanner.pickReviews` only admits `reps > 0` cards into
    /// the review wave, so these exist purely to lengthen the composed
    /// exercise list's tail: `NewCardPresentationScheduler` declines to defer
    /// a card whose tail can't supply its minimum gap (see that type's
    /// `minimumSRSGap` doc comment), and with ONLY the 5 freshly-seeded kana
    /// in the pool, the interleaved foundation-session exercise list has
    /// nothing after its last kana slot — the scheduler would then correctly
    /// (but unhelpfully, for a test that wants to prove the presentation
    /// pass fires) decline every deferral. 10 filler reviews, interleaved
    /// 50/50 with the 5 kana by `composeFoundation`, guarantees every kana
    /// slot has at least 2 more `.srsReview` occurrences after it — verified
    /// against the exact interleave/scheduler algorithm before writing this
    /// test (10 fillers defers all 5; the count is not a guess).
    private func seedStartedFillerCards(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        let profile = try ensureProfile(container: container)
        for i in 0..<count {
            let card = Card(
                front: "Filler \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(reps: 3),
                dueDate: Date().addingTimeInterval(-3600 + Double(i))
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()
    }

    /// Builds a `SessionViewModel` with the REAL `DefaultSessionPlanner`
    /// (the initializer's default) — deliberately no `MockSessionPlanner`
    /// seam here, unlike every other suite touching this feature. That seam
    /// is exactly what let the last remediation lot's tests keep passing
    /// while the real due-first planner's actual composition (foundation /
    /// construction / cruising stage selection, the 40/30/20/10 mix,
    /// `pickReviews`) went untested against real kana content.
    private func makeVM(container: ModelContainer) -> SessionViewModel {
        // `SessionViewModel.defaultDurationMinutes` reads
        // `@AppStorage("ikeru.session.defaultDurationMinutes")`, i.e.
        // `UserDefaults.standard` — pinned explicitly rather than relying on
        // its 15-minute default. The deferral math in this suite's helper
        // doc comments (10 fillers ⇒ all 5 kana get a big-enough tail) was
        // verified against a 900-second (15 min) review budget; a smaller
        // value here would shrink `pickReviews`'s budget and could make the
        // exact-count assertions below flaky on a machine/simulator where
        // this default was changed (e.g. via the dev-tools settings slider).
        UserDefaults.standard.set(15, forKey: "ikeru.session.defaultDurationMinutes")
        let repo = CardRepository(modelContainer: container)
        let plannerService = PlannerService(cardRepository: repo)
        return SessionViewModel(
            plannerService: plannerService,
            cardRepository: repo,
            modelContainer: container
        )
    }

    // MARK: - Presentation precedes grading; presentation is ungraded; the delayed test is the real first FSRS note

    @Test("A real seeded kana session: every never-reviewed kana gets an ungraded presentation before its delayed graded test, which is its only FSRS write")
    func realKanaSessionPresentsBeforeGrading() async throws {
        let container = try makeContainer()
        try ensureProfile(container: container)
        let seedingRepo = CardRepository(modelContainer: container)

        // Real production seeding path — the exact seeder a day-1 learner's
        // app runs, not a hand-built fixture. Must run BEFORE the filler
        // cards below: `seedBeginnerKanaIfNeeded` only seeds when
        // `existingCardCount == 0`.
        let seededKana = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: seedingRepo,
            existingCardCount: 0
        )
        #expect(seededKana.count == ContentSeedService.beginnerHiragana.count)
        #expect(seededKana.allSatisfy { $0.isKana && $0.fsrsState.reps == 0 })

        try seedStartedFillerCards(container: container, count: 10)
        try suppressFirstSessionBonus(container: container)

        let repo = CardRepository(modelContainer: container)
        let vm = makeVM(container: container)

        // Real due-first `DefaultSessionPlanner`: with 5 never-reviewed kana
        // in the pool, `composeHome` selects the "foundation" (lancement)
        // profile — due reviews (the 10 filler cards) interleaved with one
        // curriculum row of new kana (all 5, since `foundationRowSize == 5`).
        await vm.startSession()
        #expect(vm.isActive)

        var presentedIDs = Set<UUID>()
        var delayedGradeIDs = Set<UUID>()
        var iterations = 0
        let maxIterations = 100 // 20 composed exercises max; generous margin.

        while !vm.isSessionComplete, iterations < maxIterations {
            iterations += 1
            guard case .srsReview(let card) = vm.currentExercise else {
                Issue.record("Expected only .srsReview exercises in a foundation session, got \(String(describing: vm.currentExercise))")
                break
            }
            let isNewKana = card.isKana && card.fsrsState.reps == 0

            if vm.isPresentingNewCard {
                #expect(isNewKana, "only never-reviewed kana cards should ever route through the presentation pass")
                #expect(!presentedIDs.contains(card.id), "a card's presentation pass must fire at most once")
                presentedIDs.insert(card.id)

                let gradedBefore = vm.gradedAttemptCount
                let correctBefore = vm.correctCount
                let newItemsBefore = vm.newItemsLearned

                await vm.completeNewCardPresentation()

                // No FSRS write, no correctness / graded-attempt / new-item
                // bookkeeping — the presentation must not touch the recall rate.
                let logsRightAfterPresentation = await repo.reviewLogs(for: card.id)
                #expect(logsRightAfterPresentation.isEmpty)
                #expect(vm.gradedAttemptCount == gradedBefore)
                #expect(vm.correctCount == correctBefore)
                #expect(vm.newItemsLearned == newItemsBefore)
            } else {
                // The guard-rail: a brand-new kana card can never reach a
                // GRADED slot before its own presentation pass has fired.
                if isNewKana {
                    #expect(
                        presentedIDs.contains(card.id),
                        "kana '\(card.front)' was graded before its presentation pass"
                    )
                }
                await vm.gradeAndAdvance(grade: .good)
                if isNewKana {
                    delayedGradeIDs.insert(card.id)
                    // THIS is the card's real first FSRS grade.
                    let logs = await repo.reviewLogs(for: card.id)
                    #expect(logs.count == 1)
                    #expect(logs.first?.grade == .good)
                }
            }
        }

        #expect(iterations < maxIterations, "session did not terminate within \(maxIterations) grading steps")
        #expect(vm.isSessionComplete == true)

        // With 10 filler reviews the tail is long enough for every one of
        // the 5 seeded kana to be deferred (verified against the scheduler's
        // exact algorithm — see `seedStartedFillerCards`'s doc comment), so
        // this locks the FULL presentation → delayed-grade cycle, not just
        // "at least one card happened to defer".
        #expect(presentedIDs.count == ContentSeedService.beginnerHiragana.count)
        #expect(delayedGradeIDs == presentedIDs)

        // Final state: every seeded kana card ended up with exactly ONE
        // review log — its delayed test, never its presentation.
        for kana in ContentSeedService.beginnerHiragana {
            guard let card = seededKana.first(where: { $0.front == kana.character }) else {
                Issue.record("Missing seeded card for \(kana.character)")
                continue
            }
            let logs = await repo.reviewLogs(for: card.id)
            #expect(logs.count == 1, "\(kana.character) should have exactly one FSRS grade")
        }
    }

    // MARK: - Repeated failure terminates: maxRetriesPerCard applies even with a real kana session

    @Test("A real kana session where the learner fails every card still terminates — same-day requeue respects the retry cap")
    func realKanaSessionFailingRepeatedlyStillTerminates() async throws {
        let container = try makeContainer()
        try ensureProfile(container: container)
        let seedingRepo = CardRepository(modelContainer: container)
        _ = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: seedingRepo,
            existingCardCount: 0
        )
        try seedStartedFillerCards(container: container, count: 10)
        try suppressFirstSessionBonus(container: container)

        let vm = makeVM(container: container)
        await vm.startSession()
        #expect(vm.isActive)

        var iterations = 0
        // The composed plan has ~20 exercises; same-day requeue can add at
        // most 2 retries per unique card id (~15 unique ids), so the queue
        // is bounded well under 100 total graded steps. 500 is a generous
        // safety margin that still fails loudly if the cap regresses.
        let maxIterations = 500

        while !vm.isSessionComplete, iterations < maxIterations {
            iterations += 1
            // Always fail. When the current slot is an ungraded presentation,
            // `gradeAndAdvance` routes to `completeNewCardPresentation`
            // regardless of the grade passed — this also exercises that
            // defensive routing under a caller that always asks for `.again`.
            await vm.gradeAndAdvance(grade: .again)
        }

        // The guard-rail this test locks: repeated failure must not loop
        // forever. If the retry cap ever regressed, this trips instead of
        // the suite hanging.
        #expect(iterations < maxIterations, "session never completed after \(iterations) grades — possible infinite requeue loop")
        #expect(vm.isSessionComplete == true)

        // maxRetriesPerCard (2, `SessionViewModel`) bounds how many times ANY
        // single card can be same-day-requeued after a `.again`. A kana card
        // that went through the presentation pass can appear at most 1
        // (ungraded intro) + 1 (delayed test) + 2 (retries of that test) = 4
        // times in the final exercise list; a filler card (no presentation)
        // caps at 1 + 2 = 3.
        let finalCards = vm.sessionExercises.compactMap { item -> CardDTO? in
            if case .srsReview(let card) = item { return card }
            return nil
        }
        for kana in ContentSeedService.beginnerHiragana {
            let occurrences = finalCards.filter { $0.front == kana.character }.count
            #expect(occurrences >= 1 && occurrences <= 4, "kana '\(kana.character)' appeared \(occurrences) times — retry cap may not be enforced")
        }
        for i in 0..<10 {
            let front = "Filler \(i)"
            let occurrences = finalCards.filter { $0.front == front }.count
            #expect(occurrences >= 1 && occurrences <= 3, "'\(front)' appeared \(occurrences) times — retry cap may not be enforced")
        }
    }

    // MARK: - Jour un, SANS révisions de remplissage (la forme d'un vrai débutant)

    /// Le BLOQUANT n° 1 de la contre-review (OBS2-001), épinglé.
    ///
    /// Tous les autres tests de cette fonctionnalité sèment d'abord des
    /// révisions déjà commencées (`seedStartedFillerCards`) — précisément ce
    /// qu'un apprenant du premier jour n'a PAS. Sans elles, les cartes de queue
    /// n'ont pas assez d'occurrences après elles, et l'ordonnanceur renonçait
    /// alors à la PRÉSENTATION plutôt qu'au test différé : l'apprenant était
    /// interrogé sur un caractère que personne ne lui avait montré, et sa
    /// réponse au hasard devenait sa première note FSRS.
    ///
    /// Ce test a été écrit pendant la review, où il ÉCHOUAIT (3 présentations
    /// sur 5). Il passe depuis que le renoncement porte sur le test différé et
    /// non sur la rencontre.
    @Test("Jour un sans remplissage : chaque kana neuf est présenté avant d'être noté (OBS2-001)")
    func dayOneWithoutFillersPresentsEveryNewKana() async throws {
        let container = try makeContainer()
        try ensureProfile(container: container)
        let seedingRepo = CardRepository(modelContainer: container)

        let seededKana = await ContentSeedService.seedBeginnerKanaIfNeeded(
            repository: seedingRepo,
            existingCardCount: 0
        )
        // Aucun `seedStartedFillerCards` ici — c'est tout l'intérêt.
        try suppressFirstSessionBonus(container: container)

        let vm = makeVM(container: container)
        await vm.startSession()
        #expect(vm.isActive)

        var presentedIDs = Set<UUID>()
        var gradedBeforePresentation: [String] = []
        var iterations = 0

        while !vm.isSessionComplete, iterations < 100 {
            iterations += 1
            guard case .srsReview(let card) = vm.currentExercise else { break }
            if vm.isPresentingNewCard {
                presentedIDs.insert(card.id)
                await vm.completeNewCardPresentation()
            } else {
                // Une carte jamais vue qu'on note sans l'avoir présentée : le
                // défaut exact. On l'enregistre pour que l'échec soit lisible.
                if card.fsrsState.reps == 0, !presentedIDs.contains(card.id) {
                    gradedBeforePresentation.append(card.front)
                }
                await vm.gradeAndAdvance(grade: .good)
            }
        }

        #expect(
            gradedBeforePresentation.isEmpty,
            "notés sans avoir jamais été présentés : \(gradedBeforePresentation)"
        )
        #expect(
            presentedIDs.count == seededKana.count,
            "seulement \(presentedIDs.count) des \(seededKana.count) kana neufs ont reçu une présentation"
        )
    }
}
