import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// GAP-05 (see `docs/known-gaps.md`): re-verifies — DOES NOT "fix" — the
/// analysis that `ISO8601DateFormatter` (used by both
/// `SyncCursorTimestampParsing.parse`, which `advanceCursor` uses to pick
/// the max `(server_updated_at, id)` candidate within one page, and
/// `SyncPullActor`'s own row-level date parsing) truncates a real
/// Postgres `timestamptz` string's 6-digit microsecond fraction down to
/// millisecond precision. Two rows from the SAME millisecond but different
/// microseconds therefore parse to the IDENTICAL Swift `Date`.
///
/// Empirically re-confirmed for this task (not just re-asserted from the
/// prior write-up) with a standalone `ISO8601DateFormatter` probe:
/// `"...968936+00:00"` and `"...968999+00:00"` both parse to
/// `...968` — the SAME `Date`, `timeIntervalSince1970` difference `0.0`.
///
/// The analysis this file locks down: because `SyncCursorPosition.timestamp`
/// is always the VERBATIM string of a row that was ACTUALLY delivered and
/// applied — never a value reconstructed from the truncated `Date` — a
/// millisecond-tie mis-pick by `advanceCursor`'s `max()` (which, once two
/// rows' `Date`s compare equal, falls back to comparing `id` strings, NOT
/// true microsecond order) can only ever cause a SAFE REDELIVERY of the
/// other tied row on a later cycle, never its loss. The real Postgres
/// keyset filter compares the raw string server-side, at full microsecond
/// precision, so it does not share the client's truncation blind spot.
extension SyncPullDivergenceTests {

    // MARK: - The premise, re-verified directly against the type this app
    // actually calls

    @Test("GAP-05 premise: SyncCursorTimestampParsing.parse truncates two same-millisecond, different-microsecond strings to the identical Date")
    func cursorTimestampParsingTruncatesToMillisecond() {
        let earlier = "2026-08-14T09:42:22.968936+00:00"
        let later = "2026-08-14T09:42:22.968999+00:00"

        let parsedEarlier = SyncCursorTimestampParsing.parse(earlier)
        let parsedLater = SyncCursorTimestampParsing.parse(later)

        #expect(parsedEarlier != nil)
        #expect(parsedEarlier == parsedLater, "the premise the rest of GAP-05's analysis depends on")
    }

    // MARK: - advanceCursor: the stored cursor is always a REAL row's own
    // verbatim string, even when the millisecond-truncated tie-break picks
    // the chronologically EARLIER of two same-millisecond rows

    @Test("GAP-05: advanceCursor's millisecond-tie mispick still stores an ACTUAL row's own verbatim (timestamp, id) — never a synthesized value")
    func advanceCursorTieBreakStoresARealRowsVerbatimPosition() {
        let cursorStore = MockSyncCursorStore()

        // Same millisecond, different microseconds — `earlierTrue`'s
        // microsecond digits are numerically smaller (936 < 999), so it is
        // the chronologically EARLIER row in real Postgres precision, even
        // though both truncate to the identical Swift `Date`.
        let earlierTrue = "2026-08-14T09:42:22.968936+00:00"
        let laterTrue = "2026-08-14T09:42:22.968999+00:00"

        // Deliberately engineer the WORST case: give the chronologically
        // EARLIER row the LEXICOGRAPHICALLY GREATER id, so the `Date`-tied
        // max()'s id-string tie-break picks IT — the "wrong" (older) row —
        // over the truly-later one. Matches `advanceCursorBreaksTiesByID`'s
        // established id ordering (`FFFFFFFF...` sorts after `00000000...`).
        let idOfEarlierTrue = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let idOfLaterTrue = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let rows: [SyncRow] = [
            ["id": .uuid(idOfEarlierTrue), "server_updated_at": .string(earlierTrue)],
            ["id": .uuid(idOfLaterTrue), "server_updated_at": .string(laterTrue)],
        ]

        let result = cursorStore.advanceCursor(forTable: "vocabulary_entries", afterApplying: rows)

        // The tie-break DID pick the chronologically earlier row — this is
        // the hazard GAP-05 describes, reproduced deliberately.
        #expect(result?.id == idOfEarlierTrue)
        // But its `timestamp` is EXACTLY that row's own raw string — not a
        // re-formatted `Date`, not a blend of the two. This is what makes
        // the mispick safe: the next fetch's `or=` filter still compares
        // this exact string server-side, at full precision, against the
        // truly-later row's own untouched value.
        #expect(result?.timestamp == earlierTrue)
    }

    // MARK: - End-to-end: the mispick above causes a safe REDELIVERY of the
    // truly-later row, never a loss — verified against a transport that
    // filters with the SAME full-precision STRING comparison Postgres
    // performs server-side (unlike `FakeSyncServer`, which re-parses
    // `since.timestamp` into a `Date` for its own filtering and would
    // therefore share the very truncation blind spot this test needs to
    // rule out, proving nothing about the real hazard).

    @Test("GAP-05: a millisecond-tie mispick within one page causes a safe, idempotent redelivery on the next cycle — nothing is lost")
    func millisecondTieMispickRedeliversSafelyWithoutLoss() async throws {
        let container = try makeContainer()
        let cursorStore = MockSyncCursorStore()
        let skipTracker = MockSyncSkipTracker()
        let transport = FullPrecisionStringFilterTransport()

        let earlierTrue = "2026-08-14T09:42:22.968936+00:00"
        let laterTrue = "2026-08-14T09:42:22.968999+00:00"

        let rowA = VocabularyEntry(word: "一", reading: "いち", meaning: "one")
        rowA.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        var syncRowA = try SyncPayloadBuilder.row(for: rowA)
        syncRowA["server_updated_at"] = .string(earlierTrue)

        let rowB = VocabularyEntry(word: "二", reading: "に", meaning: "two")
        rowB.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        var syncRowB = try SyncPayloadBuilder.row(for: rowB)
        syncRowB["server_updated_at"] = .string(laterTrue)

        // Real Postgres order (`server_updated_at.asc, id.asc`) puts A
        // (chronologically earlier at full precision) first, regardless of
        // which id is lexicographically greater.
        transport.seed([syncRowA, syncRowB], forTable: "vocabulary_entries")

        // `pageSize: 10`, deliberately larger than the 2 seeded rows: an
        // UNDER-full page (`page.count < pageSize`) is the realistic shape —
        // this is "everything currently on the server," not an artificial
        // full page that would make the pagination loop itself immediately
        // re-fetch and self-heal the mispick within the SAME `pullAll` call
        // (which it does when `page.count == pageSize`, an easier case that
        // doesn't exercise the risk this test is actually about — a
        // mispicked cursor surviving PAST the cycle that made it).
        let pullActor = SyncPullActor(modelContainer: container)
        let summary1 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )

        #expect(summary1.appliedRowCounts["vocabulary_entries"] == 2)

        // The millisecond-tie mispick: the cursor lands on rowA (the
        // chronologically EARLIER row), not rowB, exactly as
        // `advanceCursorTieBreakStoresARealRowsVerbatimPosition` predicts.
        #expect(cursorStore.cursor(forTable: "vocabulary_entries")?.id == rowA.id)
        #expect(cursorStore.cursor(forTable: "vocabulary_entries")?.timestamp == earlierTrue)

        // Second cycle: with a cursor genuinely BEHIND rowB in full
        // precision, the (production-faithful) transport redelivers rowB —
        // the safe, expected consequence — and does NOT redeliver rowA
        // (correctly excluded: the cursor sits exactly at rowA's own
        // position).
        let summary2 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )

        #expect(summary2.appliedRowCounts["vocabulary_entries"] == 1)
        #expect(transport.lastFetchedIDs(forTable: "vocabulary_entries") == [rowB.id])

        // Nothing lost, nothing duplicated: both entries present exactly
        // once, both with their correct content, after the redelivery.
        let context = ModelContext(container)
        let stored = try context.fetch(FetchDescriptor<VocabularyEntry>())
        #expect(stored.count == 2)
        #expect(Set(stored.map(\.word)) == Set(["一", "二"]))

        // The cursor now correctly reflects rowB's own position — a THIRD
        // cycle would fetch nothing new.
        #expect(cursorStore.cursor(forTable: "vocabulary_entries")?.id == rowB.id)
        let summary3 = try await pullActor.pullAll(
            transport: transport, cursorStore: cursorStore, skipTracker: skipTracker, accessToken: "token", pageSize: 10
        )
        #expect(summary3.appliedRowCounts["vocabulary_entries"] == 0)
    }
}

// MARK: - FullPrecisionStringFilterTransport

/// A `SyncPullTransport` fake that filters `since` with the SAME semantics
/// `PostgRESTPullTransport.keysetFilter` sends to a real `timestamptz`
/// column — full microsecond precision, via `or=(gt, and(eq, id.gt))` —
/// implemented here as a raw ISO-8601 STRING comparison rather than a
/// re-parsed Swift `Date`.
///
/// This is valid specifically because every `server_updated_at` this app
/// ever produces or reads is a FIXED-WIDTH, zero-padded ISO-8601 string with
/// an identical `+00:00` offset (verified against the live project — see
/// `SyncCursorPosition`'s doc comment): every field occupies the same
/// character positions in every string, so lexicographic string ordering
/// and chronological ordering agree exactly. `FakeSyncServer` (used by every
/// OTHER divergence test in this suite) does not use this technique — it
/// re-parses `since.timestamp` into a `Date` for its own filtering, which
/// would silently share the exact millisecond-truncation blind spot GAP-05
/// is about, making it unable to prove anything about the real hazard this
/// file locks down. A dedicated, narrower fake is worth the duplication.
final class FullPrecisionStringFilterTransport: SyncPullTransport, @unchecked Sendable {

    private var rowsByTable: [String: [SyncRow]] = [:]
    private var fetchedIDsByTable: [String: [UUID]] = [:]
    private let lock = NSLock()

    func seed(_ rows: [SyncRow], forTable table: String) {
        lock.lock(); defer { lock.unlock() }
        rowsByTable[table, default: []].append(contentsOf: rows)
    }

    /// The ids returned by the MOST RECENT `fetchRows` call against `table`
    /// — lets a test assert precisely what got (re)delivered on a given
    /// cycle, not just how many rows.
    func lastFetchedIDs(forTable table: String) -> [UUID] {
        lock.withLock { fetchedIDsByTable[table] ?? [] }
    }

    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        // `withLock` runs the whole critical section synchronously, so it's
        // safe to call from this `async` function — same pattern
        // `MockSyncPullTransport.fetchRows` uses, for the same
        // `lock()`/`unlock()`-are-`noasync` reason.
        lock.withLock {
            let all = rowsByTable[table] ?? []
            let sorted = all.sorted { lhs, rhs in
                guard case .string(let lts)? = lhs["server_updated_at"],
                      case .string(let lid)? = lhs["id"],
                      case .string(let rts)? = rhs["server_updated_at"],
                      case .string(let rid)? = rhs["id"] else { return false }
                if lts != rts { return lts < rts }
                return lid < rid
            }

            let candidates: [SyncRow]
            if let since {
                candidates = sorted.filter { row in
                    guard case .string(let ts)? = row["server_updated_at"],
                          case .string(let idString)? = row["id"] else { return false }
                    if ts != since.timestamp { return ts > since.timestamp }
                    return idString > since.id.uuidString
                }
            } else {
                candidates = sorted
            }

            let page = Array(candidates.prefix(limit))
            let ids: [UUID] = page.compactMap { row in
                guard case .string(let idString)? = row["id"] else { return nil }
                return UUID(uuidString: idString)
            }
            fetchedIDsByTable[table] = ids
            return page
        }
    }
}
