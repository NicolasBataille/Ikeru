import Foundation

/// A Supabase Auth session for the device's identity — see
/// `AnonymousIdentityManager`. Persisted to Keychain (never `UserDefaults`,
/// per rule) as JSON encoded through `SyncJSON`.
public struct SyncSession: Codable, Equatable, Sendable {

    /// The Supabase `auth.users.id` for this device's account. Becomes
    /// `auth.uid()` server-side, which every RLS policy checks against
    /// `user_id`.
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

    /// True while this session belongs to Supabase's built-in "anonymous
    /// user" flow (`signInAnonymously()`); false once it's been linked to
    /// (or created directly via) a real external provider — Sign in with
    /// Apple, lot 3.
    ///
    /// **This flag is load-bearing, not cosmetic** —
    /// `AnonymousIdentityManager.currentSession()`'s refresh-rejection
    /// handling conditions its "mint a brand-new anonymous identity"
    /// fallback on this being `true`. A `false` session (linked to a real
    /// account) whose refresh is rejected must instead surface a
    /// "reconnect" error: silently re-minting there would demote a
    /// signed-in learner to a fresh anonymous ghost, invisibly, with no way
    /// back short of noticing their progress vanished. See that method's
    /// doc comment for the full story.
    ///
    /// Set explicitly at the three places a `SyncSession` is actually
    /// created — `signInAnonymously()` (`true`), `linkAppleIdentity`/
    /// `signInWithApple` (`false`) — and CARRIED FORWARD, never
    /// re-derived, across `refreshSession` (a refresh cannot itself change
    /// whether the underlying account is anonymous — see
    /// `AnonymousIdentityManager.currentSession()`'s refresh branch, which
    /// is the one place that does the carrying-forward, deliberately NOT
    /// trusting `SupabaseAuthTransport.refreshSession`'s own return value
    /// for this field: that keeps this safety-critical flag independent of
    /// whether GoTrue's refresh response wire shape happens to include a
    /// trustworthy `is_anonymous` — a claim this task could not
    /// independently curl-verify).
    public let isAnonymous: Bool

    public init(userID: UUID, accessToken: String, refreshToken: String, expiresAt: Date, isAnonymous: Bool = true) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.isAnonymous = isAnonymous
    }

    private enum CodingKeys: String, CodingKey {
        case userID, accessToken, refreshToken, expiresAt, isAnonymous
    }

    /// Custom decoding SOLELY to default `isAnonymous` to `true` when the
    /// key is absent — every session persisted to Keychain before lot 3
    /// shipped predates this field entirely. `true` is the correct default
    /// for that population by construction: lot 3 is the very first thing
    /// able to produce a `false` (linked) session, so anything decoded
    /// without the key was, by definition, still anonymous the last time it
    /// was written.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(isAnonymous, forKey: .isAnonymous)
    }

    /// True once `accessToken` is at or past its `margin`-second safety
    /// window — the trigger `AnonymousIdentityManager` uses to refresh
    /// proactively instead of waiting for a 401.
    public func needsRefresh(margin: TimeInterval = 60, now: Date = Date()) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}
