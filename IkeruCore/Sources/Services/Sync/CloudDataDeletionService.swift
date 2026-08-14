import Foundation
import SwiftData

// MARK: - CloudDeletionTransport

/// Abstraction over the one network call this file needs — invoking the
/// `delete-account` Edge Function (`supabase/functions/delete-account`) —
/// so `CloudDataDeletionService` is testable without touching the network.
/// Modeled on `SupabaseAuthTransport` / `SyncDataTransport`: same shape,
/// same reason (protocol boundary + a `URLSession`-backed production type +
/// an in-memory mock for tests).
public protocol CloudDeletionTransport: Sendable {

    /// Calls the `delete-account` Edge Function as the identity that owns
    /// `accessToken`. The function itself re-derives the caller's user id
    /// from this token server-side (see that file's top comment) — this
    /// transport never sends a user id anywhere.
    func deleteAccount(accessToken: String) async throws
}

public enum CloudDeletionError: Error, Sendable, Equatable {
    case invalidResponse
    case requestFailed(status: Int, body: String)
}

// MARK: - URLSessionCloudDeletionTransport

/// Production transport, built on `URLSession` — no `supabase-swift`
/// dependency (this repo carries none, by design), same as every other
/// transport in this module.
///
/// Request shape: `POST {baseURL}/functions/v1/delete-account`, with the
/// SAME two headers `PostgRESTSyncTransport` sends — `apikey` (publishable
/// key, identifies the project) and `Authorization: Bearer <accessToken>`
/// (the caller's own session; the function's `auth.getUser()` call is what
/// actually authenticates the request server-side, not this header's mere
/// presence).
public struct URLSessionCloudDeletionTransport: CloudDeletionTransport {

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

    public func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudDeletionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw CloudDeletionError.requestFailed(status: http.statusCode, body: bodyString)
        }
    }
}

// MARK: - MockCloudDeletionTransport

/// In-memory fake for tests — no network. Records every call so a test can
/// assert on call count / the token used, and can be configured to fail so
/// tests can assert the local session survives a server-side failure.
public final class MockCloudDeletionTransport: CloudDeletionTransport, @unchecked Sendable {

    public var errorToThrow: Error?
    public private(set) var callCount = 0
    public private(set) var lastAccessToken: String?

    private let lock = NSLock()

    public init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    public func deleteAccount(accessToken: String) async throws {
        // `lock()`/`unlock()` are `noasync` on current SDKs (priority-inversion
        // guard) — `withLock` runs the whole critical section synchronously,
        // so it's safe to call from this `async` function. Same pattern as
        // `MockSyncDataTransport` / `MockSupabaseAuthTransport`.
        let error: Error? = lock.withLock {
            callCount += 1
            lastAccessToken = accessToken
            return errorToThrow
        }
        if let error { throw error }
    }
}

// MARK: - CloudDataDeletionService

/// Erases this device's cloud-synced data server-side, then purges the
/// local proof of identity (the Keychain-persisted `SyncSession`) — the
/// counterpart to `CloudSyncCoordinator`'s push-only sync (lot 1). Unlike
/// that lot, this one legitimately needs a server round trip that a plain
/// RLS-scoped client cannot perform (deleting the `auth.users` row itself),
/// which is why the actual deletion work lives server-side in
/// `supabase/functions/delete-account` — this actor's job is just: get a
/// valid token, call that function, then forget the session.
public actor CloudDataDeletionService {

    private let modelContainer: ModelContainer
    private let identity: AnonymousIdentityManager
    private let transport: any CloudDeletionTransport
    private let cursorStore: any SyncCursorStore
    private let skipTracker: any SyncSkipTracker

    public init(
        modelContainer: ModelContainer,
        identity: AnonymousIdentityManager = AnonymousIdentityManager(),
        transport: any CloudDeletionTransport = URLSessionCloudDeletionTransport(),
        cursorStore: any SyncCursorStore = UserDefaultsSyncCursorStore(),
        skipTracker: any SyncSkipTracker = UserDefaultsSyncSkipTracker()
    ) {
        self.modelContainer = modelContainer
        self.identity = identity
        self.transport = transport
        self.cursorStore = cursorStore
        self.skipTracker = skipTracker
    }

    /// Deletes every server-side row tied to this device's anonymous
    /// identity (see `supabase/functions/delete-account` for the exact
    /// table list and order), then forgets the local session so a future
    /// cloud-sync opt-in mints a fresh identity rather than reusing one
    /// whose server-side data was just erased.
    public func deleteAllCloudData() async throws {
        // `existingSessionAccessToken()`, NOT `validAccessToken()`. The
        // distinction is load-bearing for an erasure request, and the
        // reasoning lives in that method's doc comment: only a `nil` return
        // (nothing in the Keychain — this device never backed anything up)
        // is a legitimate no-op success. Any OTHER failure to obtain a token
        // — offline, sign-in down, refresh token rejected — now propagates
        // to the caller as a thrown error instead of being swallowed.
        //
        // What that buys: the UI can no longer tell a learner "your data was
        // deleted" while their rows are untouched on the server. Silence on
        // this path is not success; it is an unverified claim about someone
        // else's copy of their data, and it is exactly the claim a GDPR
        // erasure request must not get wrong.
        guard let accessToken = try await identity.existingSessionAccessToken() else {
            return
        }

        try await transport.deleteAccount(accessToken: accessToken)

        // Reset every pull cursor now that the server confirmed deletion —
        // BEFORE `forgetSession()` below, deliberately (IMPORTANT 6
        // remediation). Ordering matters here in the opposite direction
        // from the session purge: if `forgetSession()` were to throw after
        // this point, the server rows are already gone regardless, so
        // cleared cursors are still the correct local state — whereas
        // stale, non-nil cursors surviving next to an emptied server
        // account is exactly the hazard this fixes. A leftover cursor from
        // before the deletion means the NEXT pull (same device reusing a
        // still-Keychain-valid identity, or a freshly re-provisioned one)
        // would not look like a cold start to `SyncPullActor`
        // (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`,
        // `SyncPullActor.swift`), which disarms rule 1 — the guard that
        // stops a genuinely empty cloud account from ever being read as
        // "nothing to merge" for a device that still holds local data. This
        // makes `resetAll()` here, not `SettingsView`, the place that
        // guarantees this happens: any future second caller of this service
        // inherits the same protection instead of having to remember it.
        cursorStore.resetAll()
        // `SyncSkipTracker` state must be reset alongside the cursor it's
        // paired with — a strike count left over from before the deletion
        // would let this now-empty account's first genuinely poison row
        // inherit however many strikes the OLD account's row had racked up
        // (see `SyncSkipTracker.resetAll()`'s doc comment).
        skipTracker.resetAll()

        // CRITIQUE B: mark every local row unsynced now, not just reset the
        // cursors — without this, the NEXT opt-back-in push would see every
        // row's `syncedAt` still pointing at the account that was just
        // erased, read every one of them as "already synced", and push
        // almost nothing (only `profiles`/`rpg_states`, pushed
        // unconditionally). See `SyncModelActor.markEverythingUnsynced()`'s
        // doc comment for the full failure mode. Runs after `cursorStore.resetAll()`
        // (matching that call's own "server confirmed deletion" ordering
        // rationale below) but, like it, before the Keychain session is
        // forgotten — if this throws, the session survives so a retry can
        // still reach this point.
        try await SyncModelActor(modelContainer: modelContainer).markEverythingUnsynced()

        // Only purge the local Keychain session once the SERVER has
        // confirmed deletion succeeded. If this were purged first and the
        // network call above then failed, the learner would lose the only
        // local record of which server-side user_id was theirs — with no
        // session left, any retry mints a BRAND-NEW anonymous identity
        // (see `AnonymousIdentityManager`) with nothing left to point a
        // deletion request at, silently orphaning the old rows forever.
        try await identity.forgetSession()
    }
}
