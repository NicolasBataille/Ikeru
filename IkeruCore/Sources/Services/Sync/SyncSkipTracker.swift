import Foundation

// MARK: - SyncSkipTracker

/// Tracks, per table, how many CONSECUTIVE pull cycles have failed to get
/// past the SAME head-of-line row — the mechanism that turns "a row that
/// will never apply" from an infinite, silent stall into a bounded, visible
/// abandonment.
///
/// The disaster this closes: before this existed, a permanently
/// inapplicable row (a payload written by a newer app version, or a log
/// whose card will never exist on this device) pinned a table's cursor
/// FOREVER — every future pull re-fetched the same row, failed to apply it
/// again, and never advanced past it. In a short page that froze just that
/// one table silently; once the backlog behind it reached `pageSize`, the
/// page came back full and (before `SyncPullActor`'s per-table stall
/// handling was fixed alongside this) killed the entire pull cycle,
/// including every table listed after it in `pullOrder`.
///
/// `SyncPullActor` calls `recordSkip` once per cycle for whichever row is
/// currently stuck at the head of a table's unapplied rows. After 3
/// consecutive cycles on the exact same row id, it force-advances the
/// cursor past that row (safe, precise, and collateral-free specifically
/// BECAUSE the cursor is a composite `(timestamp, id)` keyset — see
/// `SyncCursorPosition` — rather than the single `Date` this lot shipped
/// with first, which could only skip an entire tie cluster at once), counts
/// the row as permanently dropped, and logs it.
///
/// Persisted the same way the cursor itself is (`UserDefaultsSyncSkipTracker`
/// mirrors `UserDefaultsSyncCursorStore`) rather than kept purely in-memory:
/// 3 strikes need to survive an app relaunch between sync cycles, or a
/// learner who only foregrounds the app once a day would effectively never
/// accumulate them.
public protocol SyncSkipTracker: Sendable {

    /// Records one more cycle stuck on `headRowID` for `table`. If a
    /// DIFFERENT id was tracked for this table before (or nothing was), the
    /// count resets to 1 — a new stuck candidate, not a continuation of the
    /// old one, per the type doc comment's "same id, 3 cycles" invariant.
    /// Returns the new count.
    @discardableResult
    func recordSkip(table: String, headRowID: UUID) -> Int

    /// Clears whatever is tracked for `table` — called once a cycle makes
    /// full progress on it (nothing stuck this time, so whatever transient
    /// stall happened before has self-healed) or once a poison row has been
    /// forcibly dropped, so the NEXT stuck row (if any) starts counting at
    /// 1, not wherever the dropped row's count left off.
    func clearSkip(table: String)

    /// Clears every table's tracked state. MUST be called everywhere
    /// `SyncCursorStore.resetAll()` is — consent revocation, account
    /// deletion, a pending cursor reset applied at the end of an in-flight
    /// cycle — see `SyncCursorStore.resetAll()`'s doc comment for why a
    /// stale strike count surviving a cursor reset is a real hazard, not
    /// just untidy state: a brand-new (or freshly re-provisioned) account's
    /// row could otherwise inherit 2 strikes from a completely unrelated
    /// previous account and get dropped on its very first genuine stall.
    func resetAll()
}

// MARK: - SyncSkipTrackerPreferences

/// `UserDefaults` key scheme, mirroring `SyncCursorPreferences`'s shape —
/// same file-perimeter reasoning, same "no SwiftData schema change" reason
/// for living in `UserDefaults` rather than a new `@Model` property.
public enum SyncSkipTrackerPreferences {

    public static let keyPrefix = "ikeru.cloudSync.skip."

    public static func headIDKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).headID"
    }

    public static func countKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).count"
    }
}

// MARK: - UserDefaultsSyncSkipTracker

public final class UserDefaultsSyncSkipTracker: SyncSkipTracker, @unchecked Sendable {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @discardableResult
    public func recordSkip(table: String, headRowID: UUID) -> Int {
        let idKey = SyncSkipTrackerPreferences.headIDKey(forTable: table)
        let countKey = SyncSkipTrackerPreferences.countKey(forTable: table)

        let newCount: Int
        if defaults.string(forKey: idKey) == headRowID.uuidString {
            newCount = defaults.integer(forKey: countKey) + 1
        } else {
            newCount = 1
        }
        defaults.set(headRowID.uuidString, forKey: idKey)
        defaults.set(newCount, forKey: countKey)
        return newCount
    }

    public func clearSkip(table: String) {
        defaults.removeObject(forKey: SyncSkipTrackerPreferences.headIDKey(forTable: table))
        defaults.removeObject(forKey: SyncSkipTrackerPreferences.countKey(forTable: table))
    }

    public func resetAll() {
        let prefix = SyncSkipTrackerPreferences.keyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - MockSyncSkipTracker

/// In-memory fake for tests.
public final class MockSyncSkipTracker: SyncSkipTracker, @unchecked Sendable {

    private var tracked: [String: (id: UUID, count: Int)] = [:]
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func recordSkip(table: String, headRowID: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let existing = tracked[table], existing.id == headRowID {
            let newCount = existing.count + 1
            tracked[table] = (headRowID, newCount)
            return newCount
        }
        tracked[table] = (headRowID, 1)
        return 1
    }

    public func clearSkip(table: String) {
        lock.lock(); defer { lock.unlock() }
        tracked.removeValue(forKey: table)
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        tracked.removeAll()
    }

    /// Test-only accessor — lets a test assert on the count without racing
    /// the actor doing the recording (this is `NSLock`-guarded like every
    /// other read here).
    public func currentCount(forTable table: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return tracked[table]?.count
    }
}
