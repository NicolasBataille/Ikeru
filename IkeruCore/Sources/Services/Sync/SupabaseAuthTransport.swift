import Foundation

// MARK: - SupabaseAuthTransport

/// Abstraction over the two Supabase Auth (GoTrue) REST calls this lot
/// needs, so `AnonymousIdentityManager` is testable without touching the
/// network — see `MockSupabaseAuthTransport` below.
public protocol SupabaseAuthTransport: Sendable {

    /// Creates a brand-new anonymous user and returns its session.
    func signInAnonymously() async throws -> SyncSession

    /// Exchanges a (single-use, rotating) refresh token for a new session.
    func refreshSession(refreshToken: String) async throws -> SyncSession
}

// MARK: - Errors

public enum SyncAuthError: Error, Sendable, Equatable {
    case invalidResponse
    /// `error_code` (when present) + raw response body, for diagnosis.
    /// `anonymous_provider_disabled` is the one this lot is known to hit
    /// until the dashboard toggle is flipped — see this file's top doc
    /// comment.
    case requestFailed(status: Int, errorCode: String?, body: String)
}

// MARK: - URLSessionSupabaseAuthTransport

/// Production transport, built directly on `URLSession` + `Codable` — this
/// repo carries zero third-party dependencies (no `supabase-swift`), so this
/// hand-rolls the two GoTrue REST calls `supabase-js`'s `signInAnonymously()`
/// / auto-refresh perform under the hood.
///
/// ### Endpoint verification (task rule: "VERIFIE dans la doc, ne devine pas")
///
/// The Supabase docs site's client-SDK reference pages (JS/Swift/Dart/…)
/// document `signInAnonymously()` / `auth.signInAnonymously` at the
/// *client-library* level only — no raw REST/curl reference page for
/// `/auth/v1/signup` or `/auth/v1/token` turned up through the docs search
/// tool available in this task (searched multiple phrasings: "anonymous
/// sign-in REST API", "self-hosting auth REST reference", "GoTrue endpoint
/// reference"). What IS independently confirmed, against the **live**
/// project (`aiayzlarixlogcoyswna`), by an actual `curl` request run during
/// this task:
///
/// ```
/// curl -X POST '<projectURL>/auth/v1/signup' -H 'apikey: <publishableKey>' \
///      -H 'Content-Type: application/json' -d '{}'
/// → HTTP 422 {"code":422,"error_code":"anonymous_provider_disabled",
///             "msg":"Anonymous sign-ins are disabled"}
/// ```
///
/// This is strong (not conclusive, but strong) confirmation that
/// `POST /auth/v1/signup` with an empty JSON body IS the correct anonymous
/// sign-in shape: GoTrue parsed the request far enough to reach its
/// anonymous-provider feature-flag check and return a structured,
/// feature-specific error — a malformed path or body shape would instead
/// produce a generic 404 or a body-parse 400, not this. **Anonymous
/// sign-ins are currently DISABLED on this project** — this lot's auth flow
/// cannot complete end-to-end until "Enable Anonymous Sign-Ins" is turned on
/// in Supabase Dashboard → Authentication → Providers. Flagged again in this
/// task's final notes; not something this file's file perimeter can fix.
///
/// The refresh endpoint (`POST /auth/v1/token?grant_type=refresh_token`,
/// body `{"refresh_token": "..."}`) is the standard GoTrue REST shape used
/// by every official Supabase client under the hood, but was NOT separately
/// curl-verified in this task (doing so needs a live refresh token, which
/// requires anonymous sign-in to be enabled first — see above).
public struct URLSessionSupabaseAuthTransport: SupabaseAuthTransport {

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        baseURL: URL = SupabaseConfig.projectURL,
        apiKey: String = SupabaseConfig.publishableKey,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.now = now
    }

    public func signInAnonymously() async throws -> SyncSession {
        try await perform(path: "auth/v1/signup", queryItems: [], body: Data("{}".utf8))
    }

    public func refreshSession(refreshToken: String) async throws -> SyncSession {
        let body = try JSONEncoder().encode(["refresh_token": refreshToken])
        return try await perform(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body
        )
    }

    private func perform(path: String, queryItems: [URLQueryItem], body: Data) async throws -> SyncSession {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SyncAuthError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw SyncAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            let errorCode = (try? JSONDecoder().decode(GoTrueErrorResponse.self, from: data))?.errorCode
            throw SyncAuthError.requestFailed(status: http.statusCode, errorCode: errorCode, body: bodyString)
        }

        let decoded = try JSONDecoder().decode(GoTrueSessionResponse.self, from: data)
        return SyncSession(
            userID: decoded.user.id,
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }
}

// MARK: - GoTrue wire shapes

private struct GoTrueSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    struct User: Decodable {
        let id: UUID
    }
}

private struct GoTrueErrorResponse: Decodable {
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
    }
}

// MARK: - MockSupabaseAuthTransport

/// In-memory fake for tests — no network. Records every call so a test can
/// assert on how many times sign-in / refresh were attempted (e.g. "consent
/// off ⇒ zero auth calls ever").
public final class MockSupabaseAuthTransport: SupabaseAuthTransport, @unchecked Sendable {

    public var signInResult: Result<SyncSession, Error>
    public var refreshResult: Result<SyncSession, Error>
    public private(set) var signInCallCount = 0
    public private(set) var refreshCallCount = 0
    public private(set) var lastRefreshToken: String?

    private let lock = NSLock()

    public init(
        signInResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse),
        refreshResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse)
    ) {
        self.signInResult = signInResult
        self.refreshResult = refreshResult
    }

    public func signInAnonymously() async throws -> SyncSession {
        // `lock()`/`unlock()` are `noasync` on current SDKs (priority-inversion
        // guard) — `withLock` runs the whole critical section synchronously,
        // so it's safe to call from this `async` function.
        let result: Result<SyncSession, Error> = lock.withLock {
            signInCallCount += 1
            return signInResult
        }
        return try result.get()
    }

    public func refreshSession(refreshToken: String) async throws -> SyncSession {
        let result: Result<SyncSession, Error> = lock.withLock {
            refreshCallCount += 1
            lastRefreshToken = refreshToken
            return refreshResult
        }
        return try result.get()
    }
}
