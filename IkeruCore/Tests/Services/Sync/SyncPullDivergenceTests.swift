import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Divergence tests for the pull engine (`SyncPullActor`) — the delivery
/// condition for cloud-sync lot 2, per
/// `docs/design-specs/2026-08-10-cloud-sync-design.md` §10: "**Le lot
/// dangereux** : il ne se livre qu'avec des tests de divergence (deux
/// appareils hors-ligne, notes concurrentes, suppression concurrente)."
///
/// Two devices are simulated as two separate in-memory `ModelContainer`s,
/// each with its OWN `SyncCursorStore` (a cursor is per-device local state
/// in the real architecture — see `SyncCursorStore.swift` — so sharing one
/// between two simulated devices would be a test bug, not a realistic
/// scenario), synchronized through one shared `FakeSyncServer` (below) that
/// implements BOTH `SyncDataTransport` and `SyncPullTransport` over a
/// single in-memory table store — the piece of infrastructure needed to
/// make one device's push visible to another device's pull, which neither
/// `MockSyncDataTransport` nor `MockSyncPullTransport` alone provides (each
/// is scoped to recording calls for a single role).
///
/// `syncDevice` below deliberately mirrors `CloudSyncCoordinator.syncNow()`'s
/// own ordering — pull, then push, using the exact same 7-call push
/// sequence — because the concurrent-deletion test specifically exercises
/// why that ordering matters (see that test's doc comment): pulling before
/// pushing is what lets a device that's about to push a stale value
/// reconcile against a fresher remote tombstone FIRST, rather than
/// clobbering it. `CloudSyncCoordinator` itself is not used directly here
/// (it also requires consent/throttle/identity wiring that's orthogonal to
/// what this suite verifies) — driving `SyncPullActor` + `SyncModelActor`
/// directly keeps each test focused on merge-rule correctness.
@Suite("SyncPullDivergence")
@MainActor
struct SyncPullDivergenceTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            ExerciseOutcomeLog.self,
            CompanionChatMessage.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// One full sync cycle for one simulated device: pull, then push —
    /// same order, same 7 push calls, as `CloudSyncCoordinator.syncNow()`.
    @discardableResult
    private func syncDevice(
        container: ModelContainer,
        server: FakeSyncServer,
        cursorStore: any SyncCursorStore,
        accessToken: String = "device-token"
    ) async throws -> SyncPullActor.PullSummary {
        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(transport: server, cursorStore: cursorStore, accessToken: accessToken)

        let pushActor = SyncModelActor(modelContainer: container)
        _ = try await pushActor.pushAllProfiles(using: server, accessToken: accessToken)
        _ = try await pushActor.pushAllRPGStates(using: server, accessToken: accessToken)
        _ = try await pushActor.pushDirtyCards(using: server, accessToken: accessToken)
        _ = try await pushActor.pushDirtyReviewLogs(using: server, accessToken: accessToken)
        _ = try await pushActor.pushDirtyVocabularyEntries(using: server, accessToken: accessToken)
        _ = try await pushActor.pushDirtyVocabularyEncounters(using: server, accessToken: accessToken)
        _ = try await pushActor.pushDirtyExerciseOutcomeLogs(using: server, accessToken: accessToken)

        return summary
    }

    // MARK: - Seeding / reading helpers (fresh `ModelContext` per call — see
    // `CloudSyncCoordinatorTests.fetchCard`'s doc comment for why: no
    // stale identity-map entries to go stale across these direct
    // manipulations).

    private func seedCard(id: UUID, updatedAt: Date, syncedAt: Date?, into container: ModelContainer) throws {
        let context = ModelContext(container)
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.id = id
        card.updatedAt = updatedAt
        card.syncedAt = syncedAt
        context.insert(card)
        try context.save()
    }

    private func gradeCard(id: UUID, grade: Grade, timestamp: Date, in container: ModelContainer) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let card = try context.fetch(descriptor).first else {
            Issue.record("gradeCard: card \(id) not found")
            return
        }
        // Mirrors `CardRepository.gradeCard`'s FSRS bookkeeping (that file
        // is out of this lot's perimeter, so this is a small, deliberate,
        // self-contained re-implementation for test fixtures, not a call
        // into it).
        let newState = FSRSService.schedule(state: card.fsrsState, grade: grade, now: timestamp)
        let newDueDate = FSRSService.dueDate(for: newState, desiredRetention: 0.9, now: timestamp)
        card.fsrsState = newState
        card.lapseCount = newState.lapses
        card.interval = max(1, Int(newDueDate.timeIntervalSince(timestamp) / 86400))
        card.dueDate = newDueDate
        card.updatedAt = timestamp

        let log = ReviewLog(card: card, grade: grade, responseTimeMs: 500, timestamp: timestamp)
        log.updatedAt = timestamp
        context.insert(log)
        try context.save()
    }

    private func deleteCard(id: UUID, timestamp: Date, in container: ModelContainer) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let card = try context.fetch(descriptor).first else {
            Issue.record("deleteCard: card \(id) not found")
            return
        }
        card.deletedAt = timestamp
        card.updatedAt = timestamp
        try context.save()
    }

    private func fetchCard(id: UUID, in container: ModelContainer) throws -> Card? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func seedRPGState(id: UUID, xp: Int, level: Int, into container: ModelContainer) throws {
        let context = ModelContext(container)
        let state = RPGState(xp: xp, level: level)
        state.id = id
        context.insert(state)
        try context.save()
    }

    private func fetchRPGState(id: UUID, in container: ModelContainer) throws -> RPGState? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<RPGState>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    private func seedRichLocalState(into container: ModelContainer) throws -> (profileID: UUID, cardID: UUID) {
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Learner")
        context.insert(profile)
        // `UserProfile.init` already mints an `RPGState` — reuse it rather
        // than inserting a second one (see `SyncPullActor.applyRPGStateRows`'s
        // orphan-adoption doc comment for why a stray second `RPGState`
        // matters).
        profile.rpgState?.xp = 500
        profile.rpgState?.level = 3

        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile
        context.insert(card)

        let log = ReviewLog(card: card, grade: .good, responseTimeMs: 400)
        context.insert(log)

        try context.save()
        return (profile.id, card.id)
    }

    // MARK: - Test 1: two offline devices grading the same card converge

    @Test("Two offline devices grading the same card converge to the identical FSRS state")
    func twoDevicesGradingSameCardConverge() async throws {
        let server = FakeSyncServer()
        let containerA = try makeContainer()
        let containerB = try makeContainer()
        let cursorA = MockSyncCursorStore()
        let cursorB = MockSyncCursorStore()

        let cardID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Both devices already have the SAME card, already synced — the
        // starting point before they go offline and diverge.
        try seedCard(id: cardID, updatedAt: t0, syncedAt: t0, into: containerA)
        try seedCard(id: cardID, updatedAt: t0, syncedAt: t0, into: containerB)

        // Device A grades it .good at t1, offline.
        let t1 = t0.addingTimeInterval(3600)
        try gradeCard(id: cardID, grade: .good, timestamp: t1, in: containerA)

        // Device B grades the SAME card .again at t2, independently offline
        // — neither device has seen the other's review yet.
        let t2 = t0.addingTimeInterval(7200)
        try gradeCard(id: cardID, grade: .again, timestamp: t2, in: containerB)

        // A comes online first: pulls (nothing new yet), pushes its grade.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)
        // B comes online: pulls A's log (merges + replays against its own),
        // pushes its own grade + the merged card state.
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB)
        // A syncs again (e.g. the next foreground trigger): pulls B's log,
        // merges + replays too.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)

        let finalA = try fetchCard(id: cardID, in: containerA)
        let finalB = try fetchCard(id: cardID, in: containerB)

        // Both devices must now hold BOTH review logs (union by id) — not
        // just their own.
        #expect(finalA?.reviewLogs?.count == 2)
        #expect(finalB?.reviewLogs?.count == 2)

        // The expected state is derived from whichever device's logs we
        // read (not hardcoded), so this asserts convergence structurally:
        // if A and B's logs differ at all, this cross-check fails.
        let logsFromA = (finalA?.reviewLogs ?? []).map {
            SyncMergeRules.ReplayLogEntry(id: $0.id, timestamp: $0.timestamp, grade: $0.grade)
        }
        let expected = SyncMergeRules.replayFSRSState(logs: logsFromA)

        #expect(finalA?.fsrsState == expected)
        #expect(finalB?.fsrsState == expected)
        #expect(finalA?.fsrsState == finalB?.fsrsState)
        #expect(finalA?.lapseCount == finalB?.lapseCount)
        #expect(finalA?.dueDate == finalB?.dueDate)
    }

    // MARK: - Test 2: concurrent deletion beats concurrent modification

    @Test("A deletes a card while B modifies it concurrently — after both sync, it is deleted everywhere")
    func concurrentDeletionWinsEverywhere() async throws {
        let server = FakeSyncServer()
        let containerA = try makeContainer()
        let containerB = try makeContainer()
        let cursorA = MockSyncCursorStore()
        let cursorB = MockSyncCursorStore()

        let cardID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_100_000)
        try seedCard(id: cardID, updatedAt: t0, syncedAt: t0, into: containerA)
        try seedCard(id: cardID, updatedAt: t0, syncedAt: t0, into: containerB)

        // A deletes at t1.
        let t1 = t0.addingTimeInterval(3600)
        try deleteCard(id: cardID, timestamp: t1, in: containerA)

        // B modifies (grades) the SAME card at t2 — deliberately LATER than
        // A's deletion, so a naive last-write-wins on `updatedAt` would
        // pick B's edit. Rule 4 must make the deletion win regardless of
        // which side's clock is newer.
        let t2 = t0.addingTimeInterval(7200)
        try gradeCard(id: cardID, grade: .good, timestamp: t2, in: containerB)

        // A syncs first: pushes its tombstone to the server.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)
        // B syncs: PULLS FIRST, so it reconciles against A's tombstone
        // (rule 4) BEFORE its own push would otherwise clobber it —
        // exactly why `CloudSyncCoordinator.syncNow()` pulls before it
        // pushes. B's local card becomes tombstoned here.
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB)
        // A syncs again — confirms the deletion is stable, not resurrected
        // by anything B pushed.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)

        let finalA = try fetchCard(id: cardID, in: containerA)
        let finalB = try fetchCard(id: cardID, in: containerB)

        #expect(finalA?.deletedAt != nil)
        #expect(finalB?.deletedAt != nil)
    }

    // MARK: - Test 3: empty cloud + populated local loses nothing (rule 1)

    @Test("Empty cloud, populated local: after the first pull, nothing local is lost")
    func emptyCloudPopulatedLocalLosesNothing() async throws {
        // Genuinely empty — nothing is ever pushed to this server.
        let server = FakeSyncServer()
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()

        let seeded = try seedRichLocalState(into: container)

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(transport: server, cursorStore: cursorStore, accessToken: "token")

        // Rule 1 must have fired: nothing applied, seed decision recorded.
        #expect(summary.seededFromLocal == true)
        #expect(summary.totalApplied == 0)

        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        let states = try context.fetch(FetchDescriptor<RPGState>())

        #expect(profiles.count == 1)
        #expect(cards.count == 1)
        #expect(logs.count == 1)
        #expect(states.count == 1)
        #expect(profiles.first?.id == seeded.profileID)
        #expect(cards.first?.id == seeded.cardID)
        #expect(cards.first?.deletedAt == nil)
        #expect(states.first?.xp == 500)
        #expect(states.first?.level == 3)
    }

    // MARK: - Test 4: counters never regress on a lagging device

    @Test("A device far behind on XP never drags a fresher, higher value backward after merging")
    func laggingDeviceNeverRegressesXP() async throws {
        let server = FakeSyncServer()
        let containerA = try makeContainer()
        let containerB = try makeContainer()
        let cursorA = MockSyncCursorStore()
        let cursorB = MockSyncCursorStore()

        let stateID = UUID()

        // A is already ahead — xp 1000, level 5 — and syncs first.
        try seedRPGState(id: stateID, xp: 1000, level: 5, into: containerA)
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)

        // B has been offline a long time and is stuck on a stale, LOWER
        // snapshot — xp 200, level 2 — for the SAME rpg_state id.
        try seedRPGState(id: stateID, xp: 200, level: 2, into: containerB)
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB)

        // B must have merged UP to the higher remote value, not stayed at
        // (or pushed) its stale one.
        let stateB = try fetchRPGState(id: stateID, in: containerB)
        #expect(stateB?.xp == 1000)
        #expect(stateB?.level == 5)

        // A syncs again — must still read 1000. If B's stale push had
        // somehow reached the server as a raw overwrite (rather than
        // merging locally before pushing), this would regress to 200.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)
        let stateA = try fetchRPGState(id: stateID, in: containerA)
        #expect(stateA?.xp == 1000)
        #expect(stateA?.level == 5)
    }

    // MARK: - Test 5: idempotence

    @Test("Re-applying the same page of remote rows twice does not duplicate rows or change state")
    func idempotentReapplicationOfSamePage() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let transport = MockSyncPullTransport()

        let cardID = UUID()
        let logID = UUID()
        let cardUpdatedAt = Date(timeIntervalSince1970: 1_700_200_000)
        let logTimestamp = Date(timeIntervalSince1970: 1_700_200_500)

        // Build realistic rows through the SAME builder the push side uses
        // (the reverse of what `SyncPullActor` decodes), rather than
        // hand-rolling `SyncRow` dictionaries that could drift from the
        // real wire shape.
        let scratchCard = Card(front: "猫", back: "cat", type: .vocabulary)
        scratchCard.id = cardID
        scratchCard.updatedAt = cardUpdatedAt
        var cardRow = try SyncPayloadBuilder.row(for: scratchCard)
        cardRow["server_updated_at"] = .string(SyncJSON.iso8601String(cardUpdatedAt))

        let scratchLog = ReviewLog(card: scratchCard, grade: .good, responseTimeMs: 400, timestamp: logTimestamp)
        scratchLog.id = logID
        scratchLog.updatedAt = logTimestamp
        var logRow = try SyncPayloadBuilder.row(for: scratchLog)
        logRow["server_updated_at"] = .string(SyncJSON.iso8601String(logTimestamp))

        // Enqueue the SAME two pages TWICE — one page consumed per
        // `pullAll` run below, so the second run sees byte-identical
        // redelivered rows, exactly like the `gte` cursor boundary
        // re-fetching an already-applied row for real.
        for _ in 0..<2 {
            transport.enqueueRows([cardRow], forTable: "cards")
            transport.enqueueRows([logRow], forTable: "review_logs")
        }

        let pullActor = SyncPullActor(modelContainer: container)
        _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, accessToken: "token")

        let afterFirst = ModelContext(container)
        let cardsAfterFirst = try afterFirst.fetch(FetchDescriptor<Card>())
        let logsAfterFirst = try afterFirst.fetch(FetchDescriptor<ReviewLog>())
        #expect(cardsAfterFirst.count == 1)
        #expect(logsAfterFirst.count == 1)
        let stateAfterFirst = cardsAfterFirst.first?.fsrsState
        let dueDateAfterFirst = cardsAfterFirst.first?.dueDate

        _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, accessToken: "token")

        let afterSecond = ModelContext(container)
        let cardsAfterSecond = try afterSecond.fetch(FetchDescriptor<Card>())
        let logsAfterSecond = try afterSecond.fetch(FetchDescriptor<ReviewLog>())

        #expect(cardsAfterSecond.count == 1)
        #expect(logsAfterSecond.count == 1)
        #expect(cardsAfterSecond.first?.id == cardID)
        #expect(logsAfterSecond.first?.id == logID)
        #expect(cardsAfterSecond.first?.fsrsState == stateAfterFirst)
        #expect(cardsAfterSecond.first?.dueDate == dueDateAfterFirst)
    }

    // MARK: - Bonus: RPGState orphan-adoption on a freshly-pulled profile

    @Test("Pulling a profile then its rpg_state adopts the profile's auto-created RPGState instead of orphaning it")
    func rpgStateAdoptsFreshProfileOrphan() async throws {
        // Device A: a profile with its RPGState, both pushed together.
        let server = FakeSyncServer()
        let containerA = try makeContainer()
        let cursorA = MockSyncCursorStore()

        let context = ModelContext(containerA)
        let profile = UserProfile(displayName: "Learner")
        profile.rpgState?.xp = 77
        context.insert(profile)
        try context.save()

        try await syncDevice(container: containerA, server: server, cursorStore: cursorA)

        // Device B: brand new, never seen this profile before. Its OWN
        // `UserProfile.init` will mint a fresh, unrelated `RPGState` with a
        // random id the instant the `profiles` row is applied — before the
        // `rpg_states` row (a DIFFERENT id) arrives moments later in the
        // very same pull cycle.
        let containerB = try makeContainer()
        let cursorB = MockSyncCursorStore()
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB)

        let contextB = ModelContext(containerB)
        let profilesB = try contextB.fetch(FetchDescriptor<UserProfile>())
        let statesB = try contextB.fetch(FetchDescriptor<RPGState>())

        #expect(profilesB.count == 1)
        // Exactly one RPGState — not two (the auto-created one plus a
        // second one for the pulled `rpg_states` row).
        #expect(statesB.count == 1)
        #expect(statesB.first?.xp == 77)
        #expect(profilesB.first?.rpgState?.id == statesB.first?.id)
    }
}

// MARK: - FakeSyncServer

/// A minimal shared fake server: implements BOTH `SyncDataTransport` (push)
/// and `SyncPullTransport` (pull) over ONE in-memory table store, so a push
/// from one simulated device becomes visible to a `fetchRows` call from
/// another — the one piece of infrastructure `MockSyncDataTransport` and
/// `MockSyncPullTransport` don't provide alone (each only records calls for
/// its own single role). Rows are keyed by `(table, id)`; `upsert`
/// overwrites by id and stamps a monotonically increasing
/// `server_updated_at` on every write — mirroring the real
/// `touch_server_updated_at()` trigger's guarantee (verified in
/// `SyncCursorStore.swift`'s doc comment) that it never goes backward.
final class FakeSyncServer: SyncDataTransport, SyncPullTransport, @unchecked Sendable {

    private var tables: [String: [String: SyncRow]] = [:]
    private var clockTick: TimeInterval = 1_650_000_000
    private let lock = NSLock()

    func upsert(table: String, rows: [SyncRow], accessToken: String) async throws {
        guard !rows.isEmpty else { return }
        // `withLock` runs the whole critical section synchronously, so it's
        // safe to call from this `async` function — same pattern
        // `MockSyncDataTransport.upsert` / `MockSyncPullTransport.fetchRows`
        // use, for the same `lock()`/`unlock()`-are-`noasync` reason.
        lock.withLock {
            var stored = tables[table, default: [:]]
            for row in rows {
                guard case .string(let idString)? = row["id"] else { continue }
                clockTick += 1
                var stamped = row
                stamped["server_updated_at"] = .string(SyncJSON.iso8601String(Date(timeIntervalSince1970: clockTick)))
                stored[idString] = stamped
            }
            tables[table] = stored
        }
    }

    func fetchRows(table: String, since: Date?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        lock.withLock {
            let rows = Array((tables[table] ?? [:]).values)
            let filtered: [SyncRow]
            if let since {
                filtered = rows.filter { row in
                    guard case .string(let raw)? = row["server_updated_at"],
                          let stamped = SyncJSON.dateFormatter.date(from: raw) else { return false }
                    return stamped >= since
                }
            } else {
                filtered = rows
            }
            let sorted = filtered.sorted { lhs, rhs in
                guard case .string(let lRaw)? = lhs["server_updated_at"],
                      let lDate = SyncJSON.dateFormatter.date(from: lRaw),
                      case .string(let rRaw)? = rhs["server_updated_at"],
                      let rDate = SyncJSON.dateFormatter.date(from: rRaw) else { return false }
                if lDate != rDate { return lDate < rDate }
                guard case .string(let lID)? = lhs["id"], case .string(let rID)? = rhs["id"] else { return false }
                return lID < rID
            }
            return Array(sorted.prefix(limit))
        }
    }
}
