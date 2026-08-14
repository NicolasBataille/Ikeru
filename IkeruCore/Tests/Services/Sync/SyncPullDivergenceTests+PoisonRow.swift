import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// The tie-cluster / poison-row tests for `SyncPullDivergenceTests` — split
/// out of that file purely to stay under SwiftLint's `type_body_length`
/// (600 lines) budget, same reasoning as `SyncPullActor+StandaloneTables.swift`.
/// There is no behavioral reason these couldn't live in the main file; they
/// share its fixtures (`makeContainer()`, bumped from `private` to internal
/// so this cross-file extension can reach it) and its `@Suite("SyncPullDivergence")`
/// annotation (inherited — an extension doesn't need to repeat it).
extension SyncPullDivergenceTests {

    // MARK: - Test 7, REWRITTEN for the composite cursor (was CRITIQUE 3):
    // a tie cluster wider than one page is now walked to completion, not
    // aborted
    //
    // ⚠️ Behavioral inversion, stated explicitly: the ORIGINAL version of
    // this test (`fullyTiedFullPageThrowsInsteadOfLooping`, see git history)
    // asserted the OPPOSITE outcome — that a fully-tied full page THROWS
    // `cursorStalledOnFullPage`. That was correct for the single-`Date`
    // cursor this lot shipped with first, which genuinely could not
    // distinguish two rows sharing a timestamp and would spin forever
    // without the throw. The composite `(server_updated_at, id)` cursor
    // (`SyncCursorPosition`) removes the hazard structurally — every row in
    // a tie cluster has a unique `(timestamp, id)` position, so pagination
    // walks straight through it. Keeping the old assertion would mean
    // asserting a REGRESSION back to the exact bug point 1 of this lot's
    // remediation exists to close; the invariant worth testing is no longer
    // "does it throw" but "does a tie cluster wider than one page still
    // deliver every row." Real end-to-end validation for the underlying
    // wire format lives in `SyncCursorStoreTests`'s "real PostgREST
    // timestamp shapes" tests and in the curl walk documented on
    // `PostgRESTPullTransport`.
    @Test("A tie cluster wider than one page (3 rows, pageSize 1) is fully traversed by the composite keyset cursor")
    func tiedClusterWiderThanOnePageIsFullyTraversed() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // Three rows sharing the EXACT same `server_updated_at` — the shape
        // a single bulk push transaction produces (Postgres `now()` stamps
        // every row in one transaction identically — see
        // `SyncPullTransport`'s doc comment). `pageSize: 1` below makes
        // EVERY row its own "full" page, the narrowest possible window for
        // this hazard.
        let tiedTimestamp = Date(timeIntervalSince1970: 1_700_400_000)
        let tiedRaw = SyncJSON.iso8601String(tiedTimestamp)

        let entries = [
            VocabularyEntry(word: "一", reading: "いち", meaning: "one"),
            VocabularyEntry(word: "二", reading: "に", meaning: "two"),
            VocabularyEntry(word: "三", reading: "さん", meaning: "three"),
        ]
        for entry in entries { entry.updatedAt = tiedTimestamp }
        let rows = try entries.map { entry -> SyncRow in
            var row = try SyncPayloadBuilder.row(for: entry)
            row["server_updated_at"] = .string(tiedRaw)
            return row
        }
        for row in rows {
            transport.enqueueRows([row], forTable: "vocabulary_entries")
        }

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(
            transport: transport,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: "token",
            pageSize: 1
        )

        // All 3 tied rows applied in ONE `pullAll` call — no throw, no
        // stall, no manual second cycle needed.
        #expect(summary.appliedRowCounts["vocabulary_entries"] == 3)
        #expect(summary.skippedRowCounts["vocabulary_entries"] == 0)

        let context = ModelContext(container)
        let stored = try context.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(Set(stored.map(\.word)) == Set(["一", "二", "三"]))

        // 4 `fetchRows` calls: one per tied row, plus the final empty page
        // that signals "caught up".
        #expect(transport.calls(forTable: "vocabulary_entries").count == 4)
    }

    // MARK: - Ex æquo: the SAME scenario against `FakeSyncServer`'s real
    // keyset filter (not a hand-rolled page queue) — the case a single-`Date`
    // cursor could never correctly paginate, validated end-to-end against
    // the exact `or=` syntax verified live on 2026-08-14 (see
    // `PostgRESTPullTransport`'s doc comment).

    @Test("Ex æquo: a 3-row tie cluster from ONE upsert transaction is fully traversed with pageSize 1 against the real keyset filter")
    func exAequoTieClusterAgainstRealKeysetFilter() async throws {
        let server = FakeSyncServer()
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()

        // ONE `upsert` call = ONE transaction = ONE `server_updated_at`
        // stamp for all 3 rows, exactly like `touch_server_updated_at()`'s
        // `now()` — see `FakeSyncServer.upsert`'s doc comment.
        let entries = [
            VocabularyEntry(word: "一", reading: "いち", meaning: "one"),
            VocabularyEntry(word: "二", reading: "に", meaning: "two"),
            VocabularyEntry(word: "三", reading: "さん", meaning: "three"),
        ]
        let rows = try entries.map { try SyncPayloadBuilder.row(for: $0) }
        try await server.upsert(table: "vocabulary_entries", rows: rows, accessToken: "token")

        let pullActor = SyncPullActor(modelContainer: container)
        let summary = try await pullActor.pullAll(
            transport: server,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: "token",
            pageSize: 1
        )

        #expect(summary.appliedRowCounts["vocabulary_entries"] == 3)
        #expect(summary.skippedRowCounts["vocabulary_entries"] == 0)

        let context = ModelContext(container)
        let stored = try context.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(Set(stored.map(\.word)) == Set(["一", "二", "三"]))
    }

    // MARK: - Critical A, "page pleine": a poison row at the head of a FULL
    // page must not kill the rest of the cycle

    @Test("Critical A: a poison row at the head of a FULL page does not abort pullAll — tables after it in pullOrder still run")
    func poisonRowOnFullPageDoesNotAbortSubsequentTables() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // `cards`: a FULL page (pageSize 2) with the poison row FIRST —
        // permanently undecodable (empty payload, exactly like Test 8's
        // `badCardRow`), never a transient "hasn't arrived yet" case.
        let poisonID = UUID()
        let poisonTimestamp = Date(timeIntervalSince1970: 1_700_700_000)
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(poisonTimestamp)),
        ]
        let validCard = Card(front: "犬", back: "dog", type: .vocabulary)
        validCard.updatedAt = poisonTimestamp.addingTimeInterval(1)
        var validCardRow = try SyncPayloadBuilder.row(for: validCard)
        validCardRow["server_updated_at"] = .string(SyncJSON.iso8601String(validCard.updatedAt))
        transport.enqueueRows([poisonRow, validCardRow], forTable: "cards")

        // `vocabulary_entries` is pulled AFTER `cards` in `pullOrder` — a
        // valid row here proves the cycle actually reached it, not just
        // that its dictionary key happens to exist.
        let entry = VocabularyEntry(word: "水", reading: "みず", meaning: "water")
        entry.updatedAt = poisonTimestamp.addingTimeInterval(2)
        var entryRow = try SyncPayloadBuilder.row(for: entry)
        entryRow["server_updated_at"] = .string(SyncJSON.iso8601String(entry.updatedAt))
        transport.enqueueRows([entryRow], forTable: "vocabulary_entries")

        let pullActor = SyncPullActor(modelContainer: container)
        // Must NOT throw — the whole point of this test. Before the
        // per-table catch in `pullAll` (Critical A's fix), a poison row on
        // a full page threw `cursorStalledOnFullPage` straight out of
        // `pullAll`, and NOTHING after `cards` in `pullOrder` — including
        // `vocabulary_entries` — was ever queried that cycle.
        let summary = try await pullActor.pullAll(
            transport: transport,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: "token",
            pageSize: 2
        )

        #expect(summary.appliedRowCounts["cards"] == 1)
        #expect(summary.skippedRowCounts["cards"] == 1)
        // Only 1 strike so far — nowhere near the 3-cycle drop threshold —
        // so nothing was permanently abandoned yet, just deferred.
        #expect(summary.permanentlyDroppedRowCounts["cards"] == 0)
        // The table AFTER `cards` in `pullOrder` still ran and applied its
        // row — proving the stall didn't take the rest of the cycle down.
        #expect(summary.appliedRowCounts["vocabulary_entries"] == 1)
    }

    // MARK: - Critical A, "page courte": after 3 cycles on the SAME poison
    // row, it is dropped, and the rows behind it finally apply

    @Test("Critical A: after 3 consecutive cycles on the same poison row, it is dropped and rows behind it apply")
    func poisonRowIsDroppedAfterThreeCyclesAndUnblocksLaterRows() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let poisonID = UUID()
        let poisonTimestamp = Date(timeIntervalSince1970: 1_700_800_000)
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(poisonTimestamp)),
        ]
        // Enqueue the SAME poison row 3 times — one per `pullAll` cycle
        // below. `MockSyncPullTransport` drains a FIFO queue regardless of
        // `since` (it doesn't model "the server keeps re-returning an
        // undelivered row"), so re-enqueuing per cycle is what makes each
        // call see it again, exactly like a real `gt`/`eq` keyset filter
        // re-fetching a row the cursor never advanced past.
        for _ in 0..<3 {
            transport.enqueueRows([poisonRow], forTable: "cards")
        }

        let pullActor = SyncPullActor(modelContainer: container)

        // `pageSize: 10` with single-row pages throughout — deliberately
        // "page courte" (`page.count < pageSize`) for every cycle in this
        // test, the OTHER half of Critical A from the full-page test above:
        // the drop-after-3 policy is independent of full vs. short.
        let cycle1 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )
        #expect(cycle1.permanentlyDroppedRowCounts["cards"] == 0)
        #expect(cursorStore.cursor(forTable: "cards") == nil)

        let cycle2 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )
        #expect(cycle2.permanentlyDroppedRowCounts["cards"] == 0)
        #expect(cursorStore.cursor(forTable: "cards") == nil)

        let cycle3 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )
        // The 3rd consecutive cycle on the SAME row id: dropped, visibly.
        #expect(cycle3.permanentlyDroppedRowCounts["cards"] == 1)
        #expect(cursorStore.cursor(forTable: "cards")?.id == poisonID)

        // Now enqueue a row that was "stuck behind" the poison row —
        // before the drop, nothing after it in the ordering could ever be
        // reached because the cursor never advanced past the poison row's
        // own position.
        let unblockedCard = Card(front: "犬", back: "dog", type: .vocabulary)
        unblockedCard.updatedAt = poisonTimestamp.addingTimeInterval(1)
        var unblockedRow = try SyncPayloadBuilder.row(for: unblockedCard)
        unblockedRow["server_updated_at"] = .string(SyncJSON.iso8601String(unblockedCard.updatedAt))
        transport.enqueueRows([unblockedRow], forTable: "cards")

        let cycle4 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )
        #expect(cycle4.appliedRowCounts["cards"] == 1)
    }

    // MARK: - Critical A, residual anomaly guard: even when
    // `cursorStalledOnFullPage` genuinely fires, `pullAll`'s per-table catch
    // — not the poison-row policy above — is what keeps the cycle alive

    @Test("Critical A: the residual anomaly guard (full page, every row applied, but no row's server_updated_at parses) still does not abort pullAll")
    func residualAnomalyGuardOnFullPageDoesNotAbortSubsequentTables() async throws {
        // This is a DIFFERENT path than the poison-row tests above: every
        // row here APPLIES successfully (unlike a poison row, which never
        // does) — the anomaly is that `server_updated_at`, a column only
        // `advanceCursor` reads, is missing from both rows, so the cursor
        // genuinely cannot move despite full apply-side progress. This is
        // exactly the residual case `SyncPullActorError.cursorStalledOnFullPage`'s
        // doc comment describes as "should not occur in practice" but keeps
        // a guard for — and it's the one case that still reaches `pullAll`'s
        // `catch let error as SyncPullActorError`, proving that catch (not
        // the 3-strikes poison policy, which never even runs here since
        // nothing was skipped) is what keeps this table's trouble from
        // taking `pullOrder`'s later tables down with it.
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let cardA = Card(front: "一", back: "one", type: .vocabulary)
        let cardB = Card(front: "二", back: "two", type: .vocabulary)
        cardA.updatedAt = Date(timeIntervalSince1970: 1_700_900_000)
        cardB.updatedAt = Date(timeIntervalSince1970: 1_700_900_001)
        var rowA = try SyncPayloadBuilder.row(for: cardA)
        var rowB = try SyncPayloadBuilder.row(for: cardB)
        // Deliberately no `server_updated_at` key on either row — `apply()`
        // never reads it (only `updated_at`, present above), so both still
        // decode and apply fine; only `advanceCursor` is starved.
        rowA["server_updated_at"] = nil
        rowB["server_updated_at"] = nil
        transport.enqueueRows([rowA, rowB], forTable: "cards")

        let entry = VocabularyEntry(word: "水", reading: "みず", meaning: "water")
        entry.updatedAt = Date(timeIntervalSince1970: 1_700_900_002)
        var entryRow = try SyncPayloadBuilder.row(for: entry)
        entryRow["server_updated_at"] = .string(SyncJSON.iso8601String(entry.updatedAt))
        transport.enqueueRows([entryRow], forTable: "vocabulary_entries")

        let pullActor = SyncPullActor(modelContainer: container)
        // Must NOT throw.
        let summary = try await pullActor.pullAll(
            transport: transport,
            cursorStore: cursorStore,
            skipTracker: skipTracker,
            accessToken: "token",
            pageSize: 2
        )

        // Both cards applied (the anomaly is cursor-side, not apply-side).
        #expect(summary.appliedRowCounts["cards"] == 2)
        // `vocabulary_entries`, pulled AFTER `cards`, still ran.
        #expect(summary.appliedRowCounts["vocabulary_entries"] == 1)
    }

}
