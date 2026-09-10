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
///
/// ### `wasLinked` (lot 3 — Critique #1 remediation)
///
/// This protocol also carries a second, unrelated-at-first-glance marker:
/// whether this device has EVER persisted a linked (non-anonymous)
/// `SyncSession`. It lives here, backed by `UserDefaults` exactly like
/// `lastKnownUserID` above, for one specific reason — the asymmetry
/// between where the two halves of this device's identity actually live:
///
/// - The real `SyncSession` (`AnonymousIdentityManager`) is Keychain-only,
///   saved with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It NEVER
///   migrates to another device, not even via an iCloud backup restore —
///   that accessibility flag exists specifically to prevent it.
/// - `UserDefaults` (and therefore anything this protocol stores) DOES
///   restore from an iCloud device backup.
///
/// So a learner who links Sign in with Apple on device A, then restores
/// that backup onto device B, arrives on B with `UserDefaults` intact but
/// an EMPTY Keychain — exactly the state a brand-new install is in. Without
/// a marker that survives on the `UserDefaults` side of that split, device
/// B cannot tell "never linked, mint anonymous" apart from "was linked,
/// something just doesn't have the receipt" — and
/// `AnonymousIdentityManager.currentSession()` used to resolve that
/// ambiguity by always assuming the former, silently minting a fresh
/// anonymous ghost identity and orphaning the real account. `wasLinked`
/// closes that gap: it is written the moment a non-anonymous session is
/// first adopted, and consulted by `currentSession()` before ANY anonymous
/// mint that would otherwise happen with an empty Keychain.
///
/// It is un-written in exactly ONE place, deliberately: after
/// `CloudDataDeletionService.deleteAllCloudData()` confirms the server-side
/// account no longer exists —
/// `AnonymousIdentityManager.forgetSessionAfterAccountDeletion()` (2026-08
/// lot-3 round-2 remediation, CRITIQUE item 4). Once the account is truly
/// gone, there is nothing left for this marker to protect; leaving it
/// `true` would instead permanently lock the device out of ever syncing
/// again (every `currentSession()` call throwing
/// `.reauthenticationRequired` forever, on an account that no longer
/// exists to reconnect to).
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

    /// `true` once this device has EVER persisted a linked (non-anonymous)
    /// `SyncSession` — see this protocol's type doc comment for exactly why
    /// this needs its own, `UserDefaults`-backed existence separate from
    /// the Keychain-only session itself. `false` for a device that has
    /// only ever held anonymous sessions (including a genuinely fresh
    /// install), OR whose linked account was deliberately erased via
    /// `CloudDataDeletionService` — those are the ONLY two populations
    /// this must ever say `false` for, since a `false` positive here (a
    /// device that was linked and whose account is still real) makes
    /// `AnonymousIdentityManager.currentSession()` throw
    /// `SyncAuthError.reauthenticationRequired` instead of minting an
    /// anonymous identity on first launch.
    func wasLinked() -> Bool

    /// Records that this device has now persisted a linked session, or
    /// clears that record after a confirmed account deletion. Almost every
    /// caller only ever passes `true` — see `wasLinked()`'s doc comment for
    /// the single exception (`AnonymousIdentityManager
    /// .forgetSessionAfterAccountDeletion()`), the only place in this lot
    /// that passes `false`.
    func setWasLinked(_ value: Bool)
}

// MARK: - SyncIdentityPreferences

/// `UserDefaults` key scheme — new key, this lot's file perimeter is
/// `Services/Sync/` only, same reasoning as `SyncCursorPreferences`.
public enum SyncIdentityPreferences {
    public static let lastKnownUserIDKey = "ikeru.cloudSync.identity.lastKnownUserID"
    /// Lot 3 — see `SyncIdentityStore`'s type doc comment for why this
    /// marker exists and must live in `UserDefaults`, not the Keychain.
    public static let wasLinkedKey = "ikeru.cloudSync.identity.wasLinked"
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

    public func wasLinked() -> Bool {
        defaults.bool(forKey: SyncIdentityPreferences.wasLinkedKey)
    }

    public func setWasLinked(_ value: Bool) {
        defaults.set(value, forKey: SyncIdentityPreferences.wasLinkedKey)
    }
}

// MARK: - MockSyncIdentityStore

/// In-memory fake for tests — deliberately NOT backed by `UserDefaults.standard`,
/// which would leak state across every other test sharing this process (Swift
/// Testing runs many `@Test`s in one process even under `--no-parallel`).
public final class MockSyncIdentityStore: SyncIdentityStore, @unchecked Sendable {

    private var storedID: UUID?
    private var storedWasLinked: Bool
    private let lock = NSLock()

    public init(lastKnownUserID: UUID? = nil, wasLinked: Bool = false) {
        self.storedID = lastKnownUserID
        self.storedWasLinked = wasLinked
    }

    public func lastKnownUserID() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return storedID
    }

    public func setLastKnownUserID(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        storedID = id
    }

    public func wasLinked() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storedWasLinked
    }

    public func setWasLinked(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        storedWasLinked = value
    }
}
