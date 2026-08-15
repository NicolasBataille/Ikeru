import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - SessionRPGPersistence
//
// Owns every SwiftData read/write `SessionViewModel` makes against the active
// profile's `RPGState` — XP/level load & persist, daily/streak bonus
// finalization, and the shared card-grade side-effect detection
// (leech/new-item). Extracted from `SessionViewModel` (remediation 8.4):
// every method body here is a verbatim move of the corresponding private
// method, just re-homed off the `modelContainer` captured at init instead of
// `self.modelContainer`.
//
// The loot/lootbox drop-generation, pity-timer, and mastery-event detection
// behavior that used to live here was retired (loot pipeline retirement,
// 2026-07-15) — XP + LevelUpView + the badge system are the only remaining
// gamification. `RPGState`'s stored loot fields stay untouched (dormant) to
// avoid a schema migration; see IkeruSchema.
//
// Not `@Observable` — this type holds no published UI state of its own.
// `SessionViewModel` owns all the `@Observable` fields (totalXP, currentLevel, …)
// and applies the results these methods return/persist.
@MainActor
final class SessionRPGPersistence {

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - RPG State Persistence

    /// Fetches the active profile's RPGState, applies the given mutation, and saves.
    /// Use this for all mutations on the current-profile RPGState.
    private func withRPGState(_ body: (RPGState) throws -> Void) async {
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            Logger.rpg.error("No active profile when mutating RPG state")
            return
        }
        do {
            try body(state)
            try context.save()
        } catch {
            Logger.rpg.error("RPG state operation failed: \(error.localizedDescription)")
        }
    }

    /// Loads the active profile's RPG state. Returns nil if the profile
    /// lacks one (caller falls back to xp=0/level=1, mirroring the original
    /// `loadRPGState()`).
    func loadState() async -> (xp: Int, level: Int)? {
        let context = modelContainer.mainContext
        if let state = ActiveProfileResolver.fetchActiveRPGState(in: context) {
            Logger.rpg.debug("Loaded RPG state: xp=\(state.xp), level=\(state.level)")
            return (state.xp, state.level)
        }
        Logger.rpg.warning("No active profile — session starts with zero XP")
        return nil
    }

    /// Persists current RPG state to SwiftData.
    ///
    /// The `totalReviewsCompleted += 1` below is deliberately left as-is
    /// (GAP-13, 2026-08) even though this field is no longer the
    /// authoritative lifetime review count anywhere in the UI — see
    /// `RPGState.totalReviewsCompleted`'s doc comment for the full list of
    /// writers (this one, plus two in `WatchConnectivityManager`). Every
    /// display of a lifetime review count now derives from `ReviewLog` via
    /// `CardRepository.activeProfileReviewCount()`. This increment survives
    /// only because `HomeViewModel.totalReviewsCompleted` still keys its
    /// first-session-ever onboarding heuristic off this field's 0 → >0
    /// transition — an approximation, not an exact one even before this fix
    /// (a Watch result can also move it), but still the least-bad signal
    /// available without reintroducing the Tatami-gate divergence this fix
    /// removes.
    func persistState(xp: Int, level: Int) async {
        await withRPGState { state in
            state.xp = xp
            state.level = level
            state.totalReviewsCompleted += 1
        }
    }

    // MARK: - Newly-Unlocked Processing

    /// After a session ends, records each `ExerciseType` that crossed its
    /// unlock threshold during the session so it isn't re-announced next
    /// time. No-op if there's no active profile or nothing newly unlocked.
    /// Previously also granted a `Loot.NewExerciseUnlocked` badge — dropped
    /// with the loot pipeline retirement (2026-07-15) since no UI ever
    /// displayed it; the acknowledgedUnlocks dedup bookkeeping is the actual
    /// progression signal and is unchanged.
    func processNewlyUnlocked(
        snapshot: LearnerSnapshot,
        unlockService: any ExerciseUnlockService
    ) async {
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        let previous = state.acknowledgedUnlocks
        let delta = unlockService.newlyUnlocked(profile: snapshot, previous: previous)
        guard !delta.isEmpty else { return }
        for type in delta {
            Logger.rpg.info("unlock.granted type=\(type.rawValue, privacy: .public)")
        }
        state.acknowledgedUnlocks = previous.union(delta)
        try? context.save()
    }

    // MARK: - Card-Grade Side Effects

    /// Result of the shared card-grade side-effect detection (first-review
    /// counting, leech detection). See `SessionViewModel.applyCardGradeSideEffects`
    /// for how the caller applies each field back onto its own `@Observable` state.
    struct CardGradeSideEffects {
        let isNewItem: Bool
        let leechEvent: LeechEvent?
        /// Companion intervention content generated when `leechEvent` fires,
        /// nil otherwise. Distractors are sampled from the same-JLPT-level
        /// content bundle when `contentRepository` is available (async
        /// overload); falls back to the hand-written generic pools (sync
        /// overload) when it isn't — e.g. previews/tests that don't inject one.
        let intervention: LeechIntervention?
    }

    /// Card-derived grade side-effects shared by the SRS deck path
    /// (`gradeAndAdvance`) and the `.kanjiStudy` drill path
    /// (`completeCurrentExercise`). Both grade a real FSRS `CardDTO`, so both
    /// must run identical detection/counting:
    ///   1. first-review `newItemsLearned` counting (reps was 0), deduped by
    ///      the caller so a same-day re-queued new card isn't double-counted;
    ///   2. leech detection + companion intervention (real bundle distractors
    ///      when `contentRepository` is available, hand-written fallback pool
    ///      otherwise).
    ///
    /// Must be called by the caller AFTER the XP/RPG update and BEFORE either
    /// index advances — unchanged from the original ordering constraint.
    ///
    /// NOTE: mistake tracking + same-day requeue (`missedCardIDs` /
    /// `requeueFailedCard`) are deliberately NOT here, same as before — that
    /// stays on `SessionViewModel` in the `.srsReview` deck path. Mastery-event
    /// detection + RNG/mastery loot drops used to run here too — retired with
    /// the loot pipeline (2026-07-15).
    func applyCardGradeSideEffects(
        preGradeCard card: CardDTO,
        grade: Grade,
        alreadyCountedNewItem: Bool,
        contentRepository: ContentRepository?
    ) async -> CardGradeSideEffects {
        // Track new items learned (first review = reps was 0). The caller's
        // set guard keeps a same-day re-queued new card from counting twice.
        let isNewItem = card.fsrsState.reps == 0 && !alreadyCountedNewItem

        // Check for leech detection after grading.
        let leechEvent = LeechDetectionService.checkForLeech(
            card: card,
            grade: grade,
            threshold: CardRepository.leechThreshold
        )

        // Generate companion intervention content for a newly-detected leech.
        // Prefers the async overload (real same-JLPT-level bundle distractors)
        // when a `ContentRepository` is available; falls back to the sync
        // overload's hand-written generic pools otherwise (previews/tests that
        // don't inject one).
        var intervention: LeechIntervention?
        if leechEvent != nil {
            let confusionPattern = LeechDetectionService.analyzeConfusion(card: card)
            if let contentRepository {
                intervention = await LeechInterventionService.generateIntervention(
                    card: card,
                    confusionPattern: confusionPattern,
                    contentRepository: contentRepository
                )
            } else {
                intervention = LeechInterventionService.generateIntervention(
                    card: card,
                    confusionPattern: confusionPattern
                )
            }
        }

        return CardGradeSideEffects(
            isNewItem: isNewItem,
            leechEvent: leechEvent,
            intervention: intervention
        )
    }

    // MARK: - Session Finalization

    /// Result of end-of-session finalization (daily/streak bonus). See
    /// `SessionViewModel.finalizeSession` for how the caller applies each
    /// field back onto its own `@Observable` state.
    struct FinalizationResult {
        let updatedTotalXP: Int
        let updatedLevel: Int
        let didLevelUp: Bool
        let bonusXPAwarded: Int
        let bonus: SessionBonusService.Result
    }

    /// Applies end-of-session effects: daily/streak bonus.
    /// Runs once when the session's last card has been graded. Returns nil if
    /// there's no active profile (caller no-ops, mirroring the original
    /// `guard let state = ... else { return }`).
    func finalize(
        currentXP: Int,
        currentLevel: Int
    ) async -> FinalizationResult? {
        let now = Date()
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return nil }

        // Session bonus (daily / streak).
        let bonus = SessionBonusService.evaluate(
            now: now,
            lastSessionDate: state.lastSessionDate,
            currentStreak: state.currentDailyStreak,
            longestStreak: state.longestDailyStreak
        )

        var updatedTotalXP = currentXP
        var updatedLevel = currentLevel
        var didLevelUp = false
        if bonus.bonusXP > 0 {
            updatedTotalXP += bonus.bonusXP
            let newLevel = RPGConstants.levelForXP(updatedTotalXP)
            if newLevel > updatedLevel {
                didLevelUp = true
                updatedLevel = newLevel
            }
            state.xp = updatedTotalXP
            state.level = updatedLevel
            Logger.rpg.info("Session bonus: +\(bonus.bonusXP) XP (streak=\(bonus.newDailyStreak), newDay=\(bonus.isNewDay))")
        }

        state.currentDailyStreak = bonus.newDailyStreak
        state.longestDailyStreak = bonus.newLongestStreak
        state.lastSessionDate = now
        state.totalSessionsCompleted += 1
        // `isNewDay` is true on any calendar-day change vs. the last session,
        // streak-continuity aside — exactly "a distinct active day". Feeds
        // DisplayModeAdvancedThresholdMonitor's `OR active days ≥ 30` path.
        if bonus.isNewDay {
            state.activeDaysCount += 1
        }

        do {
            try context.save()
        } catch {
            Logger.rpg.error("Failed to persist session finalization: \(error.localizedDescription)")
        }

        // Refresh the home-screen widgets' data channel now that this
        // session's due count / level / last-study date are final.
        await WidgetSnapshotRefresher.refresh(modelContainer: modelContainer, force: true)

        return FinalizationResult(
            updatedTotalXP: updatedTotalXP,
            updatedLevel: updatedLevel,
            didLevelUp: didLevelUp,
            bonusXPAwarded: bonus.bonusXP,
            bonus: bonus
        )
    }
}
