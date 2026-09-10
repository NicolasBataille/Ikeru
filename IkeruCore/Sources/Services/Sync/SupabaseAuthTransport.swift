import Foundation

// MARK: - SupabaseAuthTransport

/// Abstraction over the Supabase Auth (GoTrue) REST calls this module needs,
/// so `AnonymousIdentityManager` is testable without touching the network —
/// see `MockSupabaseAuthTransport` below.
public protocol SupabaseAuthTransport: Sendable {

    /// Creates a brand-new anonymous user and returns its session.
    func signInAnonymously() async throws -> SyncSession

    /// Exchanges a (single-use, rotating) refresh token for a new session.
    func refreshSession(refreshToken: String) async throws -> SyncSession

    /// Grafts an Apple identity onto the CURRENTLY authenticated (anonymous)
    /// session — lot 3. `POST /auth/v1/token?grant_type=id_token`,
    /// `Authorization: Bearer <accessToken>` (the session being linked
    /// FROM), body `{"provider":"apple","id_token":idToken,"nonce":rawNonce,
    /// "link_identity":true}`. Exact shape read from auth-js's
    /// `linkIdentityIdToken` — see this type's doc comment for the
    /// verification story.
    ///
    /// A successful call is expected to return a session for the SAME
    /// `user_id` the `accessToken` belonged to — but this method does NOT
    /// itself enforce that. It is a dumb transport; the guard that compares
    /// before/after `user_id` and refuses to adopt a mismatch lives in
    /// `AnonymousIdentityManager.linkOrSignInWithApple`, the only place that
    /// also holds "which `user_id` did we start with" — see that method's
    /// doc comment for why this is THE load-bearing safety check of lot 3.
    ///
    /// Throws `SyncAuthError.identityAlreadyLinked` (not
    /// `.requestFailed`) when GoTrue refuses the link because this Apple
    /// identity already belongs to a DIFFERENT, existing account — see that
    /// case's doc comment for why the caller treats this as a distinct,
    /// expected outcome rather than a generic failure.
    func linkAppleIdentity(idToken: String, rawNonce: String, accessToken: String) async throws -> SyncSession

    /// Plain Sign in with Apple — same endpoint as `linkAppleIdentity`, but
    /// with NO `link_identity` key and NO `Authorization` header. Used when
    /// this device has no existing session to link (a fresh install) or
    /// once linking has been refused because the identity already belongs
    /// to someone else. Unlike `linkAppleIdentity`, this call makes no
    /// promise to preserve `user_id` — a legitimately different account
    /// coming back is the entire point, not a guard violation.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> SyncSession
}

// MARK: - Errors

public enum SyncAuthError: Error, Sendable, Equatable {
    case invalidResponse
    /// `error_code` (when present) + raw response body, for diagnosis.
    /// `anonymous_provider_disabled` is the one this lot is known to hit
    /// until the dashboard toggle is flipped — see this file's top doc
    /// comment.
    case requestFailed(status: Int, errorCode: String?, body: String)
    /// GoTrue refused `linkAppleIdentity` specifically because the Apple
    /// identity being linked already belongs to a DIFFERENT, existing
    /// account (manual linking never merges two already-existing accounts
    /// — it only ever attaches a NEW identity to the CURRENT session's
    /// user). Recognized by `error_code == "identity_already_exists"`,
    /// which is Supabase's documented auth error code for this exact
    /// conflict.
    ///
    /// ⚠️ Honesty note (task rule: never claim verified what wasn't):
    /// this exact code is NOT independently curl-verified in this task —
    /// doing so needs a live Apple ID already linked to a second,
    /// pre-existing Supabase account, which this task's environment cannot
    /// produce. Flagged again in this lot's final notes as something a
    /// device pass with two Apple-linked test accounts should confirm
    /// before this path is trusted in production; if the live code turns
    /// out to differ, this case simply never fires and
    /// `AnonymousIdentityManager.linkOrSignInWithApple` surfaces the
    /// generic `.requestFailed` instead — loud, not silent, either way.
    case identityAlreadyLinked(status: Int, body: String)
    /// Thrown by `AnonymousIdentityManager.currentSession()`'s demotion
    /// guards (lot 3) whenever minting a fresh anonymous identity would
    /// silently demote an already-linked device instead of asking the
    /// learner to reconnect. Two distinct triggers, both surfaced as this
    /// SAME case (a caller cannot tell which without inspecting Keychain
    /// state directly, and does not need to — both mean "reconnect"):
    /// - a LINKED (`isAnonymous == false`) session's refresh token was
    ///   explicitly rejected by the server; or
    /// - the Keychain holds NO session at all, but this device's
    ///   `SyncIdentityStore.wasLinked()` marker is `true` — the
    ///   iCloud-restore-onto-a-new-device case, where `UserDefaults`
    ///   restores but the `ThisDeviceOnly` Keychain entry does not (see
    ///   `SyncIdentityStore`'s type doc comment).
    /// Never thrown for a device that has NEVER held a linked session
    /// (`wasLinked() == false`) — that case still silently mints a fresh
    /// anonymous identity, unchanged from lot 1 — see `currentSession()`'s
    /// doc comment for both guards. The reachable recovery path from
    /// EITHER trigger is
    /// `AnonymousIdentityManager.linkOrSignInWithApple`, which treats this
    /// exact rejection as "no local session" and re-authenticates via
    /// Apple.
    case reauthenticationRequired

    /// The exact string `CloudSyncCoordinator.syncNow()`'s catch-all
    /// (`String(describing: error)`) writes into
    /// `SyncConsentStore.recordError` when THIS case is what aborted a
    /// cycle. `SettingsView`'s reconnect-prompt UI (app target, outside
    /// this lot's file perimeter) reads `cloudSyncLastError` back out and
    /// compares it against this exact value to decide whether to offer
    /// "Sign in with Apple again" — the ONLY reconnection path in the app.
    /// A bare string literal at that call site would silently stop
    /// matching the moment this case is ever renamed; referencing this
    /// constant from both sides keeps the two in lockstep by construction.
    /// Verified equal to what the coordinator actually writes by
    /// `AppleIdentityLinkingTests.reauthenticationRequiredMessageMatchesCoordinatorWrite`.
    public static let reauthenticationRequiredMessage = String(describing: SyncAuthError.reauthenticationRequired)
}

// MARK: - URLSessionSupabaseAuthTransport

/// Production transport, built directly on `URLSession` + `Codable` — this
/// repo carries zero third-party dependencies (no `supabase-swift`), so this
/// hand-rolls the GoTrue REST calls `supabase-js`'s `signInAnonymously()` /
/// auto-refresh / `linkIdentity()` perform under the hood.
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
/// produce a generic 404 or a body-parse 400, not this. At the time this
/// paragraph was written (lot 1), anonymous sign-ins were DISABLED on the
/// live project, blocking this flow end-to-end until the "Enable Anonymous
/// Sign-Ins" dashboard toggle was flipped. That toggle has since been
/// turned on — lots 0/1/2/4 (push, pull+merge, compliance, the Settings
/// toggle) are shipped and merged as of lot 3, which is only possible with
/// anonymous sign-in working — so this paragraph is now historical context
/// for the verification story, not a live blocker. Left in place rather
/// than deleted: it is still the only record of how this endpoint shape was
/// actually confirmed.
///
/// The refresh endpoint (`POST /auth/v1/token?grant_type=refresh_token`,
/// body `{"refresh_token": "..."}`) is the standard GoTrue REST shape used
/// by every official Supabase client under the hood, but was NOT separately
/// curl-verified in this task (doing so needs a live refresh token, which
/// requires anonymous sign-in to be enabled first — see above).
///
/// The `link_identity` shape (`linkAppleIdentity`/`signInWithApple` below,
/// lot 3) — `POST /auth/v1/token?grant_type=id_token`, `provider: "apple"`,
/// `id_token`, `nonce` (raw, unhashed), `link_identity: true` only for the
/// linking variant — was read directly out of auth-js's
/// `GoTrueClient.linkIdentityIdToken` source, not curl-verified against the
/// live project (that needs a real signed Apple identity token, which this
/// task's environment cannot produce). Task notes flag: "Client IDs" =
/// `com.ikeru.app` and "Manual linking" are both already enabled on the
/// live project's Apple provider config.
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
        let decoded = try await perform(path: "auth/v1/signup", queryItems: [], body: Data("{}".utf8), bearerToken: nil)
        return decoded.session(now: now(), isAnonymous: true)
    }

    public func refreshSession(refreshToken: String) async throws -> SyncSession {
        let body = try JSONEncoder().encode(["refresh_token": refreshToken])
        let decoded = try await perform(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body,
            bearerToken: nil
        )
        // `isAnonymous` here is a placeholder the caller (`AnonymousIdentityManager
        // .currentSession()`) always overwrites with the PREVIOUS session's own
        // flag before persisting — see `SyncSession.isAnonymous`'s doc comment
        // for why refresh deliberately never gets to decide this value itself.
        return decoded.session(now: now(), isAnonymous: false)
    }

    public func linkAppleIdentity(idToken: String, rawNonce: String, accessToken: String) async throws -> SyncSession {
        let body = try JSONEncoder().encode(
            AppleIDTokenBody(idToken: idToken, nonce: rawNonce, linkIdentity: true)
        )
        let decoded = try await perform(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: body,
            bearerToken: accessToken
        )
        // A successful LINK always yields a non-anonymous session by
        // definition — hardcoded, not decoded from the wire, same reasoning
        // as `signInAnonymously`.
        return decoded.session(now: now(), isAnonymous: false)
    }

    public func signInWithApple(idToken: String, rawNonce: String) async throws -> SyncSession {
        let body = try JSONEncoder().encode(
            // `linkIdentity: nil` — Swift's synthesized `Encodable` uses
            // `encodeIfPresent` for `Optional` stored properties, so a `nil`
            // value here OMITS the `link_identity` key entirely rather than
            // encoding `"link_identity":null`. Verified by
            // `URLSessionSupabaseAuthTransportRequestShapeTests` (asserts
            // the literal outgoing request body), not just assumed.
            AppleIDTokenBody(idToken: idToken, nonce: rawNonce, linkIdentity: nil)
        )
        let decoded = try await perform(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: body,
            bearerToken: nil
        )
        return decoded.session(now: now(), isAnonymous: false)
    }

    /// Shared request plumbing for all four calls above. `bearerToken`,
    /// when non-nil, is sent as `Authorization: Bearer <token>` —
    /// `linkAppleIdentity` is the only caller that passes one (the session
    /// being linked FROM); every other call authenticates purely via the
    /// request body (`signInAnonymously`, `signInWithApple`) or the
    /// refresh token itself (`refreshSession`).
    private func perform(
        path: String,
        queryItems: [URLQueryItem],
        body: Data,
        bearerToken: String?
    ) async throws -> GoTrueSessionResponse {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SyncAuthError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw SyncAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            let errorCode = (try? JSONDecoder().decode(GoTrueErrorResponse.self, from: data))?.errorCode
            if errorCode == "identity_already_exists" {
                throw SyncAuthError.identityAlreadyLinked(status: http.statusCode, body: bodyString)
            }
            throw SyncAuthError.requestFailed(status: http.statusCode, errorCode: errorCode, body: bodyString)
        }

        return try JSONDecoder().decode(GoTrueSessionResponse.self, from: data)
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

    func session(now: Date, isAnonymous: Bool) -> SyncSession {
        SyncSession(
            userID: user.id,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)),
            isAnonymous: isAnonymous
        )
    }
}

private struct GoTrueErrorResponse: Decodable {
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
    }
}

/// Wire body for `POST /auth/v1/token?grant_type=id_token` — shared by
/// `linkAppleIdentity` (`linkIdentity: true`) and `signInWithApple`
/// (`linkIdentity: nil`, so the key is omitted — see that call site's
/// comment).
private struct AppleIDTokenBody: Encodable {
    let provider = "apple"
    let idToken: String
    let nonce: String
    // Deliberately Optional, not a plain `Bool` defaulting to `false` — a
    // three-state field (present-true / present-false / ABSENT) is exactly
    // the wire shape this type exists to produce. `nil` here means the
    // "link_identity" key is omitted entirely (Swift's synthesized
    // `Encodable` uses `encodeIfPresent` for `Optional` properties), which
    // is a materially different request than sending `"link_identity":false`
    // — the task's exact call shape only ever specifies the key as present
    // with `true`, or absent.
    // swiftlint:disable:next discouraged_optional_boolean
    let linkIdentity: Bool?

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
        case linkIdentity = "link_identity"
    }
}

// MARK: - MockSupabaseAuthTransport

/// In-memory fake for tests — no network. Records every call so a test can
/// assert on how many times each entry point was attempted (e.g. "consent
/// off ⇒ zero auth calls ever", or lot 3's "identity already linked ⇒ falls
/// back to plain sign-in exactly once").
public final class MockSupabaseAuthTransport: SupabaseAuthTransport, @unchecked Sendable {

    public var signInResult: Result<SyncSession, Error>
    public var refreshResult: Result<SyncSession, Error>
    public var linkAppleResult: Result<SyncSession, Error>
    public var signInWithAppleResult: Result<SyncSession, Error>

    public private(set) var signInCallCount = 0
    public private(set) var refreshCallCount = 0
    public private(set) var linkAppleCallCount = 0
    public private(set) var signInWithAppleCallCount = 0
    public private(set) var lastRefreshToken: String?
    /// `accessToken` passed to the most recent `linkAppleIdentity` call —
    /// what a test asserts against to confirm the CURRENT session's token
    /// (not some other one) was what got sent to link with.
    public private(set) var lastLinkAccessToken: String?
    public private(set) var lastAppleIDToken: String?
    public private(set) var lastAppleRawNonce: String?

    private let lock = NSLock()

    public init(
        signInResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse),
        refreshResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse),
        linkAppleResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse),
        signInWithAppleResult: Result<SyncSession, Error> = .failure(SyncAuthError.invalidResponse)
    ) {
        self.signInResult = signInResult
        self.refreshResult = refreshResult
        self.linkAppleResult = linkAppleResult
        self.signInWithAppleResult = signInWithAppleResult
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

    public func linkAppleIdentity(idToken: String, rawNonce: String, accessToken: String) async throws -> SyncSession {
        let result: Result<SyncSession, Error> = lock.withLock {
            linkAppleCallCount += 1
            lastLinkAccessToken = accessToken
            lastAppleIDToken = idToken
            lastAppleRawNonce = rawNonce
            return linkAppleResult
        }
        return try result.get()
    }

    public func signInWithApple(idToken: String, rawNonce: String) async throws -> SyncSession {
        let result: Result<SyncSession, Error> = lock.withLock {
            signInWithAppleCallCount += 1
            lastAppleIDToken = idToken
            lastAppleRawNonce = rawNonce
            return signInWithAppleResult
        }
        return try result.get()
    }
}
