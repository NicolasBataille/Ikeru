import Foundation

// MARK: - SyncPullTransport

/// Abstraction over a PostgREST bulk-read call — the pull-side counterpart
/// to `SyncDataTransport.upsert`. Protocol boundary so a future pull engine
/// (`SyncModelActor` / `CloudSyncCoordinator`) is testable with
/// `MockSyncPullTransport` below, without touching the network.
///
/// ## Pagination contract — keyset, not offset
/// `fetchRows` returns AT MOST `limit` rows, ordered ascending by
/// `(server_updated_at, id)`. The caller owns the pagination loop:
///
/// 1. Call `fetchRows(table:since:limit:accessToken:)` with `since` set to
///    `SyncCursorStore.cursor(forTable:)` (`nil` on a cold start).
/// 2. Apply the returned rows locally.
/// 3. Advance the cursor from those SAME rows —
///    `SyncCursorStore.advanceCursor(forTable:afterApplying:)` — never
///    before step 2 succeeds (see that method's doc comment).
/// 4. If the response had exactly `limit` rows, there may be more: repeat
///    from step 1 with the now-advanced cursor.
/// 5. Stop once a response comes back with FEWER than `limit` rows
///    (including zero) — that's the "caught up" signal.
///
/// A learner with a year of history can have thousands of `review_logs`
/// rows; without this loop a single page silently truncates their pull.
///
/// ## Why a composite `(timestamp, id)` cursor, not a single `Date`
/// Every synced table's `server_updated_at` trigger stamps rows with
/// `now()` (the TRANSACTION timestamp, not `clock_timestamp()` — verified
/// via `pg_get_functiondef` against the live `touch_server_updated_at()`
/// function on 2026-08-14, same function on all 8 tables). One bulk
/// upsert — e.g. one `SyncModelActor` push flushing hundreds of dirty
/// `review_logs` rows in a single `POST` — therefore gives ALL of those
/// rows the exact same `server_updated_at`; tie clusters wider than one
/// page are routine, not an edge case. A single `Date` cursor cannot tell
/// "already delivered this tied row" from "haven't delivered it yet" once
/// a tie cluster spans more than one page, and — the sharper problem —
/// cannot skip a single unrecoverable ("poison") row without skipping its
/// ENTIRE tie cluster along with it, which could mean hundreds of
/// legitimately-applicable rows silently going unretried forever. Adding
/// `id` as a secondary key (see `SyncCursorPosition`) gives every row a
/// unique position in the ordering, which is what makes both a tie cluster
/// wider than a page AND a surgical single-row skip (see
/// `SyncPullActor`'s poison-row handling) actually work.
public protocol SyncPullTransport: Sendable {

    /// Fetches up to `limit` rows from `table`, ordered ascending by
    /// `(server_updated_at, id)`.
    ///
    /// - `since: nil` means "no lower bound" — a full first pull, used only
    ///   when `SyncCursorStore.cursor(forTable:)` is `nil` for this table.
    /// - `since` non-nil returns every row STRICTLY AFTER `since` in
    ///   `(server_updated_at, id)` order — see
    ///   `PostgRESTPullTransport.keysetFilter` for the exact filter this
    ///   compiles to. Unlike the earlier `Date`-only design's `gte`
    ///   boundary, this is exclusive: the row AT `since` was already
    ///   applied (or deliberately abandoned) by definition of the cursor
    ///   having been advanced past it, so it must not be re-delivered.
    func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow]
}

public enum SyncPullTransportError: Error, Sendable, Equatable {
    case invalidResponse
    case requestFailed(status: Int, body: String)
}

// MARK: - PostgRESTPullTransport

/// Production transport, built on `URLSession` — same no-external-SDK
/// stance as `PostgRESTSyncTransport` (`SyncDataTransport.swift`), and
/// deliberately mirrors its header/error-handling style.
///
/// Request shape — validated end-to-end against the live Supabase project
/// (`aiayzlarixlogcoyswna`) on 2026-08-14 via `curl` with `limit=1`, walking
/// a real 3-row tie cluster row by row (HTTP 200 at every step, correct
/// order, empty page at the end):
///
/// ```
/// GET {baseURL}/rest/v1/{table}
///   ?select=*
///   &or=(server_updated_at.gt.{TS},and(server_updated_at.eq.{TS},id.gt.{ID}))
///   &order=server_updated_at.asc,id.asc
///   &limit={N}
/// ```
///
/// `{TS}` is `since.timestamp` used VERBATIM (see `SyncCursorPosition`'s
/// doc comment for why) and `{ID}` is `since.id`. The `or=` filter is
/// omitted entirely when `since` is `nil` (a cold-start full pull).
///
/// `apikey: <publishableKey>` + `Authorization: Bearer <accessToken>` — same
/// pairing as the push transport; RLS scopes every row this returns to
/// `auth.uid() = user_id`, so no other learner's rows can leak through this
/// call regardless of `table`.
public struct PostgRESTPullTransport: SyncPullTransport {

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(
        baseURL: URL = SupabaseConfig.projectURL,
        apiKey: String = SupabaseConfig.publishableKey,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SyncPullTransportError.invalidResponse
        }

        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "server_updated_at.asc,id.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let since {
            queryItems.append(URLQueryItem(name: "or", value: Self.keysetFilter(after: since)))
        }
        components.queryItems = queryItems

        // `URLComponents`' own percent-encoding leaves `+` unescaped — it is
        // a legal RFC 3986 query character — but PostgREST's query parser
        // (like most, following the `application/x-www-form-urlencoded`
        // convention) decodes an unescaped `+` as a space. Every real
        // `server_updated_at` this app ever filters on carries a `+00:00`
        // UTC offset (verified against the live project, never `Z` — see
        // `SyncCursorPosition`'s doc comment), so leaving it unescaped would
        // silently turn `...T09:42:22.968936+00:00` into
        // `...T09:42:22.968936 00:00` on the wire — a timestamp Postgres
        // cannot parse, corrupting the one filter this pagination scheme
        // depends on. Escaping every literal `+` left over in the
        // already-percent-encoded query string is the standard fix for this
        // well-known `URLComponents` gap.
        if let encodedQuery = components.percentEncodedQuery {
            components.percentEncodedQuery = encodedQuery.replacingOccurrences(of: "+", with: "%2B")
        }

        guard let url = components.url else {
            throw SyncPullTransportError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncPullTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw SyncPullTransportError.requestFailed(status: http.statusCode, body: bodyString)
        }

        let decoded = try SyncJSON.decoder.decode([JSONValue].self, from: data)
        return try decoded.map { value in
            guard case .object(let row) = value else {
                throw SyncPullTransportError.invalidResponse
            }
            return row
        }
    }

    /// Builds the `or=` filter value implementing keyset pagination past
    /// `position` — see the type doc comment for the validated request
    /// shape this is one piece of.
    static func keysetFilter(after position: SyncCursorPosition) -> String {
        let ts = position.timestamp
        let id = position.id.uuidString
        return "(server_updated_at.gt.\(ts),and(server_updated_at.eq.\(ts),id.gt.\(id)))"
    }
}

// MARK: - MockSyncPullTransport

/// In-memory fake for tests — mirrors `MockSyncDataTransport`'s shape
/// (recorded calls + programmable responses) so other agents can test a
/// pull engine without a network dependency.
public final class MockSyncPullTransport: SyncPullTransport, @unchecked Sendable {

    public struct Call: Sendable, Equatable {
        public let table: String
        public let since: SyncCursorPosition?
        public let limit: Int
        public let accessToken: String
    }

    public private(set) var calls: [Call] = []

    private var queuedPagesByTable: [String: [[SyncRow]]] = [:]
    private var errorToThrow: Error?
    private let lock = NSLock()

    public init() {}

    /// Schedules one page of rows to be returned by the NEXT `fetchRows`
    /// call against `table`. Call this multiple times per table to queue
    /// successive pages (FIFO) and exercise the pagination loop described
    /// on `SyncPullTransport` — e.g. two full-`limit` pages followed by a
    /// short final page. Once a table's queue is exhausted, `fetchRows`
    /// returns `[]` for it (mirrors "caught up").
    public func enqueueRows(_ rows: [SyncRow], forTable table: String) {
        lock.lock(); defer { lock.unlock() }
        queuedPagesByTable[table, default: []].append(rows)
    }

    /// Makes every subsequent `fetchRows` call throw `error` (until cleared
    /// with `nil`), regardless of table or queued pages.
    public func setErrorToThrow(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        errorToThrow = error
    }

    public func fetchRows(table: String, since: SyncCursorPosition?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        // `withLock` runs the whole critical section synchronously, so it's
        // safe to call from this `async` function — same rationale as
        // `MockSyncDataTransport.upsert`.
        let outcome: (rows: [SyncRow], error: Error?) = lock.withLock {
            calls.append(Call(table: table, since: since, limit: limit, accessToken: accessToken))
            if let errorToThrow {
                return ([], errorToThrow)
            }
            guard var queue = queuedPagesByTable[table], !queue.isEmpty else {
                return ([], nil)
            }
            let next = queue.removeFirst()
            queuedPagesByTable[table] = queue
            return (next, nil)
        }
        if let error = outcome.error { throw error }
        return outcome.rows
    }

    /// All recorded calls against `table`, in call order.
    public func calls(forTable table: String) -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return calls.filter { $0.table == table }
    }
}
