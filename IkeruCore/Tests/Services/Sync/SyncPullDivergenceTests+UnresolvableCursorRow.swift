import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// GAP-03 (see `docs/known-gaps.md`): documents — does NOT change — the
/// behavior of a row whose `id` is readable but whose `server_updated_at`
/// (the CURSOR-only column `resolveStuckRow` needs to build a
/// `SyncCursorPosition`, distinct from the `updated_at` app-level LWW field
/// every `apply*Rows` function actually reads) cannot be turned into a
/// cursor position. `SyncPullActor+StuckRowResolution.swift`'s
/// `resolveStuckRow` requires `case .string(let stuckTimestamp)? =
/// stuckRow["server_updated_at"]` to force-abandon a row after
/// `poisonDropThreshold`/`transientPoisonDropThreshold` consecutive strikes
/// — a row that never satisfies that guard is retried on every future
/// cycle, forever, rather than ever being dropped. Split out of
/// `SyncPullDivergenceTests+PoisonRow.swift` (which covers the ORDINARY
/// poison-row path, where `server_updated_at` is always readable) purely to
/// keep this distinct, narrower invariant in its own file rather than
/// growing that one further past SwiftLint's `type_body_length` budget.
extension SyncPullDivergenceTests {

    // MARK: - GAP-03, scenario 1: head-of-page, `server_updated_at` KEY
    // ABSENT ENTIRELY — never dropped, no matter how many cycles

    @Test("GAP-03: a head-of-page row with no server_updated_at key at all is retried every cycle, never force-dropped, and never blocks other tables")
    func missingServerUpdatedAtKeyRetriesForeverWithoutDropping() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let poisonID = UUID()
        let poisonTimestamp = Date(timeIntervalSince1970: 1_701_100_000)
        // `payload: .object([:])` makes `CardPayload` decoding fail (missing
        // every required field) — a genuine, permanent skip reason,
        // independent of the `server_updated_at` question this test is
        // actually about. `id`/`updated_at` both decode fine (`common()`
        // never touches `server_updated_at`), matching GAP-03's "id valide"
        // wording precisely.
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            // No "server_updated_at" key at all.
        ]

        let pullActor = SyncPullActor(modelContainer: container)

        // `poisonDropThreshold` is 3 — run well past it (5 cycles) to prove
        // this isn't merely "not dropped yet."
        for cycle in 1...5 {
            transport.enqueueRows([poisonRow], forTable: "cards")
            // A good row on a DIFFERENT, later table each cycle — proves the
            // stuck `cards` table never blocks the rest of `pullOrder`.
            let entry = VocabularyEntry(word: "水", reading: "みず", meaning: "water")
            entry.updatedAt = poisonTimestamp.addingTimeInterval(Double(cycle))
            var entryRow = try SyncPayloadBuilder.row(for: entry)
            entryRow["server_updated_at"] = .string(SyncJSON.iso8601String(entry.updatedAt))
            transport.enqueueRows([entryRow], forTable: "vocabulary_entries")

            let summary = try await pullActor.pullAll(
                transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
            )

            #expect(summary.skippedRowCounts["cards"] == 1, "cycle \(cycle)")
            #expect(summary.permanentlyDroppedRowCounts["cards"] == 0, "cycle \(cycle)")
            #expect(cursorStore.cursor(forTable: "cards") == nil, "cycle \(cycle): cursor must never move")
            #expect(summary.appliedRowCounts["vocabulary_entries"] == 1, "cycle \(cycle): later table still ran")

            // The strike counter keeps climbing past the threshold — this is
            // NOT a case where the counter caps out or silently resets; the
            // ONLY reason the row survives is the missing `server_updated_at`
            // guard in `resolveStuckRow`, not an exhausted counter.
            #expect(skipTracker.currentCount(forTable: "cards") == cycle, "cycle \(cycle)")
        }
    }

    // MARK: - GAP-03, scenario 1b: `server_updated_at` present but NOT a
    // string (`.null`) — same outcome as fully absent

    @Test("GAP-03: a head-of-page row whose server_updated_at is present but non-string (.null) is likewise never dropped")
    func nonStringServerUpdatedAtRetriesForeverWithoutDropping() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let poisonID = UUID()
        let poisonTimestamp = Date(timeIntervalSince1970: 1_701_200_000)
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            "server_updated_at": .null,
        ]

        let pullActor = SyncPullActor(modelContainer: container)
        for cycle in 1...4 {
            transport.enqueueRows([poisonRow], forTable: "cards")
            let summary = try await pullActor.pullAll(
                transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
            )
            #expect(summary.permanentlyDroppedRowCounts["cards"] == 0, "cycle \(cycle)")
            #expect(cursorStore.cursor(forTable: "cards") == nil, "cycle \(cycle)")
        }
    }

    // MARK: - GAP-03, scenario 2: MID-page — the row is not at the head of
    // the whole table's backlog, only at the head of the UNAPPLIED suffix.
    // Not the case the known-gaps entry describes; behavior is the same,
    // but for a different reason worth locking down separately.

    @Test("GAP-03: a mid-page poisoned row with no server_updated_at blocks the cursor before it, but rows already applied behind it in the same page are NOT lost")
    func midPagePoisonedRowDoesNotLoseRowsAppliedBehindIt() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let t0 = Date(timeIntervalSince1970: 1_701_300_000)

        let goodA = Card(front: "一", back: "one", type: .vocabulary)
        goodA.updatedAt = t0
        var goodARow = try SyncPayloadBuilder.row(for: goodA)
        goodARow["server_updated_at"] = .string(SyncJSON.iso8601String(t0))

        let poisonID = UUID()
        let poisonTimestamp = t0.addingTimeInterval(1)
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            // No "server_updated_at" — same unreadable-cursor shape as
            // scenario 1, just NOT at index 0 this time.
        ]

        let goodB = Card(front: "二", back: "two", type: .vocabulary)
        goodB.updatedAt = t0.addingTimeInterval(2)
        var goodBRow = try SyncPayloadBuilder.row(for: goodB)
        goodBRow["server_updated_at"] = .string(SyncJSON.iso8601String(goodB.updatedAt))

        transport.enqueueRows([goodARow, poisonRow, goodBRow], forTable: "cards")

        let pullActor = SyncPullActor(modelContainer: container)
        let summary1 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )

        // Both goodA AND goodB were durably applied THIS cycle — `apply()`
        // processes the whole page regardless of where the safe cursor
        // prefix stops; only the CURSOR is held back, not the actual save.
        #expect(summary1.appliedRowCounts["cards"] == 2)
        #expect(summary1.skippedRowCounts["cards"] == 1)
        #expect(summary1.permanentlyDroppedRowCounts["cards"] == 0)

        let afterCycle1 = ModelContext(container)
        let cardsAfterCycle1 = try afterCycle1.fetch(FetchDescriptor<Card>())
        #expect(Set(cardsAfterCycle1.map(\.front)) == Set(["一", "二"]), "both good rows durably saved despite the cursor stalling before the poison row")

        // The cursor only advanced to goodA's own position — the safe
        // prefix stopped there, one row short of goodB.
        #expect(cursorStore.cursor(forTable: "cards")?.id == goodA.id)

        // Next cycle: the server (per the fake transport, which we drive
        // manually here) still holds the poison row and goodB, since the
        // cursor never advanced past either. Re-deliver exactly that —
        // mirrors what a real `since=<goodA position>` keyset fetch would
        // return.
        transport.enqueueRows([poisonRow, goodBRow], forTable: "cards")
        let summary2 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )

        // Redelivery, not loss: goodB re-applies as a safe no-op (same
        // `updatedAt`, so the LWW tie keeps the already-correct local
        // fields), the poison row is skipped again, and it is STILL not
        // dropped.
        #expect(summary2.appliedRowCounts["cards"] == 1)
        #expect(summary2.skippedRowCounts["cards"] == 1)
        #expect(summary2.permanentlyDroppedRowCounts["cards"] == 0)

        let afterCycle2 = ModelContext(container)
        let cardsAfterCycle2 = try afterCycle2.fetch(FetchDescriptor<Card>())
        // Still exactly 2 cards — goodB was NOT duplicated by the safe
        // redelivery.
        #expect(cardsAfterCycle2.count == 2)
        #expect(Set(cardsAfterCycle2.map(\.front)) == Set(["一", "二"]))
    }

    // MARK: - GAP-03, clarifying case: a SYNTACTICALLY string-shaped but
    // semantically garbage `server_updated_at` is a DIFFERENT case than
    // "absent" — `resolveStuckRow`'s guard only checks the `.string` case,
    // never parses it as a date, so a garbage string DOES satisfy the guard
    // and DOES get force-dropped. Worth locking down explicitly because the
    // known-gaps wording ("absent ou non parsable") reads as if both shapes
    // behave the same; they do not.

    @Test("GAP-03 (clarifying): unlike a missing/non-string server_updated_at, a syntactically string-shaped but unparseable value DOES get force-dropped after the threshold — the guard checks '.string', not 'valid ISO-8601'")
    func garbageButStringServerUpdatedAtIsStillForceDropped() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let poisonID = UUID()
        let poisonTimestamp = Date(timeIntervalSince1970: 1_701_400_000)
        let poisonRow: SyncRow = [
            "id": .uuid(poisonID),
            "profile_id": .null,
            "payload": .object([:]),
            "updated_at": .date(poisonTimestamp),
            "deleted_at": .null,
            // A string, but not a parseable ISO-8601 timestamp. `common()`
            // never reads this column, and `resolveStuckRow`'s guard is
            // `case .string(...)? = ...` — no date parsing at all — so this
            // shape is treated as "readable enough to abandon," unlike
            // scenarios 1/1b above.
            "server_updated_at": .string("not-a-timestamp"),
        ]

        let pullActor = SyncPullActor(modelContainer: container)
        var lastSummary: SyncPullActor.PullSummary?
        for _ in 0..<SyncPullActor.poisonDropThreshold {
            transport.enqueueRows([poisonRow], forTable: "cards")
            lastSummary = try await pullActor.pullAll(
                transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
            )
        }

        #expect(lastSummary?.permanentlyDroppedRowCounts["cards"] == 1)
        // The garbage string is what actually gets persisted as the cursor
        // — verbatim, per `SyncCursorPosition`'s contract. This is the
        // corollary risk worth having on record: a future real fetch using
        // this cursor would send `"not-a-timestamp"` to Postgres in the
        // `or=` filter, which cannot cast it to `timestamptz` — a request
        // failure, not silently wrong data, and only reachable at all under
        // the same assumed-can't-happen "abnormal server write" precondition
        // the known-gaps entry already names for the rest of GAP-03.
        #expect(cursorStore.cursor(forTable: "cards") == SyncCursorPosition(timestamp: "not-a-timestamp", id: poisonID))
    }
}
