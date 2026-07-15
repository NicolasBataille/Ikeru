import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - SessionRPGPersistence
//
// Owns every SwiftData read/write `SessionViewModel` makes against the active
// profile's `RPGState` — XP/level load & persist, loot/lootbox persistence,
// pity-drop + daily/streak bonus finalization, and the shared card-grade
// side-effect detection (mastery/loot/leech/new-item). Extracted from
// `SessionViewModel` (remediation 8.4): every method body here is a verbatim
// move of the corresponding private method, just re-homed off the
// `modelContainer` captured at init instead of `self.modelContainer`.
//
// Not `@Observable` — this type holds no published UI state of its own.
// `SessionViewModel` owns all the `@Observable` fields (totalXP, currentLevel,
// lastLootDrop, …) and applies the results these methods return/persist.
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
    func persistState(xp: Int, level: Int) async {
        await withRPGState { state in
            state.xp = xp
            state.level = level
            state.totalReviewsCompleted += 1
        }
    }

    /// Persists a loot drop to the RPG state inventory.
    func persistLootDrop(_ item: LootItem) async {
        await withRPGState { state in
            state.addLootItem(item)
            Logger.rpg.info("Loot drop persisted: \(item.name) (\(item.rarity.displayName))")
        }
    }

    /// Returns true if the active profile's RPG inventory already contains a
    /// loot item with the given name. Used to dedup once-per-profile named
    /// mastery rewards like "First Steps" so they aren't re-awarded on every
    /// new card graded Good/Easy.
    func inventoryContains(name: String) async -> Bool {
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            return false
        }
        return state.lootInventory.contains { $0.name == name }
    }

    /// Persists a lootbox to the RPG state.
    func persistLootBox(_ box: LootBox) async {
        await withRPGState { state in
            state.addLootBox(box)
            Logger.rpg.info("Lootbox persisted: \(box.challengeType.displayName)")
        }
    }

    // MARK: - Newly-Unlocked Processing

    /// After a session ends, grants a one-time `Loot.NewExerciseUnlocked`
    /// badge for each `ExerciseType` that crossed its unlock threshold during
    /// the session. No-op if there's no active profile or nothing newly
    /// unlocked.
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
            let drop = LootItem(
                category: .badge,
                rarity: .rare,
                name: String(localized: "Loot.NewExerciseUnlocked"),
                iconName: "leaf.fill"
            )
            state.addLootItem(drop)
            Logger.rpg.info("unlock.granted type=\(type.rawValue, privacy: .public)")
        }
        state.acknowledgedUnlocks = previous.union(delta)
        try? context.save()
    }

    // MARK: - Card-Grade Side Effects

    /// Result of the shared card-grade side-effect detection (mastery events,
    /// RNG/mastery loot drops, first-review counting, leech detection). See
    /// `SessionViewModel.applyCardGradeSideEffects` for how the caller applies
    /// each field back onto its own `@Observable` state.
    struct CardGradeSideEffects {
        let lootDrop: LootItem?
        let sessionLootCountDelta: Int
        let masteryEvent: MasteryEvent?
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
    ///   1. mastery events (Phase 3) → forced loot drop at event rarity, taking
    ///      priority over the RNG drop; else the RNG loot drop;
    ///   2. first-review `newItemsLearned` counting (reps was 0), deduped by
    ///      the caller so a same-day re-queued new card isn't double-counted;
    ///   3. leech detection + companion intervention (real bundle distractors
    ///      when `contentRepository` is available, hand-written fallback pool
    ///      otherwise).
    ///
    /// Must be called by the caller AFTER the XP/RPG update (the RNG drop reads
    /// the post-award `currentLevel`) and BEFORE either index advances —
    /// unchanged from the original ordering constraint.
    ///
    /// NOTE: mistake tracking + same-day requeue (`missedCardIDs` /
    /// `requeueFailedCard`) are deliberately NOT here, same as before — that
    /// stays on `SessionViewModel` in the `.srsReview` deck path.
    func applyCardGradeSideEffects(
        preGradeCard card: CardDTO,
        grade: Grade,
        sessionJLPTLevel: JLPTLevel,
        currentLevel: Int,
        sessionLootCount: Int,
        alreadyCountedNewItem: Bool,
        contentRepository: ContentRepository?
    ) async -> CardGradeSideEffects {
        // Mastery events: pre-grade card state → forced drops at event rarity.
        // Detected BEFORE RNG drop so they always take priority when both would
        // fire. Named mastery drops (e.g. "First Steps") are once-per-profile —
        // if the inventory already contains the drop, skip it. Otherwise the
        // same badge would re-appear every time a new card is graded Good/Easy.
        var lootDrop: LootItem?
        var lootCountDelta = 0
        var masteryEvent: MasteryEvent?

        let masteryEvents = MasteryEventDetector.detect(preGradeCard: card, grade: grade)
        if let event = masteryEvents.first {
            let drop = LootDropService.generateMasteryDrop(for: event, learnerLevel: sessionJLPTLevel)
            let alreadyOwned = await inventoryContains(name: drop.name)
            if !alreadyOwned {
                lootDrop = drop
                lootCountDelta = 1
                masteryEvent = event
                await persistLootDrop(drop)
                Logger.rpg.info("Mastery drop: \(event.displayName) → \(drop.name) (\(drop.rarity.displayName))")
            } else {
                Logger.rpg.info("Mastery drop skipped (\(drop.name) already in inventory)")
            }
        } else if LootDropService.shouldDropLoot(
            grade: grade,
            sessionLootCount: sessionLootCount
        ) {
            let drop = LootDropService.generateDrop(level: currentLevel)
            lootDrop = drop
            lootCountDelta = 1
            await persistLootDrop(drop)
        }

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
            lootDrop: lootDrop,
            sessionLootCountDelta: lootCountDelta,
            masteryEvent: masteryEvent,
            isNewItem: isNewItem,
            leechEvent: leechEvent,
            intervention: intervention
        )
    }

    // MARK: - Session Finalization

    /// Result of end-of-session finalization (pity-drop check + daily/streak
    /// bonus). See `SessionViewModel.finalizeSession` for how the caller
    /// applies each field back onto its own `@Observable` state.
    struct FinalizationResult {
        let updatedTotalXP: Int
        let updatedLevel: Int
        let didLevelUp: Bool
        let bonusXPAwarded: Int
        let lootDrop: LootItem?
        let updatedSessionLootCount: Int
        let bonus: SessionBonusService.Result
    }

    /// Applies end-of-session effects: daily/streak bonus and pity-drop check.
    /// Runs once when the session's last card has been graded. Returns nil if
    /// there's no active profile (caller no-ops, mirroring the original
    /// `guard let state = ... else { return }`).
    func finalize(
        currentXP: Int,
        currentLevel: Int,
        sessionLootCount: Int
    ) async -> FinalizationResult? {
        let now = Date()
        let context = modelContainer.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return nil }

        // Pity timer — if no drop this session, bump counter and force a drop at threshold.
        var lootDrop: LootItem?
        var updatedSessionLootCount = sessionLootCount
        if sessionLootCount == 0 {
            state.sessionsSinceLastDrop += 1
            if LootDropService.shouldForcePityDrop(sessionsSinceLastDrop: state.sessionsSinceLastDrop) {
                let drop = LootDropService.generateDrop(level: currentLevel)
                state.addLootItem(drop)
                lootDrop = drop
                updatedSessionLootCount += 1
                state.sessionsSinceLastDrop = 0
                Logger.rpg.info("Pity drop awarded: \(drop.name) (\(drop.rarity.displayName))")
            }
        } else {
            state.sessionsSinceLastDrop = 0
        }

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
            lootDrop: lootDrop,
            updatedSessionLootCount: updatedSessionLootCount,
            bonus: bonus
        )
    }
}
