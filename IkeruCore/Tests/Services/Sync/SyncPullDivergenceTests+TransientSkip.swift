import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Tests for the PERMANENT vs. TRANSIENT skip-reason distinction
/// (`RowApplyOutcome`) — split out of `SyncPullDivergenceTests+PoisonRow.swift`
/// purely to keep each file focused; shares that file's fixtures
/// (`makeContainer()`) and `@Suite("SyncPullDivergence")` annotation
/// (inherited — an extension doesn't need to repeat it).
///
/// 2026-08 lot-2 pull review, round 4 CRITICAL: `cards` stuck behind poison
/// rows of its own; a `review_logs` row references a card sitting BEHIND
/// them. Before this fix, the log was force-abandoned at cycle 3 — it was
/// never actually unrecoverable, only waiting on a parent that took longer
/// than 3 cycles to arrive. The fix routes an unresolved-foreign-key skip
/// through a SEPARATE counter (`SyncSkipTracker.recordTransientSkip`) with
/// a much wider threshold (`SyncPullActor.transientPoisonDropThreshold`,
/// 50) than a genuinely undecodable row's (`poisonDropThreshold`, 3) — see
/// `RowApplyOutcome`'s doc comment for the full story.
extension SyncPullDivergenceTests {

    @Test("Transient skip: a review_log whose card arrives late is not abandoned even past the permanent poisonDropThreshold, and applies once the card shows up")
    func transientForeignKeySkipSurvivesPastPoisonDropThresholdAndResolves() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        // A `review_logs` row referencing a card this device has never
        // pulled — the card only shows up several cycles later, below.
        let cardID = UUID()
        let logID = UUID()
        let logTimestamp = Date(timeIntervalSince1970: 1_701_000_000)
        let reviewLogRow: SyncRow = [
            "id": .uuid(logID),
            "card_id": .uuid(cardID),
            "occurred_at": .date(logTimestamp),
            "grade": .number(3), // Grade.good
            "answered_value": .null,
            "exercise_type": .null,
            "surface": .null,
            "payload": .object(["responseTimeMs": .number(1200)]),
            "updated_at": .date(logTimestamp),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(logTimestamp)),
        ]

        let pullActor = SyncPullActor(modelContainer: container)

        // `MockSyncPullTransport` drains a FIFO queue regardless of `since`
        // (see `poisonRowIsDroppedAfterThreeCyclesAndUnblocksLaterRows`'s
        // own comment on this), so the SAME row is re-enqueued each cycle —
        // exactly like a real `gt`/`eq` keyset filter re-fetching a row the
        // cursor never advanced past. `poisonDropThreshold` is 3 — this
        // loop runs ONE cycle PAST that on purpose, to prove the log is
        // still alive at the point the OLD (shared-counter) behavior would
        // have already dropped it.
        for cycle in 1...(SyncPullActor.poisonDropThreshold + 1) {
            transport.enqueueRows([reviewLogRow], forTable: "review_logs")
            let summary = try await pullActor.pullAll(
                transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
            )
            #expect(
                summary.permanentlyDroppedRowCounts["review_logs"] == 0,
                "cycle \(cycle): a transient (unresolved-FK) skip must never be dropped by the permanent 3-strike threshold"
            )
        }

        // Prove the MECHANISM, not just the absence of the symptom: the
        // PERMANENT counter must be untouched, and the TRANSIENT counter
        // must have accumulated exactly one strike per cycle above.
        #expect(skipTracker.currentCount(forTable: "review_logs") == nil)
        #expect(skipTracker.currentTransientCount(forTable: "review_logs") == SyncPullActor.poisonDropThreshold + 1)

        // The card FINALLY arrives.
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.id = cardID
        card.updatedAt = logTimestamp.addingTimeInterval(-1)
        var cardRow = try SyncPayloadBuilder.row(for: card)
        cardRow["server_updated_at"] = .string(SyncJSON.iso8601String(card.updatedAt))
        transport.enqueueRows([cardRow], forTable: "cards")
        transport.enqueueRows([reviewLogRow], forTable: "review_logs")

        let finalSummary = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
        )

        #expect(finalSummary.appliedRowCounts["review_logs"] == 1)
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.contains { $0.id == logID })

        // Self-healed: nothing left stuck once the row actually applied.
        #expect(skipTracker.currentTransientCount(forTable: "review_logs") == nil)
    }

    @Test("Transient skip: after transientPoisonDropThreshold consecutive cycles, a card that never arrives is still eventually abandoned, bounding the wait")
    func transientForeignKeySkipIsStillBoundedWhenTheParentNeverArrives() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = MockSyncPullTransport()

        let cardID = UUID()
        let logID = UUID()
        let logTimestamp = Date(timeIntervalSince1970: 1_701_100_000)
        let reviewLogRow: SyncRow = [
            "id": .uuid(logID),
            "card_id": .uuid(cardID),
            "occurred_at": .date(logTimestamp),
            "grade": .number(3),
            "answered_value": .null,
            "exercise_type": .null,
            "surface": .null,
            "payload": .object(["responseTimeMs": .number(800)]),
            "updated_at": .date(logTimestamp),
            "deleted_at": .null,
            "server_updated_at": .string(SyncJSON.iso8601String(logTimestamp)),
        ]

        let pullActor = SyncPullActor(modelContainer: container)

        // The referenced card is NEVER enqueued in this test — simulates a
        // parent that will truly never arrive (e.g. a data-integrity issue
        // server-side). `transientPoisonDropThreshold` cycles must still
        // eventually force-abandon the row — the bound this lot's Critical
        // A finding requires (see `RowApplyOutcome`'s and
        // `transientPoisonDropThreshold`'s doc comments).
        for _ in 1..<SyncPullActor.transientPoisonDropThreshold {
            transport.enqueueRows([reviewLogRow], forTable: "review_logs")
            let summary = try await pullActor.pullAll(
                transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
            )
            #expect(summary.permanentlyDroppedRowCounts["review_logs"] == 0)
        }

        transport.enqueueRows([reviewLogRow], forTable: "review_logs")
        let finalSummary = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token"
        )
        #expect(finalSummary.permanentlyDroppedRowCounts["review_logs"] == 1)
        #expect(cursorStore.cursor(forTable: "review_logs")?.id == logID)
    }
}
