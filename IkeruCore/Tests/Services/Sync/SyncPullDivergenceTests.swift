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

    // Not `private`: `SyncPullDivergenceTests+PoisonRow.swift`'s extension
    // (a separate file, split out purely to stay under SwiftLint's
    // `type_body_length` budget — see that file's doc comment) needs this
    // too, and cross-file access needs at least `internal` (Swift's
    // `private` is file-scoped).
    func makeContainer() throws -> ModelContainer {
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
        skipTracker: any SyncSkipTracker,
        accessToken: String = "device-token"
    ) async throws -> SyncPullActor.PullSummary {
        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(
            transport: server,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: accessToken
        )

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
        let skipA = MockSyncSkipTracker()
        let skipB = MockSyncSkipTracker()

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
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)
        // B comes online: pulls A's log (merges + replays against its own),
        // pushes its own grade + the merged card state.
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB, skipTracker: skipB)
        // A syncs again (e.g. the next foreground trigger): pulls B's log,
        // merges + replays too.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)

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
        let skipA = MockSyncSkipTracker()
        let skipB = MockSyncSkipTracker()

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
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)
        // B syncs: PULLS FIRST, so it reconciles against A's tombstone
        // (rule 4) BEFORE its own push would otherwise clobber it —
        // exactly why `CloudSyncCoordinator.syncNow()` pulls before it
        // pushes. B's local card becomes tombstoned here.
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB, skipTracker: skipB)
        // A syncs again — confirms the deletion is stable, not resurrected
        // by anything B pushed.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)

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
        let skipTracker = MockSyncSkipTracker()

        let seeded = try seedRichLocalState(into: container)

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(transport: server, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")

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
        let skipA = MockSyncSkipTracker()
        let skipB = MockSyncSkipTracker()

        let stateID = UUID()

        // A is already ahead — xp 1000, level 5 — and syncs first.
        try seedRPGState(id: stateID, xp: 1000, level: 5, into: containerA)
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)

        // B has been offline a long time and is stuck on a stale, LOWER
        // snapshot — xp 200, level 2 — for the SAME rpg_state id.
        try seedRPGState(id: stateID, xp: 200, level: 2, into: containerB)
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB, skipTracker: skipB)

        // B must have merged UP to the higher remote value, not stayed at
        // (or pushed) its stale one.
        let stateB = try fetchRPGState(id: stateID, in: containerB)
        #expect(stateB?.xp == 1000)
        #expect(stateB?.level == 5)

        // A syncs again — must still read 1000. If B's stale push had
        // somehow reached the server as a raw overwrite (rather than
        // merging locally before pushing), this would regress to 200.
        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)
        let stateA = try fetchRPGState(id: stateID, in: containerA)
        #expect(stateA?.xp == 1000)
        #expect(stateA?.level == 5)
    }

    // MARK: - Test 5: idempotence

    @Test("Re-applying the same page of remote rows twice does not duplicate rows or change state")
    func idempotentReapplicationOfSamePage() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
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
        _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")

        let afterFirst = ModelContext(container)
        let cardsAfterFirst = try afterFirst.fetch(FetchDescriptor<Card>())
        let logsAfterFirst = try afterFirst.fetch(FetchDescriptor<ReviewLog>())
        #expect(cardsAfterFirst.count == 1)
        #expect(logsAfterFirst.count == 1)
        let stateAfterFirst = cardsAfterFirst.first?.fsrsState
        let dueDateAfterFirst = cardsAfterFirst.first?.dueDate

        _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")

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
        let skipA = MockSyncSkipTracker()

        let context = ModelContext(containerA)
        let profile = UserProfile(displayName: "Learner")
        profile.rpgState?.xp = 77
        context.insert(profile)
        try context.save()

        try await syncDevice(container: containerA, server: server, cursorStore: cursorA, skipTracker: skipA)

        // Device B: brand new, never seen this profile before. Its OWN
        // `UserProfile.init` will mint a fresh, unrelated `RPGState` with a
        // random id the instant the `profiles` row is applied — before the
        // `rpg_states` row (a DIFFERENT id) arrives moments later in the
        // very same pull cycle.
        let containerB = try makeContainer()
        let cursorB = MockSyncCursorStore()
        let skipB = MockSyncSkipTracker()
        try await syncDevice(container: containerB, server: server, cursorStore: cursorB, skipTracker: skipB)

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

    // MARK: - Test 6 (CRITIQUE 1): a row skipped mid-page must not let the
    // cursor skip past it

    @Test("CRITIQUE 1: a row skipped mid-page does not let the cursor advance past it — it is re-fetched on the next cycle")
    func skippedRowMidPageIsNotLostByCursorAdvance() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // Already local, as if a previous cycle already pulled it — logs
        // referencing it can attach immediately.
        let cardID = UUID()
        try seedCard(
            id: cardID,
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            syncedAt: Date(timeIntervalSince1970: 1_699_000_000),
            into: container
        )
        let scratchCard = Card(front: "犬", back: "dog", type: .vocabulary)
        scratchCard.id = cardID

        let t1 = Date(timeIntervalSince1970: 1_700_300_000)
        let t2 = t1.addingTimeInterval(10)
        let t3 = t1.addingTimeInterval(20)

        // log1: valid, attaches to `cardID` — APPLIES.
        let log1 = ReviewLog(card: scratchCard, grade: .good, responseTimeMs: 300, timestamp: t1)
        log1.updatedAt = t1
        var log1Row = try SyncPayloadBuilder.row(for: log1)
        log1Row["server_updated_at"] = .string(SyncJSON.iso8601String(t1))

        // log2: references a card that does NOT exist locally — SKIPPED.
        // Sits in the MIDDLE of the page, between two rows that both
        // apply fine — the exact shape CRITIQUE 1 describes (a log for a
        // card this device hasn't pulled yet, delivered alongside logs
        // that DO apply in the same page).
        let orphanCardID = UUID()
        let log2 = ReviewLog(card: scratchCard, grade: .again, responseTimeMs: 300, timestamp: t2)
        log2.updatedAt = t2
        var log2Row = try SyncPayloadBuilder.row(for: log2)
        log2Row["card_id"] = .uuid(orphanCardID)
        log2Row["server_updated_at"] = .string(SyncJSON.iso8601String(t2))

        // log3: valid, attaches to `cardID` — APPLIES, but comes AFTER
        // the skipped row. Before the CRITIQUE 1 fix, `advanceCursor` was
        // called with the WHOLE page, so its `max(server_updated_at)`
        // would be t3 — past log2 — and log2 would never be re-fetched.
        let log3 = ReviewLog(card: scratchCard, grade: .good, responseTimeMs: 300, timestamp: t3)
        log3.updatedAt = t3
        var log3Row = try SyncPayloadBuilder.row(for: log3)
        log3Row["server_updated_at"] = .string(SyncJSON.iso8601String(t3))

        transport.enqueueRows([log1Row, log2Row, log3Row], forTable: "review_logs")

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")

        // log1 and log3 both applied — log2 is the only skip.
        #expect(summary.appliedRowCounts["review_logs"] == 2)
        #expect(summary.skippedRowCounts["review_logs"] == 1)

        // The cursor must NOT have advanced past log2's position: it can
        // only certify the prefix up to (and including) log1, since log2
        // — mid-page — failed to apply.
        let expectedPosition = SyncCursorPosition(timestamp: SyncJSON.iso8601String(t1), id: log1.id)
        let advancedCursor = cursorStore.cursor(forTable: "review_logs")
        #expect(advancedCursor == expectedPosition)
        #expect(advancedCursor?.id != log3.id)

        // A follow-up cycle re-queries `review_logs` from that safe
        // boundary (log1's position), NOT from log3's — proving log2 (and
        // log3, its safe-to-redeliver neighbor) are not permanently lost,
        // only deferred to the next cycle, exactly like a real keyset
        // re-fetch would redeliver them once log2's card shows up.
        _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")
        let secondCall = transport.calls(forTable: "review_logs").last
        #expect(secondCall?.since == expectedPosition)
    }

    // MARK: - Test 8 (CRITIQUE 2): an undecodable row must not block tables
    // pulled after it

    @Test("CRITIQUE 2: an undecodable row in one table does not block tables pulled after it in pullOrder")
    func undecodableRowDoesNotBlockSubsequentTables() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // A `cards` row whose `payload` is missing every required field
        // (`front`, `back`, `type`, …) — cannot decode as `CardPayload`.
        // Before CRITIQUE 2, the non-append-only apply functions called
        // `SyncRowDecoding.decode` with a bare `try`, so this row's decode
        // failure threw straight out of `applyCardRows`, out of
        // `pullAndApply`, and out of `pullAll` — aborting `review_logs`,
        // `vocabulary_entries`, and every table after `cards` in
        // `pullOrder` for the ENTIRE cycle, not just this one bad row.
        let badCardID = UUID()
        let badTimestamp = Date(timeIntervalSince1970: 1_700_500_000)
        let badCardRow: SyncRow = [
            "id": .uuid(badCardID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(badTimestamp),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(badTimestamp)),
        ]
        transport.enqueueRows([badCardRow], forTable: "cards")

        // A perfectly valid `vocabulary_entries` row — pulled right AFTER
        // `cards` in `pullOrder` — is what must still succeed.
        let entry = VocabularyEntry(word: "水", reading: "みず", meaning: "water")
        let entryTimestamp = badTimestamp.addingTimeInterval(100)
        entry.updatedAt = entryTimestamp
        var entryRow = try SyncPayloadBuilder.row(for: entry)
        entryRow["server_updated_at"] = .string(SyncJSON.iso8601String(entryTimestamp))
        transport.enqueueRows([entryRow], forTable: "vocabulary_entries")

        let pullActor = SyncPullActor(modelContainer: container)
        // Must NOT throw — the whole point of CRITIQUE 2.
        let summary = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")

        #expect(summary.appliedRowCounts["cards"] == 0)
        #expect(summary.skippedRowCounts["cards"] == 1)
        // The table pulled right after `cards` still ran and applied its
        // row — proving the decode failure didn't abort the whole cycle.
        #expect(summary.appliedRowCounts["vocabulary_entries"] == 1)

        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.word == "水")

        // The bad card was never created locally.
        let badCardDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == badCardID })
        let badCards = try context.fetch(badCardDescriptor)
        #expect(badCards.isEmpty)
    }

    // MARK: - Test 9 (IMPORTANT 4): a remote win must not overwrite FSRS
    // scheduling fields ahead of the replay that's supposed to own them

    @Test("IMPORTANT 4: a remote win against a card with local review logs does not overwrite its FSRS scheduling fields before replay runs")
    func remoteWinDoesNotOverwriteSchedulingAheadOfReplay() async throws {
        let container = try makeContainer()
        // NOT a bare `MockSyncCursorStore()`: with every table's cursor
        // `nil`, `pullAll`'s rule-1 cold-start guard primes a FIRST page
        // for every table — including `review_logs` — BEFORE the normal
        // per-table loop even starts, so `TableFailingTransport` (below)
        // would fail on that priming call and abort before `cards` ever
        // gets its chance to apply. Pre-seeding `review_logs`'s own cursor
        // makes `isColdStart` false, so the normal `pullOrder` sequence
        // (`cards` before `review_logs`) is what actually runs.
        let cursorStore = MockSyncCursorStore(cursors: [
            "review_logs": SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: 1)), id: UUID()),
        ])
        let skipTracker = MockSyncSkipTracker()

        let cardID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_600_000)
        try seedCard(id: cardID, updatedAt: t0, syncedAt: t0, into: container)

        // Local device grades the card — this both creates a local
        // `ReviewLog` AND advances the card's own
        // `fsrsState`/`interval`/`dueDate`/`lapseCount` locally, while
        // `updatedAt` stays behind whatever the remote row below claims
        // (so the remote wins the LWW check).
        let t1 = t0.addingTimeInterval(3600)
        try gradeCard(id: cardID, grade: .good, timestamp: t1, in: container)

        let localBefore = try #require(try fetchCard(id: cardID, in: container))
        let fsrsStateBefore = localBefore.fsrsState
        let intervalBefore = localBefore.interval
        let dueDateBefore = localBefore.dueDate
        let lapseCountBefore = localBefore.lapseCount
        let easeFactorBefore = localBefore.easeFactor

        // Remote row: LATER `updatedAt` (wins LWW) with DIFFERENT content
        // AND deliberately garbage scheduling fields — as if another
        // device graded this card differently (or the row is simply
        // stale relative to what a completed replay would derive).
        let remoteUpdatedAt = t1.addingTimeInterval(3600)
        var garbageState = FSRSState()
        garbageState = FSRSService.schedule(state: garbageState, grade: .again, now: remoteUpdatedAt)
        let scratchCard = Card(
            front: "REMOTE-front",
            back: "REMOTE-back",
            type: .vocabulary,
            fsrsState: garbageState,
            easeFactor: 1.3,
            interval: 999,
            dueDate: remoteUpdatedAt.addingTimeInterval(86400 * 999),
            lapseCount: 42,
            leechFlag: true
        )
        scratchCard.id = cardID
        scratchCard.updatedAt = remoteUpdatedAt
        var cardRow = try SyncPayloadBuilder.row(for: scratchCard)
        cardRow["server_updated_at"] = .string(SyncJSON.iso8601String(remoteUpdatedAt))

        let mockTransport = MockSyncPullTransport()
        mockTransport.enqueueRows([cardRow], forTable: "cards")
        // `review_logs` fails outright — simulating a crash or network
        // failure AFTER the `cards` page above has already been applied
        // and saved (`pullAndApply` saves per-page), but BEFORE
        // `replayFSRS` — which only runs once, after `review_logs`
        // finishes entirely (see `pullAll`) — ever gets a chance to run.
        let transport = TableFailingTransport(inner: mockTransport, failingTable: "review_logs")

        let pullActor = SyncPullActor(modelContainer: container)
        await #expect(throws: (any Error).self) {
            _ = try await pullActor.pullAll(transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token")
        }

        let localAfter = try #require(try fetchCard(id: cardID, in: container))

        // Content fields DID come from the remote win, as expected...
        #expect(localAfter.front == "REMOTE-front")
        #expect(localAfter.back == "REMOTE-back")

        // ...but the scheduling fields, which only a COMPLETED replay is
        // authoritative over (rule 2), were NOT overwritten by the remote
        // payload's garbage values — they are still exactly what the
        // local grade produced before this pull, because the replay that
        // was supposed to correct them never got to run.
        #expect(localAfter.fsrsState == fsrsStateBefore)
        #expect(localAfter.interval == intervalBefore)
        #expect(localAfter.dueDate == dueDateBefore)
        #expect(localAfter.lapseCount == lapseCountBefore)
        #expect(localAfter.easeFactor == easeFactorBefore)
        // In particular, definitely not the garbage remote values.
        #expect(localAfter.lapseCount != 42)
    }
}

// MARK: - TableFailingTransport

/// Wraps another `SyncPullTransport` (typically `MockSyncPullTransport`) and
/// makes every `fetchRows` call against ONE specific table fail, forwarding
/// every other table through unchanged. Used by
/// `remoteWinDoesNotOverwriteSchedulingAheadOfReplay` (IMPORTANT 4) to
/// simulate a network failure that lands squarely between two real steps of
/// one `pullAll` cycle — `cards` succeeding and being saved, `review_logs`
/// (and therefore the `replayFSRS` pass that only runs after it) never
/// getting to run — something neither `MockSyncPullTransport.setErrorToThrow`
/// (global, not table-scoped) nor `FakeSyncServer` (never fails) can express
/// on their own.
private struct TableFailingTransport: SyncPullTransport {
    let inner: any SyncPullTransport
    let failingTable: String

    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        if table == failingTable {
            throw SyncPullTransportError.requestFailed(status: 500, body: "TableFailingTransport: simulated failure for \(table)")
        }
        return try await inner.fetchRows(table: table, since: since, limit: limit, accessToken: accessToken)
    }
}

// MARK: - FakeSyncServer

/// A minimal shared fake server: implements BOTH `SyncDataTransport` (push)
/// and `SyncPullTransport` (pull) over ONE in-memory table store, so a push
/// from one simulated device becomes visible to a `fetchRows` call from
/// another — the one piece of infrastructure `MockSyncDataTransport` and
/// `MockSyncPullTransport` don't provide alone (each only records calls for
/// its own single role). Rows are keyed by `(table, id)`.
final class FakeSyncServer: SyncDataTransport, SyncPullTransport, @unchecked Sendable {

    private var tables: [String: [String: SyncRow]] = [:]
    private var clockTick: TimeInterval = 1_650_000_000
    private let lock = NSLock()

    /// One `server_updated_at` stamp for the WHOLE batch, not one per row —
    /// mirrors the real `touch_server_updated_at()` trigger's guarantee
    /// (verified in `SyncCursorPosition`'s doc comment): `now()` is the
    /// TRANSACTION clock, so every row one `upsert`/push call writes gets
    /// the EXACT SAME timestamp. The earlier version of this fake bumped
    /// `clockTick` per ROW, which could never actually produce a tie —
    /// making any "tie cluster" test run against it prove nothing about the
    /// real hazard. `clockTick` itself still only ever increases between
    /// separate `upsert` calls, so cross-batch ordering stays deterministic.
    func upsert(table: String, rows: [SyncRow], accessToken: String) async throws {
        guard !rows.isEmpty else { return }
        // `withLock` runs the whole critical section synchronously, so it's
        // safe to call from this `async` function — same pattern
        // `MockSyncDataTransport.upsert` / `MockSyncPullTransport.fetchRows`
        // use, for the same `lock()`/`unlock()`-are-`noasync` reason.
        lock.withLock {
            clockTick += 1
            let stamp = SyncJSON.iso8601String(Date(timeIntervalSince1970: clockTick))
            var stored = tables[table, default: [:]]
            for row in rows {
                guard case .string(let idString)? = row["id"] else { continue }
                var stamped = row
                stamped["server_updated_at"] = .string(stamp)
                stored[idString] = stamped
            }
            tables[table] = stored
        }
    }

    /// Implements the SAME keyset semantics as `PostgRESTPullTransport`'s
    /// `or=` filter — every row STRICTLY after `since` in
    /// `(server_updated_at, id)` order — over the in-memory store, rather
    /// than the old `since >= stamp` scalar comparison a single-`Date`
    /// cursor needed. `id` ties break on `uuidString` lexicographic order,
    /// matching `advanceCursor`'s tie-break and the `id.asc` secondary sort
    /// key this transport requests.
    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        lock.withLock {
            let decorated: [(row: SyncRow, date: Date, id: String)] = (tables[table] ?? [:]).values.compactMap { row in
                guard case .string(let raw)? = row["server_updated_at"],
                      let date = SyncJSON.dateFormatter.date(from: raw),
                      case .string(let idString)? = row["id"] else { return nil }
                return (row, date, idString)
            }
            let sorted = decorated.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
            guard let since,
                  let sinceDate = SyncJSON.dateFormatter.date(from: since.timestamp) else {
                return Array(sorted.prefix(limit).map(\.row))
            }
            let sinceID = since.id.uuidString
            let filtered = sorted.filter { candidate in
                if candidate.date != sinceDate { return candidate.date > sinceDate }
                return candidate.id > sinceID
            }
            return Array(filtered.prefix(limit).map(\.row))
        }
    }
}
