import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

// MARK: - MasteryBookSnapshotStoreTests
//
// Regression coverage for chantier #45f: `priorSnapshot` and `recordIfStale`
// used to gate on the SAME age threshold in the SAME pass, so the "+N cette
// semaine" badge appeared on exactly one Home load per week (the one where
// the baseline turned 6 days old) and then vanished immediately, because
// that very load also rolled the baseline forward to today.

@Suite("MasteryBookSnapshotStore")
struct MasteryBookSnapshotStoreTests {

    /// Every test uses a fresh UUID so runs never collide with each other or
    /// with a real device's data, and cleans up afterwards so
    /// `UserDefaults.standard` doesn't accumulate leftover test keys.
    private func makeCounts(mastered: Int) -> MasteryBookCounts {
        MasteryBookCounts(masteredCount: mastered)
    }

    @Test("No baseline recorded yet returns nil")
    func noBaselineReturnsNil() {
        let profileID = UUID()
        defer { MasteryBookSnapshotStore.clear(profileID: profileID) }

        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileID) == nil)
    }

    @Test("A freshly seeded baseline is readable immediately, not gated by age")
    func baselineReadableImmediately() {
        let profileID = UUID()
        defer { MasteryBookSnapshotStore.clear(profileID: profileID) }
        let day0 = Date()
        let counts0 = makeCounts(mastered: 3)

        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts0, now: day0)

        // Previously `priorSnapshot` required the stored baseline to be
        // >= 6 days old, so a baseline seeded moments ago was invisible.
        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileID) == counts0)
    }

    @Test("The delta stays visible across consecutive loads within the week")
    func deltaPersistsAcrossConsecutiveLoads() {
        let profileID = UUID()
        defer { MasteryBookSnapshotStore.clear(profileID: profileID) }
        let day0 = Date()
        let counts0 = makeCounts(mastered: 3)
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts0, now: day0)

        // Day 1: the learner masters 2 more cards. Mirrors
        // `HomeViewModel.loadMasteryBook()`'s read-then-record order.
        let day1 = day0.addingTimeInterval(1 * 86_400)
        let counts1 = makeCounts(mastered: 5)
        let delta1 = MasteryBookSnapshotStore.priorSnapshot(profileID: profileID)
            .map { counts1.delta(from: $0) }
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts1, now: day1)
        #expect(delta1 == 2)

        // Day 2: a second Home load the very next day must still see the
        // SAME baseline (and thus the same accrued delta) — this is exactly
        // the bug: the baseline used to roll forward on the same pass that
        // computed the delta, hiding the badge on the very next look.
        let day2 = day0.addingTimeInterval(2 * 86_400)
        let counts2 = makeCounts(mastered: 5) // no further progress since day1
        let delta2 = MasteryBookSnapshotStore.priorSnapshot(profileID: profileID)
            .map { counts2.delta(from: $0) }
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts2, now: day2)
        #expect(delta2 == 2)
    }

    @Test("The baseline only rolls forward once it's a full week old")
    func baselineRollsForwardAfterAWeek() {
        let profileID = UUID()
        defer { MasteryBookSnapshotStore.clear(profileID: profileID) }
        let day0 = Date()
        let counts0 = makeCounts(mastered: 3)
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts0, now: day0)

        // Just under a week old: baseline must NOT roll forward yet.
        let day6 = day0.addingTimeInterval(6 * 86_400 + 3_600)
        let counts6 = makeCounts(mastered: 8)
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts6, now: day6)
        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileID) == counts0)

        // A full week old: baseline rolls forward to the latest counts.
        let day7 = day0.addingTimeInterval(7 * 86_400)
        let counts7 = makeCounts(mastered: 9)
        MasteryBookSnapshotStore.recordIfStale(profileID: profileID, counts: counts7, now: day7)
        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileID) == counts7)
    }

    @Test("clear removes only the targeted profile's baseline")
    func clearRemovesOnlyThatProfile() {
        let profileA = UUID()
        let profileB = UUID()
        defer {
            MasteryBookSnapshotStore.clear(profileID: profileA)
            MasteryBookSnapshotStore.clear(profileID: profileB)
        }
        let now = Date()
        MasteryBookSnapshotStore.recordIfStale(profileID: profileA, counts: makeCounts(mastered: 1), now: now)
        MasteryBookSnapshotStore.recordIfStale(profileID: profileB, counts: makeCounts(mastered: 2), now: now)

        MasteryBookSnapshotStore.clear(profileID: profileA)

        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileA) == nil)
        #expect(MasteryBookSnapshotStore.priorSnapshot(profileID: profileB) == makeCounts(mastered: 2))
    }
}
