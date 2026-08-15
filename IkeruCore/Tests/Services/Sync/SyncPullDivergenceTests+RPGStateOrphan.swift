import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// GAP-04 (see `docs/known-gaps.md`): locks down the id-adoption branch in
/// `SyncPullActor.applyRPGStateRows` for the case that entry describes —
/// TWO server-side `rpg_states` rows for the SAME `profile_id`, delivered to
/// a device whose local `RPGState` id matches neither. This happens for
/// real when a device is reinstalled: `UserProfile.init` always mints a
/// fresh `RPGState` (a new id), and `SyncModelActor.pushAllRPGStates` pushes
/// it unconditionally — so a reinstall followed by a successful push can
/// leave the server holding the pre-reinstall row AND the post-reinstall
/// row for the same profile, both surviving forever since nothing ever
/// deletes an `RPGState` row.
///
/// Decision recorded here (see this file's test, and `known-gaps.md`'s
/// GAP-04 entry): ACCEPT the orphaned server-side row rather than build a
/// cleanup — `rpg_states` counters merge by `max()` (rule 3), so the
/// orphaned row never costs a learner XP/level/streak data; it only costs
/// one unreachable row per affected profile, which is cosmetic clutter on a
/// project with no admin UI that would ever show it. A server-side cleanup
/// job is more moving parts than the problem justifies. What was actually
/// missing — and is what this file adds — is proof the multi-row delivery
/// genuinely converges to ONE local `RPGState` (not two), with every
/// counter preserved, and that a repeat cycle doesn't loop or drift.
extension SyncPullDivergenceTests {

    @Test("GAP-04: two server rpg_states rows for one profile stabilize to exactly one local RPGState, merging every counter by max — no counter lost to the orphan")
    func twoRPGStateRowsForSameProfileStabilizeWithoutLosingCounters() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // The device's own pre-existing profile + its auto-minted RPGState
        // — the local state a reinstalled device would already have before
        // this pull.
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Learner")
        profile.rpgState?.xp = 300
        profile.rpgState?.level = 2
        profile.rpgState?.totalReviewsCompleted = 10
        context.insert(profile)
        try context.save()
        let profileID = profile.id

        // Two DISTINCT server rows for the SAME profile_id — the orphan
        // scenario: an earlier device generation's row (`oldState`) plus
        // whatever a later push produced (`newState`), both surviving
        // server-side. Neither id matches the local profile's own
        // auto-minted `RPGState`.
        let t1 = Date(timeIntervalSince1970: 1_701_500_000)
        let t2 = t1.addingTimeInterval(60)

        let oldState = RPGState(xp: 1000, level: 5, totalReviewsCompleted: 50)
        oldState.totalSessionsCompleted = 20
        oldState.currentDailyStreak = 3
        oldState.longestDailyStreak = 8
        oldState.activeDaysCount = 12
        oldState.updatedAt = t1
        var oldRow = try SyncPayloadBuilder.row(for: oldState)
        oldRow["profile_id"] = .uuid(profileID)
        oldRow["server_updated_at"] = .string(SyncJSON.iso8601String(t1))

        let newState = RPGState(xp: 400, level: 3, totalReviewsCompleted: 15)
        newState.totalSessionsCompleted = 6
        newState.currentDailyStreak = 1
        newState.longestDailyStreak = 4
        newState.activeDaysCount = 9
        newState.updatedAt = t2
        var newRow = try SyncPayloadBuilder.row(for: newState)
        newRow["profile_id"] = .uuid(profileID)
        newRow["server_updated_at"] = .string(SyncJSON.iso8601String(t2))

        // Ascending `(server_updated_at, id)` order, matching what
        // `PostgRESTPullTransport` would actually deliver.
        transport.enqueueRows([oldRow, newRow], forTable: "rpg_states")

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
        )

        #expect(summary.appliedRowCounts["rpg_states"] == 2)
        #expect(summary.skippedRowCounts["rpg_states"] == 0)

        let afterCycle1 = ModelContext(container)
        let statesAfterCycle1 = try afterCycle1.fetch(FetchDescriptor<RPGState>())
        // Stabilized within ONE cycle, despite the SAME local RPGState
        // object being re-adopted twice (once per remote row) while
        // processing this page — not two local rows.
        #expect(statesAfterCycle1.count == 1)

        let final = statesAfterCycle1.first
        // Every counter is the max across ALL THREE sources (original local
        // 300/2/10, `oldState` 1000/5/50, `newState` 400/3/15) — no counter
        // lost to whichever row's id happened to "win" the id-adoption race.
        #expect(final?.xp == 1000)
        #expect(final?.level == 5)
        #expect(final?.totalReviewsCompleted == 50)
        #expect(final?.totalSessionsCompleted == 20)
        #expect(final?.currentDailyStreak == 3)
        #expect(final?.longestDailyStreak == 8)
        #expect(final?.activeDaysCount == 12)

        // The profile's relationship still points at the (re-adopted) state
        // object, whichever id it ended up with.
        let profilesAfterCycle1 = try afterCycle1.fetch(FetchDescriptor<UserProfile>())
        #expect(profilesAfterCycle1.first?.rpgState?.id == final?.id)

        // A repeat cycle with nothing new queued must not loop, re-adopt
        // again, or spawn a second local RPGState — the cursor already
        // advanced past both rows this cycle (see the cursor assertion
        // below), so a real device would not even re-deliver them.
        let summary2 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
        )
        #expect(summary2.appliedRowCounts["rpg_states"] == 0)

        let afterCycle2 = ModelContext(container)
        let statesAfterCycle2 = try afterCycle2.fetch(FetchDescriptor<RPGState>())
        #expect(statesAfterCycle2.count == 1)
        #expect(statesAfterCycle2.first?.xp == 1000)

        // Cursor advanced past both delivered rows — no stall, no drop
        // needed (nothing was skipped in the first place).
        #expect(cursorStore.cursor(forTable: "rpg_states")?.id == newState.id)
    }
}
