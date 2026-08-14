import Foundation

// MARK: - SyncCursorPreferences

/// `UserDefaults` key scheme for per-table pull cursors. New keys — this
/// lot's file perimeter is `Services/Sync/` only, so this lives here rather
/// than being folded into `CloudSyncPreferences`.
///
/// The cursor is deliberately NOT part of the SwiftData schema (no new
/// `@Model` property, no V5 migration). A V5 bump would need its own
/// process-isolated CI test step (see `LegacyStoreMigrationTests` in
/// `CLAUDE.md` — an open CoreData container with V1 snapshots poisons the
/// global entity↔class cache for the rest of the process). A per-table
/// `Date` in `UserDefaults` needs none of that.
public enum SyncCursorPreferences {

    /// Every table's key is `keyPrefix + table`, e.g.
    /// `"ikeru.cloudSync.cursor.cards"`.
    public static let keyPrefix = "ikeru.cloudSync.cursor."

    public static func key(forTable table: String) -> String {
        "\(keyPrefix)\(table)"
    }
}

// MARK: - SyncCursorStore

/// Per-table "last seen" pull cursor. Each cursor holds the maximum
/// `server_updated_at` (the server-clock column every synced table carries
/// — see the design spec §5.3 and the trigger verified in Supabase SQL)
/// already pulled and applied for that table.
///
/// This is a PULL-side concept only — unrelated to `SyncConsentStore`'s
/// push-attempt bookkeeping in `SyncPreferences.swift`.
public protocol SyncCursorStore: Sendable {

    /// The last cursor persisted for `table`, or `nil` if this table has
    /// never been pulled ("cold start" — the caller should treat this as
    /// "fetch everything", i.e. pass `since: nil` to `SyncPullTransport`).
    func cursor(forTable table: String) -> Date?

    /// Persists `date` as the new cursor for `table`.
    ///
    /// ⚠️ ORDERING CONTRACT — the one thing this type cannot enforce for
    /// you at the type level, so it's spelled out here: call this ONLY
    /// after the rows behind `date` have been durably applied to local
    /// storage. Advance-before-apply is the failure mode that loses rows
    /// forever — if the app crashes between "fetched from server" and
    /// "applied locally", an already-advanced cursor means those rows never
    /// get re-fetched, because the next pull's `since` filter starts past
    /// them. Advance-after-apply is safe under the same crash: the cursor
    /// stays where it was, the next pull re-fetches the same rows, and
    /// re-applying an already-applied row is a no-op (upsert by primary
    /// key) — see `SyncPullTransport`'s pagination contract for why the
    /// `since` filter is inclusive (`gte`, not `gt`) specifically to make
    /// that redelivery safe rather than lossy.
    ///
    /// Prefer calling the `advanceCursor(forTable:afterApplying:)`
    /// extension below instead of this method directly. It derives `date`
    /// FROM the rows you just applied, which structurally forces you to
    /// have those rows in hand — there's no bare
    /// `setCursor(Date(), forTable:)` shortcut in that call path that lets
    /// "advance" drift ahead of "apply" by accident.
    func setCursor(_ date: Date, forTable table: String)

    /// Clears every table's cursor, forcing the next pull for every table
    /// to behave like a cold start (`since: nil`). For sign-out / consent
    /// revocation / an explicit "force full resync" action — not called
    /// during normal sync.
    func resetAll()
}

extension SyncCursorStore {

    /// The sanctioned way to advance a table's cursor: pass the exact rows
    /// that have ALREADY been durably applied locally (typically the same
    /// array `SyncPullTransport.fetchRows` just returned, after your
    /// apply step succeeded). Computes the maximum `server_updated_at`
    /// among `appliedRows` and persists it via `setCursor`.
    ///
    /// If `appliedRows` is empty, or none of them carry a parseable
    /// `server_updated_at`, the cursor is left untouched and `nil` is
    /// returned — that's the correct no-op for an empty page, not an error.
    /// Otherwise returns the cursor value that was just persisted, so a
    /// caller running the pagination loop (see `SyncPullTransport`'s doc
    /// comment) can detect "a full `limit`-sized page came back but the
    /// cursor didn't move" — the signature of a tie cluster wider than
    /// `limit` (see that same doc comment) — rather than looping forever.
    ///
    /// A row missing `server_updated_at`, or carrying a value neither
    /// timestamp formatter below can parse, is ignored rather than
    /// aborting the whole batch over one malformed row.
    @discardableResult
    public func advanceCursor(forTable table: String, afterApplying appliedRows: [SyncRow]) -> Date? {
        let latest = appliedRows
            .compactMap { row -> Date? in
                guard case .string(let raw)? = row["server_updated_at"] else { return nil }
                return SyncCursorTimestampParsing.parse(raw)
            }
            .max()

        guard let latest else { return nil }
        setCursor(latest, forTable: table)
        return latest
    }
}

// MARK: - SyncCursorTimestampParsing

/// Parses the `server_updated_at` string PostgREST actually sends —
/// verified against the live Supabase project (`aiayzlarixlogcoyswna`) via
/// SQL on 2026-08-14, not assumed:
///
/// - `select to_json(now())` → `"2026-08-14T08:03:41.744605+00:00"` — a
///   6-digit microsecond fraction and a `+00:00` offset (never `Z`).
/// - `select to_json('...:00+00'::timestamptz)` (an exact-second value,
///   zero microseconds) → `"2026-08-14T10:00:00+00:00"` — Postgres DROPS
///   the fractional part entirely when it's zero, it does not emit
///   `.000000`.
///
/// `SyncJSON.dateFormatter` (`Services/Sync/SyncJSON.swift`, out of this
/// lot's file perimeter — not modified here) is configured with
/// `.withInternetDateTime, .withFractionalSeconds` and was built for the
/// `Z`-suffixed, always-fractional strings this codebase's own encoder
/// writes. Empirically (verified with a standalone Swift snippet against
/// the two real strings above) that formatter parses the WITH-fraction
/// case fine but returns `nil` on the WITHOUT-fraction case — exactly the
/// "landed on a whole second" row a real sync will eventually produce.
/// Silently failing to parse there would mean `advanceCursor` silently
/// drops that timestamp from its `max()`, which is usually harmless (a
/// same-page neighbor row supplies a comparable-or-later timestamp) but
/// becomes a real bug if EVERY row in a page happens to be fractionless —
/// the cursor would never advance and the pull loop would spin.
///
/// So this type owns a second, tolerant formatter as a fallback rather
/// than routing through `SyncJSON.dateFormatter` alone.
private enum SyncCursorTimestampParsing {

    /// Matches `SyncJSON.dateFormatter`'s configuration — tried first
    /// because it's the common case (most timestamps carry a non-zero
    /// fraction).
    ///
    /// `nonisolated(unsafe)`: same justification as
    /// `SyncJSON.dateFormatter` — a mutable reference type whose
    /// `formatOptions` is set once below and never mutated again; only the
    /// non-mutating `date(from:)` accessor is called afterward.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Fallback for the zero-fraction case Postgres renders without a
    /// decimal point at all.
    nonisolated(unsafe) private static let wholeSecond: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? wholeSecond.date(from: raw)
    }
}

// MARK: - UserDefaultsSyncCursorStore

/// Production implementation over `UserDefaults.standard` (or an injected
/// suite, matching `UserDefaultsSyncConsentStore`'s pattern in
/// `SyncPreferences.swift`).
public final class UserDefaultsSyncCursorStore: SyncCursorStore, @unchecked Sendable {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func cursor(forTable table: String) -> Date? {
        let key = SyncCursorPreferences.key(forTable: table)
        // `0` doubles as "key absent" and "epoch" — same sentinel
        // convention as `UserDefaultsSyncConsentStore.dateValue(forKey:)`.
        // A real server_updated_at at the Unix epoch is not a realistic
        // value for this app, so the collision is theoretical only.
        let stored = defaults.double(forKey: key)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    public func setCursor(_ date: Date, forTable table: String) {
        defaults.set(date.timeIntervalSince1970, forKey: SyncCursorPreferences.key(forTable: table))
    }

    public func resetAll() {
        // No fixed table list is threaded through this store (it's
        // deliberately table-agnostic — new synced tables don't need a
        // change here), so `resetAll` sweeps every key under the shared
        // prefix rather than iterating a hardcoded table array that could
        // drift out of sync with the 8 tables list in the design spec.
        let prefix = SyncCursorPreferences.keyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - MockSyncCursorStore

/// In-memory fake for tests — other agents' pull-engine tests can inject
/// this to assert on cursor progression without touching `UserDefaults`.
public final class MockSyncCursorStore: SyncCursorStore, @unchecked Sendable {

    private var cursors: [String: Date] = [:]
    private let lock = NSLock()

    public init(cursors: [String: Date] = [:]) {
        self.cursors = cursors
    }

    public func cursor(forTable table: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return cursors[table]
    }

    public func setCursor(_ date: Date, forTable table: String) {
        lock.lock(); defer { lock.unlock() }
        cursors[table] = date
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        cursors.removeAll()
    }
}
