import Foundation

// MARK: - SyncIdentityStore

/// Persists the `user_id` this device synced as the last time
/// `CloudSyncCoordinator.syncNow()` ran — the mechanism that detects
/// **identity re-provisioning** (2026-08 lot-2 pull review, round 4
/// CRITICAL): `AnonymousIdentityManager` silently mints a brand-new
/// anonymous identity whenever a stored refresh token is rejected (expired,
/// or already rotated away by a previous attempt that crashed between the
/// server issuing a new one and this device persisting it — see that
/// type's `currentSession()` doc comment). The server-side account behind
/// that NEW `user_id` is empty by definition.
///
/// A device that has already synced under the OLD identity carries
/// non-`nil` pull cursors on every table (`SyncCursorStore`), so
/// `SyncPullActor`'s rule-1 cold-start guard
/// (`isColdStart = pullOrder.allSatisfy { cursor(forTable:) == nil }`) can
/// never fire on its own after a silent re-provisioning: the fresh, empty
/// account is pulled as though it were the SAME account this device
/// already knows, `PullOutcome.seededFromLocal` never fires, and
/// `SyncModelActor.markEverythingUnsynced()` — the only thing that makes
/// `pushDirtyCards`/`pushDirtyReviewLogs`/etc. actually resend rows still
/// stamped `syncedAt` from the now-orphaned old account — never runs.
/// Cards, review logs, and vocabulary silently stay local-only forever;
/// only `profiles`/`rpg_states` (pushed unconditionally every cycle) reach
/// the new account, and `SettingsView`'s status row reports "up to date"
/// throughout.
///
/// `CloudSyncCoordinator.syncNow()` compares
/// `AnonymousIdentityManager.currentUserID()` against what's stored here on
/// every cycle; a mismatch resets both `SyncCursorStore` and
/// `SyncSkipTracker` (the same pairing `setConsent(false)` already uses —
/// see that method's doc comment for why the two must always reset
/// together) so the pull that follows genuinely IS a cold start again, and
/// rule 1's existing `seededFromLocal` machinery takes over from there,
/// unchanged.
///
/// Same "no SwiftData schema change" motive as `SyncCursorPreferences` — a
/// single `UUID` in `UserDefaults` needs no V5 migration and no
/// process-isolated migration test.
public protocol SyncIdentityStore: Sendable {

    /// The `user_id` this device synced as the last time this check ran, or
    /// `nil` if it has never run before (a fresh install, or a device
    /// updating from a build that shipped before this fix existed). `nil`
    /// is NOT itself a re-provisioning signal — see
    /// `CloudSyncCoordinator.syncNow()`'s call site for why a `nil` read
    /// must only ever be recorded, never treated as a mismatch.
    func lastKnownUserID() -> UUID?

    /// Persists `id` as the new "last known" `user_id`.
    func setLastKnownUserID(_ id: UUID)
}

// MARK: - SyncIdentityPreferences

/// `UserDefaults` key scheme — new key, this lot's file perimeter is
/// `Services/Sync/` only, same reasoning as `SyncCursorPreferences`.
public enum SyncIdentityPreferences {
    public static let lastKnownUserIDKey = "ikeru.cloudSync.identity.lastKnownUserID"
}

// MARK: - UserDefaultsSyncIdentityStore

/// Production implementation over `UserDefaults.standard` (or an injected
/// suite), matching `UserDefaultsSyncCursorStore`'s pattern.
public final class UserDefaultsSyncIdentityStore: SyncIdentityStore, @unchecked Sendable {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastKnownUserID() -> UUID? {
        guard let raw = defaults.string(forKey: SyncIdentityPreferences.lastKnownUserIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public func setLastKnownUserID(_ id: UUID) {
        defaults.set(id.uuidString, forKey: SyncIdentityPreferences.lastKnownUserIDKey)
    }
}

// MARK: - MockSyncIdentityStore

/// In-memory fake for tests — deliberately NOT backed by `UserDefaults.standard`,
/// which would leak state across every other test sharing this process (Swift
/// Testing runs many `@Test`s in one process even under `--no-parallel`).
public final class MockSyncIdentityStore: SyncIdentityStore, @unchecked Sendable {

    private var storedID: UUID?
    private let lock = NSLock()

    public init(lastKnownUserID: UUID? = nil) {
        self.storedID = lastKnownUserID
    }

    public func lastKnownUserID() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return storedID
    }

    public func setLastKnownUserID(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        storedID = id
    }
}
