import Testing
import Foundation
@testable import IkeruCore

@Suite("SyncCursorStore")
struct SyncCursorStoreTests {

    /// A throwaway `UserDefaults` suite per test — mirrors
    /// `SyncPreferencesTests.makeStore()` so this file leaves no residue on
    /// the machine running it and never touches `UserDefaults.standard`.
    private func makeStore() -> (store: UserDefaultsSyncCursorStore, defaults: UserDefaults) {
        let suiteName = "com.ikeru.tests.sync.cursor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (UserDefaultsSyncCursorStore(defaults: defaults), defaults)
    }

    private func position(_ epoch: TimeInterval, id: UUID = UUID()) -> SyncCursorPosition {
        SyncCursorPosition(timestamp: SyncJSON.iso8601String(Date(timeIntervalSince1970: epoch)), id: id)
    }

    // MARK: Cold start

    @Test("Cold start: no cursor ever set returns nil")
    func coldStartReturnsNil() {
        let (store, _) = makeStore()
        #expect(store.cursor(forTable: "cards") == nil)
    }

    @Test("Cold start: a fresh UserDefaults suite with unrelated keys still returns nil for cursors")
    func coldStartIgnoresUnrelatedKeys() {
        let (store, defaults) = makeStore()
        defaults.set(42.0, forKey: "some.other.namespace.value")
        #expect(store.cursor(forTable: "review_logs") == nil)
    }

    @Test("Cold start: a cursor written by the earlier single-Date design (no .ts/.id suffix) is unreadable, not a crash")
    func oldSingleDateCursorFormatReadsAsColdStart() {
        // Simulates a leftover value under the OLD key scheme
        // (`keyPrefix + table`, no `.ts`/`.id` suffix) — see
        // `SyncCursorPreferences`'s doc comment. Must read as cold start,
        // not throw or crash.
        let (store, defaults) = makeStore()
        defaults.set(1_700_000_000.0, forKey: "\(SyncCursorPreferences.keyPrefix)cards")
        #expect(store.cursor(forTable: "cards") == nil)
    }

    // MARK: Read/write round-trip

    @Test("setCursor / cursor round-trips a position for one table")
    func roundTripsSingleTable() {
        let (store, _) = makeStore()
        let id = UUID()
        let pos = position(1_700_000_000, id: id)
        store.setCursor(pos, forTable: "cards")

        #expect(store.cursor(forTable: "cards") == pos)
    }

    @Test("setCursor stores the timestamp string VERBATIM, not reconstructed through Date")
    func storesTimestampVerbatim() {
        // The exact shape verified against the live Supabase project — an
        // exact-second value with NO fractional part at all. Round-tripping
        // through `Date`/`ISO8601DateFormatter` (which always emits a
        // fraction) would silently mangle this.
        let (store, _) = makeStore()
        let id = UUID()
        let pos = SyncCursorPosition(timestamp: "2026-08-14T10:00:00+00:00", id: id)
        store.setCursor(pos, forTable: "cards")

        #expect(store.cursor(forTable: "cards")?.timestamp == "2026-08-14T10:00:00+00:00")
    }

    @Test("setCursor persists across store instances sharing the same defaults suite")
    func persistsAcrossInstances() {
        let (store, defaults) = makeStore()
        let pos = position(1_700_000_000)
        store.setCursor(pos, forTable: "cards")

        let reloaded = UserDefaultsSyncCursorStore(defaults: defaults)
        #expect(reloaded.cursor(forTable: "cards") == pos)
    }

    @Test("setCursor overwrites a previous value for the same table")
    func overwritesPreviousValue() {
        let (store, _) = makeStore()
        store.setCursor(position(1_000), forTable: "cards")
        let newer = position(2_000)
        store.setCursor(newer, forTable: "cards")

        #expect(store.cursor(forTable: "cards") == newer)
    }

    // MARK: Table isolation

    @Test("Cursors for different tables are isolated from each other")
    func tablesAreIsolated() {
        let (store, _) = makeStore()
        let cardsPos = position(1_000)
        let logsPos = position(2_000)

        store.setCursor(cardsPos, forTable: "cards")
        store.setCursor(logsPos, forTable: "review_logs")

        #expect(store.cursor(forTable: "cards") == cardsPos)
        #expect(store.cursor(forTable: "review_logs") == logsPos)
    }

    @Test("Setting one table's cursor never creates a cursor for another table")
    func settingOneTableDoesNotLeakToAnother() {
        let (store, _) = makeStore()
        store.setCursor(position(1_000), forTable: "cards")
        #expect(store.cursor(forTable: "vocabulary_entries") == nil)
    }

    // MARK: resetAll

    @Test("resetAll clears every table's cursor")
    func resetAllClearsEveryTable() {
        let (store, _) = makeStore()
        store.setCursor(position(1_000), forTable: "cards")
        store.setCursor(position(1_000), forTable: "review_logs")
        store.setCursor(position(1_000), forTable: "vocabulary_entries")

        store.resetAll()

        #expect(store.cursor(forTable: "cards") == nil)
        #expect(store.cursor(forTable: "review_logs") == nil)
        #expect(store.cursor(forTable: "vocabulary_entries") == nil)
    }

    @Test("resetAll on an already-empty store is a harmless no-op")
    func resetAllOnEmptyStoreIsNoOp() {
        let (store, _) = makeStore()
        store.resetAll()
        #expect(store.cursor(forTable: "cards") == nil)
    }

    @Test("resetAll does not touch unrelated UserDefaults keys in the same suite")
    func resetAllLeavesUnrelatedKeysAlone() {
        let (store, defaults) = makeStore()
        defaults.set("keep-me", forKey: "some.other.namespace.value")
        store.setCursor(position(1_000), forTable: "cards")

        store.resetAll()

        #expect(defaults.string(forKey: "some.other.namespace.value") == "keep-me")
    }

    // MARK: advanceCursor(forTable:afterApplying:) — the safe-ordering helper

    @Test("advanceCursor sets the cursor to the row with the max (server_updated_at, id) among applied rows")
    func advanceCursorTakesMaxOfAppliedRows() {
        let (store, _) = makeStore()
        let older = SyncJSON.iso8601String(Date(timeIntervalSince1970: 1_000))
        let newer = SyncJSON.iso8601String(Date(timeIntervalSince1970: 2_000))
        let idA = UUID()
        let idB = UUID()
        let rows: [SyncRow] = [
            ["id": .uuid(idA), "server_updated_at": .string(older)],
            ["id": .uuid(idB), "server_updated_at": .string(newer)],
        ]

        store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(store.cursor(forTable: "cards") == SyncCursorPosition(timestamp: newer, id: idB))
    }

    @Test("advanceCursor with an empty applied-rows array leaves the cursor untouched")
    func advanceCursorWithEmptyRowsIsNoOp() {
        let (store, _) = makeStore()
        let existing = position(1_500)
        store.setCursor(existing, forTable: "cards")

        store.advanceCursor(forTable: "cards", afterApplying: [])

        #expect(store.cursor(forTable: "cards") == existing)
    }

    @Test("advanceCursor ignores rows with a missing or unparseable server_updated_at")
    func advanceCursorIgnoresMalformedRows() {
        let (store, _) = makeStore()
        let validTS = SyncJSON.iso8601String(Date(timeIntervalSince1970: 3_000))
        let validID = UUID()
        let rows: [SyncRow] = [
            ["id": .uuid(UUID())],
            ["id": .uuid(UUID()), "server_updated_at": .string("not-a-date")],
            ["id": .uuid(validID), "server_updated_at": .string(validTS)],
        ]

        store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(store.cursor(forTable: "cards") == SyncCursorPosition(timestamp: validTS, id: validID))
    }

    @Test("advanceCursor ignores rows with a missing or unparseable id, even when the timestamp is fine")
    func advanceCursorIgnoresRowsWithBadID() {
        let (store, _) = makeStore()
        let validTS = SyncJSON.iso8601String(Date(timeIntervalSince1970: 3_000))
        let validID = UUID()
        let laterTS = SyncJSON.iso8601String(Date(timeIntervalSince1970: 4_000))
        let rows: [SyncRow] = [
            ["id": .string("not-a-uuid"), "server_updated_at": .string(laterTS)],
            ["id": .uuid(validID), "server_updated_at": .string(validTS)],
        ]

        store.advanceCursor(forTable: "cards", afterApplying: rows)

        // The later-timestamped row is excluded (unparseable id), so the
        // only valid candidate wins even though it's chronologically
        // earlier.
        #expect(store.cursor(forTable: "cards") == SyncCursorPosition(timestamp: validTS, id: validID))
    }

    @Test("advanceCursor where every row is malformed leaves the cursor untouched")
    func advanceCursorAllMalformedIsNoOp() {
        let (store, _) = makeStore()
        let rows: [SyncRow] = [
            ["id": .uuid(UUID())],
            ["id": .uuid(UUID()), "server_updated_at": .string("not-a-date")],
        ]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == nil)
        #expect(store.cursor(forTable: "cards") == nil)
    }

    @Test("advanceCursor returns the cursor it just persisted")
    func advanceCursorReturnsPersistedValue() {
        let (store, _) = makeStore()
        let raw = SyncJSON.iso8601String(Date(timeIntervalSince1970: 5_000))
        let id = UUID()
        let rows: [SyncRow] = [["id": .uuid(id), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == SyncCursorPosition(timestamp: raw, id: id))
    }

    @Test("advanceCursor breaks a timestamp tie by the greater id, matching the id.asc secondary sort key")
    func advanceCursorBreaksTiesByID() {
        let (store, _) = makeStore()
        let tied = SyncJSON.iso8601String(Date(timeIntervalSince1970: 6_000))
        // Deliberately construct two ids where lexicographic order is known.
        let lower = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higher = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let rows: [SyncRow] = [
            ["id": .uuid(higher), "server_updated_at": .string(tied)],
            ["id": .uuid(lower), "server_updated_at": .string(tied)],
        ]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == SyncCursorPosition(timestamp: tied, id: higher))
    }

    // MARK: Real PostgREST timestamp shapes (verified against live Supabase project 2026-08-14)

    @Test(
        "advanceCursor parses the real PostgREST timestamptz shape (6-digit microseconds, +00:00 offset)",
        arguments: [
            // `select to_json(now())` on the live project returned exactly
            // this shape — 6-digit fraction, colon-bearing UTC offset
            // rather than `Z`.
            "2026-08-14T08:03:41.744605+00:00"
        ]
    )
    func advanceCursorParsesRealFractionalShape(raw: String) {
        let (store, _) = makeStore()
        let id = UUID()
        let rows: [SyncRow] = [["id": .uuid(id), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == SyncCursorPosition(timestamp: raw, id: id))
    }

    @Test(
        "advanceCursor parses the real PostgREST zero-fraction shape (no decimal point at all)",
        arguments: [
            // `select to_json(x::timestamptz)` for an exact-second value on
            // the live project dropped the fraction entirely rather than
            // rendering `.000000` — this is the shape that
            // `SyncJSON.dateFormatter` alone (`.withFractionalSeconds`)
            // fails to parse; `advanceCursor` must not silently drop it.
            "2026-08-14T10:00:00+00:00"
        ]
    )
    func advanceCursorParsesRealWholeSecondShape(raw: String) {
        let (store, _) = makeStore()
        let id = UUID()
        let rows: [SyncRow] = [["id": .uuid(id), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == SyncCursorPosition(timestamp: raw, id: id))
    }

    @Test("advanceCursor: a whole-second row still wins max() against an earlier fractional row")
    func advanceCursorWholeSecondRowCanBeTheMax() {
        let (store, _) = makeStore()
        let laterID = UUID()
        let rows: [SyncRow] = [
            ["id": .uuid(UUID()), "server_updated_at": .string("2026-08-14T08:03:41.744605+00:00")],
            ["id": .uuid(laterID), "server_updated_at": .string("2026-08-14T10:00:00+00:00")],
        ]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == SyncCursorPosition(timestamp: "2026-08-14T10:00:00+00:00", id: laterID))
    }

    // MARK: MockSyncCursorStore parity

    @Test("MockSyncCursorStore round-trips like the UserDefaults-backed store")
    func mockStoreRoundTrips() {
        let store = MockSyncCursorStore()
        let pos = position(1_700_000_000)
        #expect(store.cursor(forTable: "cards") == nil)

        store.setCursor(pos, forTable: "cards")
        #expect(store.cursor(forTable: "cards") == pos)
        #expect(store.cursor(forTable: "review_logs") == nil)

        store.resetAll()
        #expect(store.cursor(forTable: "cards") == nil)
    }
}
