import Foundation

// MARK: - SyncCursorPosition

/// A keyset pagination cursor: the `server_updated_at` timestamp AND `id` of
/// the last row a table's pull has durably applied (or deliberately skipped
/// past — see `SyncPullActor`'s poison-row handling).
///
/// This is a **composite** cursor, not the single `Date` this lot shipped
/// with first. The scalar `Date` design could not simultaneously guarantee
/// "never lose a row" and "always make forward progress": `server_updated_at`
/// is stamped by `touch_server_updated_at()` with `now()` — the TRANSACTION
/// timestamp, not `clock_timestamp()` (verified via `pg_get_functiondef`
/// against the live `aiayzlarixlogcoyswna` project, same function on all 8
/// tables) — so one bulk upsert stamps EVERY row it touches with the exact
/// same timestamp. A `Date`-only cursor cannot tell "already delivered this
/// tied row" from "haven't delivered it yet" once a tie cluster spans more
/// than one page, AND cannot skip past a single poison row without skipping
/// its entire tie cluster (potentially hundreds of rows) along with it. `id`
/// as a secondary key makes every row's position in the ordering unique, so
/// both problems disappear together.
///
/// ⚠️ **`timestamp` MUST be stored VERBATIM — the exact string PostgREST
/// returned — never reconstructed from a `Date`.** Verified against the live
/// project on 2026-08-14: `select to_json(now())` returns
/// `"2026-08-14T09:42:22.968936+00:00"` — 6-digit microseconds, a
/// colon-bearing `+00:00` offset (never `Z`) — and Postgres DROPS the
/// fractional part entirely for an exact-second value
/// (`"2026-08-14T10:00:00+00:00"`, no decimal point at all, not `.000000`).
/// Parsing that string into a `Date` and re-serializing it (through
/// `ISO8601DateFormatter`, which emits `Z` and always includes a fraction)
/// produces a DIFFERENT string than what the server sent. The keyset filter
/// this cursor drives (`PostgRESTPullTransport.keysetFilter`) has an `eq`
/// branch that compares this string against the column server-side — a
/// round-tripped string silently fails to match the boundary row anymore,
/// which either re-delivers it forever (harmless but wasteful) or, worse,
/// can miswalk a tie cluster. Keeping the raw string sidesteps the whole
/// class of bug rather than chasing every shape Postgres might render.
public struct SyncCursorPosition: Sendable, Equatable, Codable {

    /// The exact `server_updated_at` string as PostgREST returned it — see
    /// the type doc comment for why this is never reconstructed from a
    /// `Date`.
    public let timestamp: String

    /// The row's `id` — the tie-break that makes this cursor's position in
    /// the ordering unique even among rows sharing `timestamp`.
    public let id: UUID

    public init(timestamp: String, id: UUID) {
        self.timestamp = timestamp
        self.id = id
    }
}

// MARK: - SyncCursorPreferences

/// `UserDefaults` key scheme for per-table pull cursors. New keys — this
/// lot's file perimeter is `Services/Sync/` only, so this lives here rather
/// than being folded into `CloudSyncPreferences`.
///
/// The cursor is deliberately NOT part of the SwiftData schema (no new
/// `@Model` property, no V5 migration). A V5 bump would need its own
/// process-isolated CI test step (see `LegacyStoreMigrationTests` in
/// `CLAUDE.md` — an open CoreData container with V1 snapshots poisons the
/// global entity↔class cache for the rest of the process). Two `String`
/// values in `UserDefaults` need none of that.
///
/// Each table's cursor now needs TWO keys, not one — `timestamp` and `id`
/// (see `SyncCursorPosition`). A table whose cursor was written by the
/// earlier, single-`Date` design left a value under the OLD single key
/// (`keyPrefix + table`, no suffix); that key is simply orphaned data under
/// this scheme (never read by `timestampKey`/`idKey`, still swept by
/// `resetAll()`'s prefix scan) — reading a table that only has the old key
/// correctly returns `nil` (cold start, rule 1 fires). No migration was
/// written for this because lot 2 never shipped with the old cursor format;
/// nothing in production ever wrote it.
public enum SyncCursorPreferences {

    /// Every table's keys share `keyPrefix + table`, e.g.
    /// `"ikeru.cloudSync.cursor.cards.ts"` / `"...cards.id"`.
    public static let keyPrefix = "ikeru.cloudSync.cursor."

    public static func timestampKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).ts"
    }

    public static func idKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).id"
    }
}

// MARK: - SyncCursorStore

/// Per-table "last seen" pull cursor — see `SyncCursorPosition` for why this
/// is a `(timestamp, id)` pair rather than a single `Date`.
///
/// This is a PULL-side concept only — unrelated to `SyncConsentStore`'s
/// push-attempt bookkeeping in `SyncPreferences.swift`.
public protocol SyncCursorStore: Sendable {

    /// The last cursor persisted for `table`, or `nil` if this table has
    /// never been pulled ("cold start" — the caller should treat this as
    /// "fetch everything", i.e. pass `since: nil` to `SyncPullTransport`).
    func cursor(forTable table: String) -> SyncCursorPosition?

    /// Persists `position` as the new cursor for `table`.
    ///
    /// ⚠️ ORDERING CONTRACT — the one thing this type cannot enforce for
    /// you at the type level, so it's spelled out here: call this ONLY
    /// after the rows behind `position` have been durably applied to local
    /// storage — OR after `SyncPullActor` has decided to deliberately
    /// abandon the row at `position` as unrecoverable (its poison-row
    /// policy; see that type's doc comment). Advance-before-apply is the
    /// failure mode that loses rows forever — if the app crashes between
    /// "fetched from server" and "applied locally", an already-advanced
    /// cursor means those rows never get re-fetched, because the next
    /// pull's keyset filter starts strictly past them. Advance-after-apply
    /// is safe under the same crash: the cursor stays where it was, the
    /// next pull re-fetches the same rows, and re-applying an
    /// already-applied row is a no-op (upsert by primary key) — see
    /// `SyncPullTransport`'s pagination contract.
    ///
    /// Prefer calling the `advanceCursor(forTable:afterApplying:)`
    /// extension below instead of this method directly for the "just
    /// applied" case. It derives `position` FROM the rows you just
    /// applied, which structurally forces you to have those rows in hand —
    /// there's no bare `setCursor(_, forTable:)` shortcut in that call path
    /// that lets "advance" drift ahead of "apply" by accident. Call
    /// `setCursor` directly only for the deliberate-abandonment case, where
    /// there is no "applied row" to derive a position from by definition.
    func setCursor(_ position: SyncCursorPosition, forTable table: String)

    /// Clears every table's cursor, forcing the next pull for every table
    /// to behave like a cold start (`since: nil`). For sign-out / consent
    /// revocation / an explicit "force full resync" action — not called
    /// during normal sync.
    ///
    /// Any implementation of this protocol used alongside a `SyncSkipTracker`
    /// (`SyncSkipTracker.swift`) must be paired with that type's own
    /// `resetAll()` at every call site — a stale strike count surviving a
    /// cursor reset would let a brand-new account's row inherit strikes from
    /// a completely unrelated previous account (see that protocol's doc
    /// comment).
    func resetAll()
}

extension SyncCursorStore {

    /// The sanctioned way to advance a table's cursor: pass the exact rows
    /// that have ALREADY been durably applied locally (typically the same
    /// array `SyncPullTransport.fetchRows` just returned, after your
    /// apply step succeeded). Computes the row with the maximum
    /// `(server_updated_at, id)` position among `appliedRows` and persists
    /// it via `setCursor`.
    ///
    /// If `appliedRows` is empty, or none of them carry a parseable
    /// `server_updated_at` AND a parseable `id`, the cursor is left
    /// untouched and `nil` is returned — that's the correct no-op for an
    /// empty page, not an error. A row with a parseable `server_updated_at`
    /// but an unparseable/missing `id` (or vice versa) is excluded from the
    /// max computation the same way a malformed timestamp always was —
    /// this cursor cannot represent half a position.
    @discardableResult
    public func advanceCursor(forTable table: String, afterApplying appliedRows: [SyncRow]) -> SyncCursorPosition? {
        let candidates: [(position: SyncCursorPosition, date: Date)] = appliedRows.compactMap { row in
            guard case .string(let raw)? = row["server_updated_at"],
                  let date = SyncCursorTimestampParsing.parse(raw),
                  case .string(let idString)? = row["id"],
                  let id = UUID(uuidString: idString) else { return nil }
            return (SyncCursorPosition(timestamp: raw, id: id), date)
        }

        // Tie-break by `id` string order — matches the `id.asc` secondary
        // sort key `SyncPullTransport` requests server-side, and Postgres's
        // own uuid byte ordering (uppercase-hex `UUID.uuidString` compares
        // the same way lexicographically, since dashes sit at fixed
        // positions in every candidate).
        guard let winner = candidates.max(by: { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.position.id.uuidString < rhs.position.id.uuidString
        }) else { return nil }

        setCursor(winner.position, forTable: table)
        return winner.position
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
/// This is used ONLY to compare two timestamp strings chronologically
/// (`advanceCursor`'s `max()`) — never to reconstruct a string to send back
/// to the server. The verbatim string itself (not a `Date` derived from it)
/// is what `SyncCursorPosition.timestamp` stores and what
/// `PostgRESTPullTransport` sends — see that type's doc comment.
///
/// `SyncJSON.dateFormatter` (`Services/Sync/SyncJSON.swift`, out of this
/// lot's file perimeter — not modified here) is configured with
/// `.withInternetDateTime, .withFractionalSeconds` and was built for the
/// `Z`-suffixed, always-fractional strings this codebase's own encoder
/// writes. Empirically (verified with a standalone Swift snippet against
/// the two real strings above) that formatter parses the WITH-fraction
/// case fine but returns `nil` on the WITHOUT-fraction case — exactly the
/// "landed on a whole second" row a real sync will eventually produce. So
/// this type owns a second, tolerant formatter as a fallback rather than
/// routing through `SyncJSON.dateFormatter` alone.
enum SyncCursorTimestampParsing {

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

    public func cursor(forTable table: String) -> SyncCursorPosition? {
        guard let timestamp = defaults.string(forKey: SyncCursorPreferences.timestampKey(forTable: table)),
              !timestamp.isEmpty,
              let idString = defaults.string(forKey: SyncCursorPreferences.idKey(forTable: table)),
              let id = UUID(uuidString: idString) else {
            return nil
        }
        return SyncCursorPosition(timestamp: timestamp, id: id)
    }

    public func setCursor(_ position: SyncCursorPosition, forTable table: String) {
        defaults.set(position.timestamp, forKey: SyncCursorPreferences.timestampKey(forTable: table))
        defaults.set(position.id.uuidString, forKey: SyncCursorPreferences.idKey(forTable: table))
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

    private var cursors: [String: SyncCursorPosition] = [:]
    private let lock = NSLock()

    public init(cursors: [String: SyncCursorPosition] = [:]) {
        self.cursors = cursors
    }

    public func cursor(forTable table: String) -> SyncCursorPosition? {
        lock.lock(); defer { lock.unlock() }
        return cursors[table]
    }

    public func setCursor(_ position: SyncCursorPosition, forTable table: String) {
        lock.lock(); defer { lock.unlock() }
        cursors[table] = position
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        cursors.removeAll()
    }
}
