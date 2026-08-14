import Foundation

// MARK: - SyncPullTransport

/// Abstraction over a PostgREST bulk-read call — the pull-side counterpart
/// to `SyncDataTransport.upsert`. Protocol boundary so a future pull engine
/// (`SyncModelActor` / `CloudSyncCoordinator`, out of this lot's file
/// perimeter) is testable with `MockSyncPullTransport` below, without
/// touching the network.
///
/// ## Pagination contract
/// `fetchRows` returns AT MOST `limit` rows, ordered ascending by
/// `server_updated_at` (with `id` as a secondary sort key, for a
/// deterministic order among ties — see below). The caller owns the
/// pagination loop:
///
/// 1. Call `fetchRows(table:since:limit:accessToken:)` with `since` set to
///    `SyncCursorStore.cursor(forTable:)` (`nil` on a cold start).
/// 2. Apply the returned rows locally.
/// 3. Advance the cursor from those SAME rows —
///    `SyncCursorStore.advanceCursor(forTable:afterApplying:)`, which
///    returns the new cursor (`nil` if it didn't move) — never advance
///    before step 2 succeeds (see that method's doc comment).
/// 4. If the response had exactly `limit` rows, there may be more: repeat
///    from step 1 with the now-advanced cursor.
/// 5. Stop once a response comes back with FEWER than `limit` rows
///    (including zero) — that's the "caught up" signal.
///
/// A learner with a year of history can have thousands of `review_logs`
/// rows; without this loop a single page silently truncates their pull.
/// Stopping early on a full page is the wrong optimization to make here —
/// re-querying once more when already caught up is cheap, silently
/// truncating a sync is not.
///
/// ## Known hazard: a tie cluster wider than `limit` stalls this loop
/// This cursor is a single `Date`, per the task's fixed protocol shape —
/// not a `(timestamp, id)` keyset cursor. That matters because every
/// synced table's `server_updated_at` trigger stamps rows with `now()`
/// (the TRANSACTION timestamp, not `clock_timestamp()` — verified via
/// `pg_get_functiondef` against the live `touch_server_updated_at()`
/// function on 2026-08-14, same function on all 8 tables). One bulk
/// upsert — e.g. one `SyncModelActor` push flushing hundreds of dirty
/// `review_logs` rows in a single `POST` — therefore gives ALL of those
/// rows the exact same `server_updated_at`. If that tie cluster is larger
/// than `limit`, step 3's cursor stops advancing (every row in the page
/// has the same timestamp as the last), step 4's re-fetch with `gte.`
/// that same timestamp returns the identical page again, and step 5's
/// termination condition never fires — the loop spins forever without
/// making progress.
///
/// This transport does not solve that (a `Date`-only cursor structurally
/// can't distinguish "already delivered this tied row" from "haven't
/// delivered it yet" once the tie cluster exceeds one page — only a
/// composite `(server_updated_at, id)` cursor can, and that's a protocol
/// change outside this lot's scope). Mitigations available to the
/// pull-engine caller within today's protocol:
///
/// - Pick `limit` comfortably larger than the largest single-transaction
///   batch the push side ever writes, so realistic tie clusters fit in
///   one page.
/// - Treat "`advanceCursor` returned `nil` (or an unchanged value) after a
///   full-`limit` page" as a hard stop with a logged/surfaced error,
///   rather than an infinite retry — better to abandon that page than to
///   spin.
public protocol SyncPullTransport: Sendable {

    /// Fetches up to `limit` rows from `table`, ordered ascending by
    /// `server_updated_at`.
    ///
    /// - `since: nil` means "no lower bound" — a full first pull, used only
    ///   when `SyncCursorStore.cursor(forTable:)` is `nil` for this table.
    /// - `since` non-nil filters `server_updated_at >= since` (inclusive —
    ///   see `PostgRESTPullTransport`'s doc comment for why `gte` and not
    ///   `gt`).
    func fetchRows(table: String, since: Date?, limit: Int, accessToken: String) async throws -> [SyncRow]
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
/// Request shape:
///
/// - `GET {baseURL}/rest/v1/{table}?order=server_updated_at.asc,id.asc&limit={limit}`,
///   plus `&server_updated_at=gte.{iso8601}` when `since` is non-nil. The
///   `id.asc` secondary sort key exists purely for a deterministic row
///   order among ties (see the "known hazard" section on
///   `SyncPullTransport` above) — it does not, by itself, make pagination
///   correct across a tie cluster wider than `limit`.
/// - `apikey: <publishableKey>` + `Authorization: Bearer <accessToken>` —
///   same pairing as the push transport; RLS scopes every row this returns
///   to `auth.uid() = user_id`, so no other learner's rows can leak through
///   this call regardless of `table`.
///
/// ## Why `gte`, not `gt`
/// Two rows can legitimately share the exact same `server_updated_at`
/// (same trigger-clock tick). Filtering strictly greater-than the cursor
/// after advancing it to `max(seen)` would silently drop the row(s) tied
/// for that max. `gte` intentionally re-fetches the boundary row(s) already
/// applied on the previous page — safe because applying a row is an upsert
/// keyed by primary key (`id`), so re-applying an already-applied row is a
/// no-op, not a duplicate or a data-loss risk.
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

    public func fetchRows(table: String, since: Date?, limit: Int, accessToken: String) async throws -> [SyncRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SyncPullTransportError.invalidResponse
        }

        var queryItems = [
            URLQueryItem(name: "order", value: "server_updated_at.asc,id.asc"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let since {
            queryItems.append(URLQueryItem(name: "server_updated_at", value: "gte.\(SyncJSON.iso8601String(since))"))
        }
        components.queryItems = queryItems

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
}

// MARK: - MockSyncPullTransport

/// In-memory fake for tests — mirrors `MockSyncDataTransport`'s shape
/// (recorded calls + programmable responses) so other agents can test a
/// pull engine without a network dependency.
public final class MockSyncPullTransport: SyncPullTransport, @unchecked Sendable {

    public struct Call: Sendable, Equatable {
        public let table: String
        public let since: Date?
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

    public func fetchRows(table: String, since: Date?, limit: Int, accessToken: String) async throws -> [SyncRow] {
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
