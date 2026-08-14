import Foundation

// MARK: - SyncDataTransport

/// Abstraction over a PostgREST bulk-upsert call — the one network
/// operation this lot's push engine performs against data tables (as
/// opposed to Auth). Protocol boundary so `SyncModelActor` /
/// `CloudSyncCoordinator` are testable with `MockSyncDataTransport` and
/// never touch the network in tests.
public protocol SyncDataTransport: Sendable {

    /// Upserts `rows` into `table`. Conflicts resolve on the table's primary
    /// key (`id`, already the client-generated UUID — see design spec §3),
    /// so no `on_conflict` query parameter is needed.
    func upsert(table: String, rows: [SyncRow], accessToken: String) async throws
}

public enum SyncDataTransportError: Error, Sendable, Equatable {
    case invalidResponse
    case requestFailed(status: Int, body: String)
}

// MARK: - PostgRESTSyncTransport

/// Production transport, built on `URLSession` — no `supabase-swift`
/// dependency (this repo carries none, by design).
///
/// Request shape, verified against the PostgREST/Supabase docs (`upsert`
/// reference pages + RLS guide) fetched during this task:
///
/// - `POST {baseURL}/rest/v1/{table}`
/// - `apikey: <publishableKey>` on every request (RLS enforces `auth.uid()`
///   from the bearer token; `apikey` identifies the project/role tier).
/// - `Authorization: Bearer <accessToken>` — the signed-in anonymous user's
///   access token, so `auth.uid()` resolves server-side and every synced
///   row's `user_id` (a `default auth.uid()` column — never sent by this
///   client) matches the owning row's RLS check.
/// - `Prefer: resolution=merge-duplicates, return=minimal` — the header
///   form of `.upsert()`. Verified via the Supabase MCP (`pg_policies` on
///   `public`, all 8 tables) that every table actually carries a full
///   SELECT/INSERT/UPDATE/DELETE policy set, each scoped to
///   `auth.uid() = user_id` — so `return=representation` would NOT 403 here
///   (an earlier draft of this comment guessed otherwise without checking;
///   corrected). `return=minimal` is kept anyway: a push-only client has no
///   use for the echoed rows, and skipping them avoids an unnecessary
///   response payload — a real optimization, just not a correctness
///   requirement.
public struct PostgRESTSyncTransport: SyncDataTransport {

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

    public func upsert(table: String, rows: [SyncRow], accessToken: String) async throws {
        guard !rows.isEmpty else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/\(table)"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try rows.encodedRequestBody()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncDataTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw SyncDataTransportError.requestFailed(status: http.statusCode, body: bodyString)
        }
    }
}

// MARK: - MockSyncDataTransport

/// In-memory fake for tests. Records every upsert call (table, rows,
/// token) so tests can assert on idempotency (same `id` pushed twice ⇒ one
/// logical row, since real PostgREST upsert would merge — this fake doesn't
/// need to dedupe itself, callers assert on the row *contents* pushed, e.g.
/// last-write-wins per `id` if that's what's under test) and on "nothing
/// pushed without consent" (zero calls recorded).
public final class MockSyncDataTransport: SyncDataTransport, @unchecked Sendable {

    public struct Call: Sendable, Equatable {
        public let table: String
        public let rows: [SyncRow]
        public let accessToken: String
    }

    public var errorToThrow: Error?
    public private(set) var calls: [Call] = []

    private let lock = NSLock()

    public init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    public func upsert(table: String, rows: [SyncRow], accessToken: String) async throws {
        // `lock()`/`unlock()` are `noasync` on current SDKs (priority-inversion
        // guard) — `withLock` runs the whole critical section synchronously,
        // so it's safe to call from this `async` function.
        let error: Error? = lock.withLock {
            calls.append(Call(table: table, rows: rows, accessToken: accessToken))
            return errorToThrow
        }
        if let error { throw error }
    }

    /// All rows ever pushed to `table`, across every call, in call order.
    public func rows(forTable table: String) -> [SyncRow] {
        lock.lock()
        defer { lock.unlock() }
        return calls.filter { $0.table == table }.flatMap { $0.rows }
    }
}
