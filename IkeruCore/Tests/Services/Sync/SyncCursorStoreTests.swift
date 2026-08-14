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

    // MARK: Read/write round-trip

    @Test("setCursor / cursor round-trips a date for one table")
    func roundTripsSingleTable() {
        let (store, _) = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.setCursor(date, forTable: "cards")

        let read = store.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(date)) < 0.001)
    }

    @Test("setCursor persists across store instances sharing the same defaults suite")
    func persistsAcrossInstances() {
        let (store, defaults) = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.setCursor(date, forTable: "cards")

        let reloaded = UserDefaultsSyncCursorStore(defaults: defaults)
        let read = reloaded.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(date)) < 0.001)
    }

    @Test("setCursor overwrites a previous value for the same table")
    func overwritesPreviousValue() {
        let (store, _) = makeStore()
        store.setCursor(Date(timeIntervalSince1970: 1_000), forTable: "cards")
        store.setCursor(Date(timeIntervalSince1970: 2_000), forTable: "cards")

        let read = store.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(Date(timeIntervalSince1970: 2_000))) < 0.001)
    }

    // MARK: Table isolation

    @Test("Cursors for different tables are isolated from each other")
    func tablesAreIsolated() {
        let (store, _) = makeStore()
        let cardsDate = Date(timeIntervalSince1970: 1_000)
        let logsDate = Date(timeIntervalSince1970: 2_000)

        store.setCursor(cardsDate, forTable: "cards")
        store.setCursor(logsDate, forTable: "review_logs")

        #expect(abs((store.cursor(forTable: "cards") ?? .distantPast).timeIntervalSince(cardsDate)) < 0.001)
        #expect(abs((store.cursor(forTable: "review_logs") ?? .distantPast).timeIntervalSince(logsDate)) < 0.001)
    }

    @Test("Setting one table's cursor never creates a cursor for another table")
    func settingOneTableDoesNotLeakToAnother() {
        let (store, _) = makeStore()
        store.setCursor(Date(), forTable: "cards")
        #expect(store.cursor(forTable: "vocabulary_entries") == nil)
    }

    // MARK: resetAll

    @Test("resetAll clears every table's cursor")
    func resetAllClearsEveryTable() {
        let (store, _) = makeStore()
        store.setCursor(Date(), forTable: "cards")
        store.setCursor(Date(), forTable: "review_logs")
        store.setCursor(Date(), forTable: "vocabulary_entries")

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
        store.setCursor(Date(), forTable: "cards")

        store.resetAll()

        #expect(defaults.string(forKey: "some.other.namespace.value") == "keep-me")
    }

    // MARK: advanceCursor(forTable:afterApplying:) — the safe-ordering helper

    @Test("advanceCursor sets the cursor to the max server_updated_at among applied rows")
    func advanceCursorTakesMaxOfAppliedRows() {
        let (store, _) = makeStore()
        let older = SyncJSON.iso8601String(Date(timeIntervalSince1970: 1_000))
        let newer = SyncJSON.iso8601String(Date(timeIntervalSince1970: 2_000))
        let rows: [SyncRow] = [
            ["id": .string("a"), "server_updated_at": .string(older)],
            ["id": .string("b"), "server_updated_at": .string(newer)]
        ]

        store.advanceCursor(forTable: "cards", afterApplying: rows)

        let read = store.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(Date(timeIntervalSince1970: 2_000))) < 0.001)
    }

    @Test("advanceCursor with an empty applied-rows array leaves the cursor untouched")
    func advanceCursorWithEmptyRowsIsNoOp() {
        let (store, _) = makeStore()
        let existing = Date(timeIntervalSince1970: 1_500)
        store.setCursor(existing, forTable: "cards")

        store.advanceCursor(forTable: "cards", afterApplying: [])

        let read = store.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(existing)) < 0.001)
    }

    @Test("advanceCursor ignores rows with a missing or unparseable server_updated_at")
    func advanceCursorIgnoresMalformedRows() {
        let (store, _) = makeStore()
        let valid = SyncJSON.iso8601String(Date(timeIntervalSince1970: 3_000))
        let rows: [SyncRow] = [
            ["id": .string("missing-field")],
            ["id": .string("bad-format"), "server_updated_at": .string("not-a-date")],
            ["id": .string("valid"), "server_updated_at": .string(valid)]
        ]

        store.advanceCursor(forTable: "cards", afterApplying: rows)

        let read = store.cursor(forTable: "cards")
        #expect(abs((read ?? .distantPast).timeIntervalSince(Date(timeIntervalSince1970: 3_000))) < 0.001)
    }

    @Test("advanceCursor where every row is malformed leaves the cursor untouched")
    func advanceCursorAllMalformedIsNoOp() {
        let (store, _) = makeStore()
        let rows: [SyncRow] = [
            ["id": .string("missing-field")],
            ["id": .string("bad-format"), "server_updated_at": .string("not-a-date")]
        ]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result == nil)
        #expect(store.cursor(forTable: "cards") == nil)
    }

    @Test("advanceCursor returns the cursor it just persisted")
    func advanceCursorReturnsPersistedValue() {
        let (store, _) = makeStore()
        let raw = SyncJSON.iso8601String(Date(timeIntervalSince1970: 5_000))
        let rows: [SyncRow] = [["id": .string("a"), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result != nil)
        #expect(abs((result ?? .distantPast).timeIntervalSince(Date(timeIntervalSince1970: 5_000))) < 0.001)
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
        let rows: [SyncRow] = [["id": .string("a"), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result != nil)
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
        let rows: [SyncRow] = [["id": .string("a"), "server_updated_at": .string(raw)]]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        #expect(result != nil)
    }

    @Test("advanceCursor: a whole-second row still wins max() against an earlier fractional row")
    func advanceCursorWholeSecondRowCanBeTheMax() {
        let (store, _) = makeStore()
        let rows: [SyncRow] = [
            ["id": .string("earlier"), "server_updated_at": .string("2026-08-14T08:03:41.744605+00:00")],
            ["id": .string("later-whole-second"), "server_updated_at": .string("2026-08-14T10:00:00+00:00")]
        ]

        let result = store.advanceCursor(forTable: "cards", afterApplying: rows)

        let expected = ISO8601DateFormatter().date(from: "2026-08-14T10:00:00Z")
        #expect(result != nil)
        #expect(abs((result ?? .distantPast).timeIntervalSince(expected ?? .distantPast)) < 0.001)
    }

    // MARK: MockSyncCursorStore parity

    @Test("MockSyncCursorStore round-trips like the UserDefaults-backed store")
    func mockStoreRoundTrips() {
        let store = MockSyncCursorStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(store.cursor(forTable: "cards") == nil)

        store.setCursor(date, forTable: "cards")
        #expect(store.cursor(forTable: "cards") == date)
        #expect(store.cursor(forTable: "review_logs") == nil)

        store.resetAll()
        #expect(store.cursor(forTable: "cards") == nil)
    }
}
