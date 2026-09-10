import Foundation
import IkeruCore
import os

// MARK: - SessionViewModel+GradingFlow
//
// The grading/completion pipeline shared by the SRS deck path
// (`gradeAndAdvance`) and the non-SRS drill path (`completeCurrentExercise`),
// plus the new-card presentation acknowledgement, end-of-session finalization,
// and the same-day re-queue. Extracted from `SessionViewModel` (P2 debt lot,
// 2026-08) to bring the class body back under the repo's file-length guard —
// every method body below is a VERBATIM move (doc comments included), not a
// rewrite. This continues the pattern already present in the original file
// (the trailing "Card-Grade Side Effects" extension, kept "to keep the class
// body under type_body_length"); the only thing that changed is that the
// extension now lives in its own file since the class itself needed to shrink,
// not just its lint-measured body.
//
// Two call-site adaptations were needed to compile from a different file:
//   1. `persistRPGState()` (a 3-line private wrapper with no other caller) is
//      inlined here as a direct `rpgPersistence.persistState(...)` call — same
//      effect, one fewer method to widen access on.
//   2. `liveActivityManager.updateActivity(...)` (with its inline exercise-label
//      `?? "Review"` fallback) now reads `liveActivity.reportProgress(...)`,
//      the extracted `SessionLiveActivityCoordinator` — same fallback, same
//      parameters, computed inside the coordinator instead of inline.
// Every other line is unchanged.
//
// Mechanical consequence of the split: every stored property and dependency
// these methods read OR WRITE, that stays declared on the class body in
// `SessionViewModel.swift`, had its access widened from `private`/
// `public private(set)` to (no modifier, i.e. internal) / `public internal(set)`
// so this file can reach it — `private` is scoped to the declaring file, not
// just the declaring type. Nothing here becomes `public` API; @testable
// already exposed internal members to the test target regardless of which
// file declared them, so this is a compile-time-only, zero-runtime-behavior
// change. See `SessionViewModel.swift`'s property declarations for the
// widened set (feedbackState, missedCardIDs, reviewedCount, currentIndex,
// cardStartTime, gradeSaveFailureCount, gradedAttemptCount, consecutiveCorrect,
// correctCount, totalXP, currentLevel, xpEarned, lastXPGained, levelUpLevel,
// skillContribution, ledger, sessionJLPTLevel, rpgPersistence, sessionExercises,
// sessionQueue, currentExerciseIndex, endPolicy, nonSRSGradedCardIDs,
// cardRepository, cardsNeedingPresentation, lastSessionBonus, retryCounts,
// newItemCountedIDs, contentRepository, newItemsLearned, lastLeechEvent,
// lastLeechIntervention, liveActivity, stopTimer()).
//
// Everything DECLARED in this file (the helper methods below, plus
// `maxRetriesPerCard`/`reviewSurface`) stays `private` — every one of their
// call sites lives in this same file, so no further widening was needed for
// them.
extension SessionViewModel {

    /// Where every `ReviewLog` written by this view model came from. The main
    /// SRS session runs only on iPhone today — no Watch call site persists a
    /// `ReviewLog` yet — so this is the one constant value for the whole file.
    /// See `ReviewLog.surface`.
    private static let reviewSurface = "iphone.session"

    /// Grades the current card and advances to the next one.
    /// - Parameter grade: The grade to apply.
    public func gradeAndAdvance(grade: Grade) async {
        guard let card = currentCard else { return }

        // Defensive: the production UI never reaches this path while
        // presenting a new-card intro — `ExerciseTransitionContainer`
        // branches to `NewCardPresentationView` (no grade buttons, no swipe
        // gesture) whenever `isPresentingNewCard` is true. This guard exists
        // so any OTHER caller (a future UI path, a test driving the view
        // model directly) can't accidentally write a real FSRS grade for an
        // ungraded intro — it silently routes to the correct "acknowledge,
        // don't grade" behavior instead.
        if isPresentingNewCard {
            await completeNewCardPresentation()
            return
        }

        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // Recall succeeded whenever the grade wasn't `.again` — `.hard` means
        // slow-but-correct, so it counts as a pass for the recall % (see
        // `correctCount`), consistent with `missedCardIDs` below only
        // treating `.again` as a miss.
        let isRecallSuccess = grade != .again

        // Show feedback. `.hard` gets its own `.partial` treatment: it's not
        // the full "correct" green (the recall was slow), but it's not the
        // "incorrect" red of an actual miss either.
        let newFeedbackState: FeedbackState = switch grade {
        case .again: .incorrect
        case .hard: .partial
        case .good, .easy: .correct
        }
        feedbackState = newFeedbackState

        // Track only .again grades as mistakes. A .hard grade means the recall
        // was slow but ultimately correct — counting it as a miss conflated
        // slow recall with failure and drilled cards the user actually knew.
        if grade == .again {
            missedCardIDs.insert(card.id)
            requeueFailedCard(card)
        }

        // Hoisted above the grade write (pure function of `card`, no side
        // effects) so the SAME resolved type feeds both the persisted
        // ReviewLog.exerciseType (provenance, learner-telemetry lot 1) and
        // the XP award below — one source of truth, not two computations
        // that could drift apart.
        let exerciseType = SessionExerciseSupport.exerciseTypeForCurrentReview(card: card)

        await gradeCardAndCheckSaveErrors(
            card: card,
            grade: grade,
            responseTimeMs: responseTimeMs,
            exerciseType: exerciseType
        )

        // Award XP via ExerciseXP (per-type × JLPT-level multiplier),
        // delegating to RPGService for level-up bookkeeping. Flashcard
        // types still match `xpForGrade` totals (delegation in the rule
        // table), so kana-only N5 sessions award the same XP as before.
        await awardExerciseXP(type: exerciseType, grade: grade, sampledTelemetry: true)

        // Track consecutive correct (display / Live Activity streak only).
        trackCorrectness(isCorrect: isRecallSuccess)

        // Card-derived grade side-effects (first-review `newItemsLearned`
        // counting, leech detection). Extracted so the `.kanjiStudy` drill
        // path in `completeCurrentExercise` runs the SAME bookkeeping — a
        // kanji card that becomes a leech or is newly learned is detected
        // regardless of which UI graded it. Called here at the exact
        // position (after the XP/RPG update, before either index advances)
        // so SRS behavior is byte-for-byte unchanged.
        await applyCardGradeSideEffects(preGradeCard: card, grade: grade)

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        // Update Live Activity with current progress
        await reportLiveActivityProgress()

        // Advance exercise index to stay in sync
        advanceToNextExercise()

        // Clear feedback after brief display
        try? await Task.sleep(for: .milliseconds(300))
        feedbackState = nil

        await finishSessionIfNeeded()
    }

    /// Persists a card's FSRS grade and surfaces persistence failures. Shared
    /// by the SRS deck path (`gradeAndAdvance`, always grades `currentCard`)
    /// and the non-SRS drill path (`completeCurrentExercise`, conditionally
    /// grades its `gradeableCard`) — both write the identical FSRS grade +
    /// save-error-monitor check. A grade whose save failed may not count
    /// toward scheduling; this checks once right after the write and clears
    /// the monitor so the same failure isn't re-surfaced on the next card.
    ///
    /// `answeredValue` is never passed here — every grade reaching this layer
    /// came from a self-graded Again/Hard/Good/Easy button, not a choice-format
    /// exercise, so there is no "chosen value" to log (stays `nil` on the
    /// persisted `ReviewLog`). Choice-format session exercises exist elsewhere
    /// (e.g. vocabulary recall options) but their chosen answers aren't
    /// plumbed to this layer yet — out of this lot's scope, not an oversight.
    private func gradeCardAndCheckSaveErrors(
        card: CardDTO,
        grade: Grade,
        responseTimeMs: Int,
        exerciseType: ExerciseType
    ) async {
        Logger.srs.debug(
            "Grading card \(card.front): grade=\(grade.rawValue), responseTime=\(responseTimeMs)ms"
        )
        await cardRepository.gradeCard(
            cardId: card.id,
            grade: grade,
            responseTimeMs: responseTimeMs,
            exerciseType: exerciseType.rawValue,
            surface: Self.reviewSurface
        )
        if cardRepository.saveErrorMonitor.lastSaveError != nil {
            cardRepository.saveErrorMonitor.clear()
            gradeSaveFailureCount += 1
        }
    }

    /// Updates the display-only correctness streak. Shared by `gradeAndAdvance`
    /// and `completeCurrentExercise` — both apply the identical increment/reset.
    private func trackCorrectness(isCorrect: Bool) {
        gradedAttemptCount += 1
        if isCorrect {
            consecutiveCorrect += 1
            correctCount += 1
        } else {
            consecutiveCorrect = 0
        }
    }

    /// Reports current progress to the Live Activity / Dynamic Island.
    /// Shared by `gradeAndAdvance` and `completeCurrentExercise` — both read
    /// `currentExercise` for the label at the exact same point (after
    /// `reviewedCount`/index bookkeeping, before the exercise pointer
    /// advances), so both see the just-completed exercise, matching the
    /// original per-call-site computation exactly.
    private func reportLiveActivityProgress() async {
        await liveActivity.reportProgress(
            elapsedSeconds: Int(elapsedTime),
            currentExercise: currentExercise,
            completedCount: reviewedCount,
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )
    }

    /// XP-award bookkeeping shared by the SRS deck path (`gradeAndAdvance`)
    /// and the non-SRS drill path (`completeCurrentExercise`): computes the
    /// per-type × JLPT-level XP via `ExerciseXP.award`, delegates to
    /// `RPGService` for level-up bookkeeping, records per-skill attribution
    /// into the session ledger, persists RPG state, and sets `levelUpLevel`
    /// on level-up. `sampledTelemetry` gates the 10%-sampled `xp.attributed`
    /// log line, which only `gradeAndAdvance` originally emitted (the SRS
    /// deck path is the high-volume event the sampling comment refers to).
    @discardableResult
    private func awardExerciseXP(type: ExerciseType, grade: Grade, sampledTelemetry: Bool) async -> Int {
        let xpAmount = ExerciseXP.award(type: type, level: sessionJLPTLevel, grade: grade)
        let result = RPGService.awardXP(
            amount: xpAmount,
            currentXP: totalXP,
            currentLevel: currentLevel,
            totalReviews: reviewedCount
        )

        totalXP = result.newXP
        currentLevel = result.newLevel
        xpEarned += result.xpAwarded
        lastXPGained = result.xpAwarded

        // Record per-skill attribution into the session ledger; surfaces
        // on SessionSummaryView's four-winds row.
        Task { [ledger] in
            await ledger.record(xp: xpAmount, exerciseType: type)
            let snap = await ledger.snapshot()
            await MainActor.run { self.skillContribution = snap }
        }

        // 10% sampled telemetry — high-volume event, full coverage would
        // bloat the log. Sampling rate documented in the design doc.
        if sampledTelemetry, Int.random(in: 0..<100) < 10 {
            Logger.ui.info(
                "xp.attributed type=\(type.rawValue, privacy: .public) level=\(self.sessionJLPTLevel.rawValue, privacy: .public) finalXP=\(xpAmount, privacy: .public)"
            )
        }

        // Persist RPG state. Inlined from the original `persistRPGState()`
        // wrapper (that method had no other caller — see this file's header).
        await rpgPersistence.persistState(xp: totalXP, level: currentLevel)

        // Check for level-up
        if result.didLevelUp {
            levelUpLevel = result.newLevel
        }

        return xpAmount
    }

    /// Ends and finalizes the session when it should stop — exercise-list
    /// exhaustion OR the time-budget policy firing. Shared by `gradeAndAdvance`
    /// (SRS deck path) and `completeCurrentExercise` (non-SRS drill path) so both
    /// routes finalize identically. No-op until `shouldEndSession` is true.
    private func finishSessionIfNeeded() async {
        guard shouldEndSession else { return }
        stopTimer()
        await finalizeSession()
        await liveActivity.end(
            elapsedSeconds: Int(elapsedTime),
            completedCount: reviewedCount,
            // Total is the exercise-list length, matching `updateActivity`
            // (which already reports `sessionExercises.count`). With mixed
            // SRS + drill sessions now reachable, `sessionQueue.count` (SRS-only)
            // would under-report the denominator on the ending Live Activity.
            totalCount: sessionExercises.count,
            xpEarned: xpEarned,
            streakCount: consecutiveCorrect
        )
        // Force BOTH pointers past their ends so views that observe
        // `isSessionComplete` (computed: currentExerciseIndex >=
        // sessionExercises.count) route to the summary even when the time
        // budget — not exercise-list exhaustion — fired the end. The two guards
        // are independent because the SRS queue and the exercise list can now
        // differ in length; draining only one would leave the session neither
        // complete nor advancing.
        let queueDrained = reviewedCount >= sessionQueue.count
        if currentIndex < sessionQueue.count {
            currentIndex = sessionQueue.count
        }
        if currentExerciseIndex < sessionExercises.count {
            currentExerciseIndex = sessionExercises.count
        }
        let budgetMinutes = self.endPolicy?.durationBudgetMinutes ?? 0
        let queueLength = self.sessionQueue.count
        if queueDrained {
            Logger.ui.info(
                "session.ended.queue durationMinutes=\(budgetMinutes, privacy: .public) elapsedSeconds=\(Int(self.elapsedTime), privacy: .public) completedCount=\(self.reviewedCount, privacy: .public) queueLength=\(queueLength, privacy: .public) xpEarned=\(self.xpEarned, privacy: .public)"
            )
        } else {
            Logger.ui.info(
                "session.ended.budget durationMinutes=\(budgetMinutes, privacy: .public) elapsedSeconds=\(Int(self.elapsedTime), privacy: .public) completedCount=\(self.reviewedCount, privacy: .public) queueLength=\(queueLength, privacy: .public) xpEarned=\(self.xpEarned, privacy: .public)"
            )
        }
    }

    /// Single completion entry point for a NON-SRS exercise (kanji study,
    /// writing, sentence construction, listening, …) surfaced by the immersive
    /// drill container. SRS flashcards keep grading through `gradeAndAdvance`;
    /// this method exists so a non-card exercise can be completed without
    /// corrupting the SRS card-queue pointer.
    ///
    /// Index discipline (the core of the 4.1 decoupling):
    /// - `currentExerciseIndex` ALWAYS advances — every exercise is consumed.
    /// - `currentIndex` (the `sessionQueue` pointer) advances ONLY for
    ///   `.srsReview`. `sessionQueue` is built from `.srsReview` payloads alone,
    ///   so a `.kanjiStudy` card is never in it; advancing the queue pointer for
    ///   it would over-run the queue and mis-grade the next real review.
    ///   Invariant held: `currentIndex` == number of completed `.srsReview`
    ///   items == index into `sessionQueue`.
    /// - `.kanjiStudy` and `.writingPractice` each write a real FSRS grade
    ///   against their backing `CardDTO` (the 4.4 hook) but do NOT touch
    ///   `currentIndex`; every other non-SRS kind is XP-only.
    ///
    /// Reachable in production: `DefaultSessionPlanner` schedules the wired
    /// non-SRS drills (`.kanjiStudy`, `.writingPractice`, `.sentenceConstruction`,
    /// listening / shadowing / vocabulary) via its `isLive` allowlist. It is also
    /// exercised by the decoupling regression tests.
    public func completeCurrentExercise(grade: Grade) async {
        guard let exercise = currentExercise else { return }

        // SRS reviews grade through the deck path so their full card-centric
        // behavior (mistake tracking, same-day requeue, leech detection,
        // new-item counting) is preserved exactly.
        if case .srsReview = exercise {
            await gradeAndAdvance(grade: grade)
            return
        }

        let responseTimeMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)

        // `.kanjiStudy` and `.writingPractice` both carry a real, gradeable
        // card, so write their FSRS grade WITHOUT advancing `currentIndex`
        // (their cards are not in `sessionQueue`). Every other non-SRS kind is
        // XP-only (no backing card). XP is still awarded below for all kinds.
        //
        // `nonSRSGradedCardIDs` de-dupes: if this same card was already graded
        // through this path earlier in the session (kanjiStudy + writingPractice
        // can both target it), skip the second FSRS write + side-effects so one
        // character isn't counted as two independent reviews. XP still accrues.
        let gradeableCard: CardDTO?
        switch exercise {
        case .kanjiStudy(let card), .writingPractice(let card):
            gradeableCard = nonSRSGradedCardIDs.contains(card.id) ? nil : card
        default:
            gradeableCard = nil
        }
        // Hoisted above the grade write — see `gradeAndAdvance`'s identical
        // reasoning for why the resolved type feeds both the persisted
        // ReviewLog.exerciseType and the XP award below from one computation.
        let resolvedType = SessionExerciseSupport.exerciseType(for: exercise)
        if let card = gradeableCard {
            nonSRSGradedCardIDs.insert(card.id)
            await gradeCardAndCheckSaveErrors(
                card: card,
                grade: grade,
                responseTimeMs: responseTimeMs,
                exerciseType: resolvedType
            )
        }

        // Award XP for the exercise kind (per-type × JLPT-level multiplier).
        // `grade` is forwarded for `.perGrade` kinds (e.g. kanjiStudy) and
        // ignored by the rule table for `.perCompletion` kinds.
        await awardExerciseXP(type: resolvedType, grade: grade, sampledTelemetry: false)

        // Track consecutive / total correct (display only). `.hard` counts as
        // a pass here too — see `correctCount`'s doc comment / `gradeAndAdvance`
        // for why: it's slow-but-correct recall, not a miss.
        trackCorrectness(isCorrect: grade != .again)

        // The card-backed kinds (`.kanjiStudy`, `.writingPractice`) run the
        // shared card-grade side-effects: leech detection and first-review
        // counting, identical to the SRS deck path. Positioned after
        // the XP/RPG update (parity with `gradeAndAdvance`) and before the
        // exercise pointer advances. Every other non-SRS kind is XP-only.
        if let card = gradeableCard {
            await applyCardGradeSideEffects(preGradeCard: card, grade: grade)
        }

        // Persist pool-based output outcomes (listening / shadowing) — these have
        // no backing FSRS card, so their accuracy is recorded here instead. It
        // feeds `LearnerSnapshot.listeningAccuracyLast30` / `listeningRecallLast30Days`
        // (which unlock `.listeningUnsubtitled` / `.speakingPractice`) and the
        // speaking axis of `SkillBalanceSnapshot` (remediation 4.4). A skip via
        // DrillUnavailableView arrives as `.again` → 0.0, which conservatively
        // (never falsely) keeps the gates locked.
        switch exercise {
        case .listeningExercise, .speakingExercise:
            let accuracy = ExerciseOutcomeAccuracy.from(grade: grade, skill: exercise.skill)
            await cardRepository.recordExerciseOutcome(skill: exercise.skill, accuracy: accuracy)
        default:
            break
        }

        // `reviewedCount` counts completed exercises (not just SRS cards): it
        // gates the time-budget policy's `completedCount`, the endSession
        // zero-skip, the Live Activity, and the abandon label — so a non-SRS
        // completion must bump it too.
        reviewedCount += 1
        cardStartTime = Date()

        // Update Live Activity with current progress (label = the just-completed
        // exercise, mirroring gradeAndAdvance's ordering).
        await reportLiveActivityProgress()

        // Advance the exercise pointer (never the SRS queue pointer here).
        advanceToNextExercise()

        await finishSessionIfNeeded()
    }

    /// Acknowledges the ungraded new-card presentation pass (see
    /// `isPresentingNewCard`/`cardsNeedingPresentation`) and advances past
    /// it. Deliberately does NOT write any FSRS grade and does NOT touch
    /// `correctCount` / `missedCardIDs` / `newItemsLearned` /
    /// `gradedAttemptCount` — those are earned by this SAME card's delayed
    /// `.srsReview` occurrence a few exercises later, which still routes
    /// through the untouched `gradeAndAdvance` and is the card's real first
    /// FSRS grade (`effects.isNewItem` fires there, not here).
    ///
    /// `currentIndex` still advances: this occurrence IS one of
    /// `sessionQueue`'s `.srsReview` slots (see `NewCardPresentationScheduler`
    /// in `SessionComposer.swift`), so the queue/exercise pointers stay in
    /// lockstep exactly as they do for a graded card — see
    /// `isSessionComplete`'s doc comment on that invariant.
    ///
    /// `reviewedCount` DOES advance: it took real session time and gates
    /// the time-budget policy's `completedCount`
    /// (`SessionEndPolicy.queueLength` was sized to include this occurrence
    /// — see `SessionComposer`), the Live Activity, and the abandon-dialog
    /// label. It is intentionally NOT the denominator `SessionSummaryView`
    /// uses for recall % — see `gradedAttemptCount`.
    public func completeNewCardPresentation() async {
        guard case .srsReview(let card) = currentExercise else { return }
        cardsNeedingPresentation.remove(card.id)

        reviewedCount += 1
        currentIndex += 1
        cardStartTime = Date()

        await reportLiveActivityProgress()
        advanceToNextExercise()

        await finishSessionIfNeeded()
    }
}

// MARK: - Session Finalization (moved alongside the grading flow above)
extension SessionViewModel {

    /// Applies end-of-session effects: daily/streak bonus.
    /// Runs once when the session's last card has been graded. Persistence +
    /// bonus computation live in `SessionRPGPersistence.finalize`
    /// (remediation 8.4 extraction); this wrapper applies the result onto
    /// `@Observable` state with the exact same conditionals as the original
    /// inline implementation (e.g. `totalXP`/`currentLevel`/`levelUpLevel`
    /// only change when `bonusXPAwarded > 0`, matching the original's
    /// `if bonus.bonusXP > 0` gate).
    private func finalizeSession() async {
        guard let result = await rpgPersistence.finalize(
            currentXP: totalXP,
            currentLevel: currentLevel
        ) else { return }

        if result.bonusXPAwarded > 0 {
            totalXP = result.updatedTotalXP
            xpEarned += result.bonusXPAwarded
            if result.didLevelUp {
                levelUpLevel = result.updatedLevel
                currentLevel = result.updatedLevel
            }
        }

        lastSessionBonus = result.bonus
    }
}

// MARK: - Same-Day Re-Queue
extension SessionViewModel {

    /// How many times a single card has been re-queued during the current
    /// session, mirrored here from `SessionViewModel`'s doc comment on
    /// `retryCounts`. Capped so a stuck card can't loop forever. Used only
    /// within this file (by `requeueFailedCard`), so it stays `private` here
    /// rather than on the class body.
    private static let maxRetriesPerCard = 2

    /// Same-day intra-session re-queue: a card graded `.again` comes back later
    /// in the same session instead of disappearing until its next FSRS due date.
    /// Mistakes mode appends to the end (drill-until-done); normal sessions
    /// re-insert 3-5 positions later. Capped at `maxRetriesPerCard`.
    private func requeueFailedCard(_ card: CardDTO) {
        let retries = retryCounts[card.id, default: 0]
        guard let result = SessionRequeuePlanner.requeue(
            card: card,
            currentRetryCount: retries,
            maxRetries: Self.maxRetriesPerCard,
            sessionMode: sessionMode,
            currentExerciseIndex: currentExerciseIndex,
            sessionQueue: sessionQueue,
            sessionExercises: sessionExercises,
            endPolicy: endPolicy
        ) else { return }

        retryCounts[card.id] = result.retryCount
        sessionQueue = result.sessionQueue
        sessionExercises = result.sessionExercises
        endPolicy = result.endPolicy

        Logger.srs.info(
            "Same-day requeue: \(card.front, privacy: .public) (retry \(result.retryCount)/\(Self.maxRetriesPerCard, privacy: .public))"
        )
    }
}

// MARK: - Card-Grade Side Effects (extracted to keep the class body under type_body_length)
extension SessionViewModel {
    /// Card-derived grade side-effects shared by the SRS deck path
    /// (`gradeAndAdvance`) and the `.kanjiStudy` drill path
    /// (`completeCurrentExercise`). Detection/persistence logic lives in
    /// `SessionRPGPersistence.applyCardGradeSideEffects` (remediation 8.4
    /// extraction); this wrapper applies the result onto `@Observable` state.
    ///
    /// Must be called AFTER the XP/RPG update and BEFORE either index advances.
    ///
    /// NOTE: mistake tracking + same-day requeue (`missedCardIDs` /
    /// `requeueFailedCard`) are deliberately NOT here — that stays in the
    /// `.srsReview` deck path (`gradeAndAdvance`).
    private func applyCardGradeSideEffects(preGradeCard card: CardDTO, grade: Grade) async {
        let effects = await rpgPersistence.applyCardGradeSideEffects(
            preGradeCard: card,
            grade: grade,
            alreadyCountedNewItem: newItemCountedIDs.contains(card.id),
            contentRepository: contentRepository
        )
        if effects.isNewItem {
            newItemCountedIDs.insert(card.id)
            newItemsLearned += 1
        }
        if let leechEvent = effects.leechEvent {
            lastLeechEvent = leechEvent
            lastLeechIntervention = effects.intervention
        }
    }
}
