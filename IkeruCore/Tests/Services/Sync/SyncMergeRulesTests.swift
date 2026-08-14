import Testing
import Foundation
@testable import IkeruCore

@Suite("SyncMergeRules")
struct SyncMergeRulesTests {

    // MARK: - Rule 1: seed decision

    @Test("Empty server + populated local seeds from local — the empty-cloud-wipes-local disaster")
    func rule1EmptyServerPopulatedLocalSeedsFromLocal() {
        let decision = SyncMergeRules.seedDecision(remoteRowCount: 0, localRowCount: 42)
        #expect(decision == .seedFromLocal)
    }

    @Test("Populated server + empty local trusts the server")
    func rule1PopulatedServerEmptyLocalTrustsServer() {
        let decision = SyncMergeRules.seedDecision(remoteRowCount: 100, localRowCount: 0)
        #expect(decision == .trustServer)
    }

    @Test("Both empty trusts the server (nothing to seed either way)")
    func rule1BothEmptyTrustsServer() {
        let decision = SyncMergeRules.seedDecision(remoteRowCount: 0, localRowCount: 0)
        #expect(decision == .trustServer)
    }

    @Test("Both populated trusts the server and proceeds with the normal merge")
    func rule1BothPopulatedTrustsServer() {
        let decision = SyncMergeRules.seedDecision(remoteRowCount: 10, localRowCount: 5)
        #expect(decision == .trustServer)
    }

    // MARK: - Rule 2: FSRS replay determinism

    @Test("Replaying the same merged log set in two different orders converges to the identical FSRSState")
    func rule2ReplayIsOrderIndependent() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let logs: [SyncMergeRules.ReplayLogEntry] = [
            .init(id: UUID(), timestamp: base, grade: .good),
            .init(id: UUID(), timestamp: base.addingTimeInterval(86400 * 3), grade: .again),
            .init(id: UUID(), timestamp: base.addingTimeInterval(86400 * 5), grade: .hard),
            .init(id: UUID(), timestamp: base.addingTimeInterval(86400 * 9), grade: .easy),
        ]

        let forward = SyncMergeRules.replayFSRSState(logs: logs)
        let shuffled = SyncMergeRules.replayFSRSState(logs: logs.shuffled())
        let reversed = SyncMergeRules.replayFSRSState(logs: Array(logs.reversed()))

        #expect(forward != nil)
        #expect(forward == shuffled)
        #expect(forward == reversed)
    }

    @Test("Replay with a fully scrambled input order still converges (repeated shuffles)")
    func rule2ReplayConvergesAcrossManyShuffles() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let logs: [SyncMergeRules.ReplayLogEntry] = (0..<8).map { index in
            .init(
                id: UUID(),
                timestamp: base.addingTimeInterval(Double(index) * 86400 * 2),
                grade: Grade.allCases[index % Grade.allCases.count]
            )
        }

        let reference = SyncMergeRules.replayFSRSState(logs: logs)
        for _ in 0..<5 {
            let shuffledResult = SyncMergeRules.replayFSRSState(logs: logs.shuffled())
            #expect(shuffledResult == reference)
        }
    }

    @Test("Two logs sharing the exact same timestamp break ties deterministically by id")
    func rule2TieBreaksByIdOnEqualTimestamps() {
        let sharedTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let logsAscendingInput: [SyncMergeRules.ReplayLogEntry] = [
            .init(id: lowerID, timestamp: sharedTimestamp, grade: .again),
            .init(id: higherID, timestamp: sharedTimestamp, grade: .easy),
        ]
        let logsDescendingInput: [SyncMergeRules.ReplayLogEntry] = [
            .init(id: higherID, timestamp: sharedTimestamp, grade: .easy),
            .init(id: lowerID, timestamp: sharedTimestamp, grade: .again),
        ]

        let resultA = SyncMergeRules.replayFSRSState(logs: logsAscendingInput)
        let resultB = SyncMergeRules.replayFSRSState(logs: logsDescendingInput)

        // Both input orderings must produce the identical replayed state...
        #expect(resultA == resultB)

        // ...and that state must match "lowerID's grade applied first" (id
        // lexicographic order), not raw input order — proving the tie-break
        // is actually id-based and not an accidental artifact of stable sort.
        var expected = FSRSState()
        expected = FSRSService.schedule(state: expected, grade: .again, now: sharedTimestamp)
        expected = FSRSService.schedule(state: expected, grade: .easy, now: sharedTimestamp)
        #expect(resultA == expected)
    }

    @Test("Replaying an empty log set returns nil")
    func rule2ReplayEmptyReturnsNil() {
        #expect(SyncMergeRules.replayFSRSState(logs: []) == nil)
    }

    @Test("Union-by-id: a log id present on both devices contributes once, not twice")
    func rule2DuplicateIdCollapsesToOneContribution() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let sharedID = UUID()

        // A de-duplicated set of logs (the correct union) produces the same
        // result as the single underlying event, not a double-application
        // of the same grade.
        let dedupedLogs = [SyncMergeRules.ReplayLogEntry(id: sharedID, timestamp: timestamp, grade: .good)]
        let deduped = SyncMergeRules.replayFSRSState(logs: dedupedLogs)

        var expected = FSRSState()
        expected = FSRSService.schedule(state: expected, grade: .good, now: timestamp)

        #expect(deduped == expected)
    }

    @Test("IMPORTANT 5: an UN-deduplicated union (same id present twice in `logs`) is replayed only once, not twice")
    func rule2UndedupedDuplicateIdIsReplayedOnlyOnce() {
        // `replayFSRSState` used to document deduping-by-id as a CALLER
        // obligation (`SyncPullActor`'s own union, at the call site in
        // `replayFSRS`, never actually did this). If a duplicate id ever
        // slipped through — a page redelivered twice, a future union site
        // that forgets — the same review event would apply its grade TWICE
        // to the replayed state, every time replay runs, forever. Passing
        // the SAME entry twice (simulating that un-deduped union) must
        // still produce the state a SINGLE application of it produces, not
        // a double-application — without a fix, `.again` applied twice in a
        // row lands on a materially different (more lapsed) `FSRSState`
        // than `.again` applied once, so this fails loudly if the internal
        // dedup regresses.
        let timestamp = Date(timeIntervalSince1970: 1_700_050_000)
        let sharedID = UUID()
        let entry = SyncMergeRules.ReplayLogEntry(id: sharedID, timestamp: timestamp, grade: .again)

        let withDuplicate = SyncMergeRules.replayFSRSState(logs: [entry, entry])

        var expectedSingleApplication = FSRSState()
        expectedSingleApplication = FSRSService.schedule(state: expectedSingleApplication, grade: .again, now: timestamp)

        var doubleApplication = FSRSState()
        doubleApplication = FSRSService.schedule(state: doubleApplication, grade: .again, now: timestamp)
        doubleApplication = FSRSService.schedule(state: doubleApplication, grade: .again, now: timestamp)

        #expect(withDuplicate == expectedSingleApplication)
        #expect(withDuplicate != doubleApplication)
    }

    // MARK: - Rule 3: monotone counters

    @Test("A device behind on XP never drags a fresher, larger XP value backward")
    func rule3StaleDeviceNeverRegressesXP() {
        let ahead = SyncMergeRules.MonotoneCounters(
            xp: 5000, level: 12, totalReviewsCompleted: 900,
            totalSessionsCompleted: 80, currentDailyStreak: 3, longestDailyStreak: 10,
            activeDaysCount: 60, lastSessionDate: Date(timeIntervalSince1970: 1_700_100_000)
        )
        let stale = SyncMergeRules.MonotoneCounters(
            xp: 4200, level: 10, totalReviewsCompleted: 700,
            totalSessionsCompleted: 60, currentDailyStreak: 1, longestDailyStreak: 10,
            activeDaysCount: 55, lastSessionDate: Date(timeIntervalSince1970: 1_699_000_000)
        )

        let merged = SyncMergeRules.mergeCounters(local: stale, remote: ahead)

        #expect(merged.xp == ahead.xp)
        #expect(merged.xp >= stale.xp)
        #expect(merged.level == ahead.level)
    }

    @Test("Every monotone field merges by max(), field by field, independent of which side is 'local'")
    func rule3EveryFieldMergesByMax() {
        let sideA = SyncMergeRules.MonotoneCounters(
            xp: 100, level: 5, totalReviewsCompleted: 20,
            totalSessionsCompleted: 3, currentDailyStreak: 7, longestDailyStreak: 7,
            activeDaysCount: 10, lastSessionDate: nil
        )
        let sideB = SyncMergeRules.MonotoneCounters(
            xp: 50, level: 8, totalReviewsCompleted: 30,
            totalSessionsCompleted: 1, currentDailyStreak: 2, longestDailyStreak: 9,
            activeDaysCount: 4, lastSessionDate: nil
        )

        let merged = SyncMergeRules.mergeCounters(local: sideA, remote: sideB)

        #expect(merged.xp == 100)
        #expect(merged.level == 8)
        #expect(merged.totalReviewsCompleted == 30)
        #expect(merged.totalSessionsCompleted == 3)
        #expect(merged.currentDailyStreak == 7)
        #expect(merged.longestDailyStreak == 9)
        #expect(merged.activeDaysCount == 10)
    }

    @Test("A legitimately broken streak is preserved in longestDailyStreak even though currentDailyStreak merges by max()")
    func rule3BrokenStreakStillRecordedInLongest() {
        // Device A: streak broke, now at 1, but its historical best (10) is
        // still the largest longestDailyStreak seen anywhere.
        let deviceA = SyncMergeRules.MonotoneCounters(
            xp: 0, level: 1, totalReviewsCompleted: 0,
            totalSessionsCompleted: 0, currentDailyStreak: 1, longestDailyStreak: 10,
            activeDaysCount: 0, lastSessionDate: nil
        )
        // Device B: hasn't synced since the streak was still climbing.
        let deviceB = SyncMergeRules.MonotoneCounters(
            xp: 0, level: 1, totalReviewsCompleted: 0,
            totalSessionsCompleted: 0, currentDailyStreak: 8, longestDailyStreak: 8,
            activeDaysCount: 0, lastSessionDate: nil
        )

        let merged = SyncMergeRules.mergeCounters(local: deviceA, remote: deviceB)

        // currentDailyStreak over-reports (documented, accepted trade-off)...
        #expect(merged.currentDailyStreak == 8)
        // ...but the break is durably recorded via longestDailyStreak, which
        // never loses the historical peak either.
        #expect(merged.longestDailyStreak == 10)
    }

    @Test("lastSessionDate merges to the more recent of the two, nil-safe both ways")
    func rule3LastSessionDateMergesToMoreRecent() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        func counters(lastSessionDate: Date?) -> SyncMergeRules.MonotoneCounters {
            SyncMergeRules.MonotoneCounters(
                xp: 0, level: 1, totalReviewsCompleted: 0,
                totalSessionsCompleted: 0, currentDailyStreak: 0, longestDailyStreak: 0,
                activeDaysCount: 0, lastSessionDate: lastSessionDate
            )
        }

        #expect(SyncMergeRules.mergeCounters(
            local: counters(lastSessionDate: earlier),
            remote: counters(lastSessionDate: later)
        ).lastSessionDate == later)

        #expect(SyncMergeRules.mergeCounters(
            local: counters(lastSessionDate: nil),
            remote: counters(lastSessionDate: later)
        ).lastSessionDate == later)

        #expect(SyncMergeRules.mergeCounters(
            local: counters(lastSessionDate: earlier),
            remote: counters(lastSessionDate: nil)
        ).lastSessionDate == earlier)

        #expect(SyncMergeRules.mergeCounters(
            local: counters(lastSessionDate: nil),
            remote: counters(lastSessionDate: nil)
        ).lastSessionDate == nil)
    }

    // MARK: - Rule 4: deletion wins

    @Test("Local deletion wins over a remote modification that happened later")
    func rule4LocalDeletionWinsOverLaterRemoteEdit() {
        let deletedEarlier = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deletedAt: Date(timeIntervalSince1970: 1_000)
        )
        let editedLater = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 5_000),
            deletedAt: nil
        )

        let winner = SyncMergeRules.resolveWinner(local: deletedEarlier, remote: editedLater)
        #expect(winner == .local)
    }

    @Test("Remote deletion wins over a local modification that happened later")
    func rule4RemoteDeletionWinsOverLaterLocalEdit() {
        let editedLater = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 5_000),
            deletedAt: nil
        )
        let deletedEarlier = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deletedAt: Date(timeIntervalSince1970: 1_000)
        )

        let winner = SyncMergeRules.resolveWinner(local: editedLater, remote: deletedEarlier)
        #expect(winner == .remote)
    }

    @Test("Both sides deleted resolves deterministically without it being a meaningful choice")
    func rule4BothDeletedResolvesDeterministically() {
        let deletedA = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deletedAt: Date(timeIntervalSince1970: 1_000)
        )
        let deletedB = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deletedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(SyncMergeRules.resolveWinner(local: deletedA, remote: deletedB) == .local)
    }

    @Test("Neither side deleted falls through to last-write-wins on updatedAt")
    func rule4NoDeletionFallsThroughToLWW() {
        let olderLocal = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deletedAt: nil
        )
        let newerRemote = SyncMergeRules.SyncClock(
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deletedAt: nil
        )

        #expect(SyncMergeRules.resolveWinner(local: olderLocal, remote: newerRemote) == .remote)
        #expect(SyncMergeRules.resolveWinner(local: newerRemote, remote: olderLocal) == .local)
    }
}
