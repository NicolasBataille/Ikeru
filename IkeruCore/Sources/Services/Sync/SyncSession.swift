import Foundation

/// A Supabase Auth session for the device's anonymous identity — see
/// `AnonymousIdentityManager`. Persisted to Keychain (never `UserDefaults`,
/// per rule) as JSON encoded through `SyncJSON`.
public struct SyncSession: Codable, Equatable, Sendable {

    /// The Supabase `auth.users.id` for this device's anonymous account.
    /// Becomes `auth.uid()` server-side, which every RLS policy checks
    /// against `user_id`.
    public let userID: UUID

    /// Short-lived JWT sent as `Authorization: Bearer <accessToken>` on
    /// every REST/PostgREST request.
    public let accessToken: String

    /// Long-lived, single-use token exchanged for a new `accessToken` (and a
    /// NEW `refreshToken` — GoTrue rotates it on every use). Never sent to
    /// PostgREST, only to `/auth/v1/token`.
    public let refreshToken: String

    /// Wall-clock expiry of `accessToken`, computed at sign-in/refresh time
    /// from the server's `expires_in` (seconds).
    public let expiresAt: Date

    public init(userID: UUID, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True once `accessToken` is at or past its `margin`-second safety
    /// window — the trigger `AnonymousIdentityManager` uses to refresh
    /// proactively instead of waiting for a 401.
    public func needsRefresh(margin: TimeInterval = 60, now: Date = Date()) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}
