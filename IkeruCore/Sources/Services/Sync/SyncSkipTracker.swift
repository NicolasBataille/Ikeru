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
/// `SyncPullActor` maintains TWO independent counters per table, not one
/// (2026-08 lot-2 pull review, round 4 — see `RowApplyOutcome`'s doc
/// comment for the full story):
///
/// - `recordSkip`/`poisonDropThreshold` (3 cycles) for a row stuck for a
///   PERMANENT reason — an undecodable payload. Nothing about waiting
///   longer can ever fix that, so the threshold stays tight.
/// - `recordTransientSkip`/`transientPoisonDropThreshold` (50 cycles) for a
///   row stuck for a TRANSIENT reason — an unresolved foreign key whose
///   parent row hasn't arrived yet, which is expected to self-heal. Using
///   the tight 3-cycle threshold here used to force-drop review logs and
///   vocabulary encounters that were only ever waiting on a parent delayed
///   by something else (e.g. that parent's OWN poison-row recovery, which
///   can itself take up to 3 cycles) — real, previously-shipped data loss,
///   not a hypothetical.
///
/// Either counter force-advances the cursor past its row once its own
/// threshold is reached (safe, precise, and collateral-free specifically
/// BECAUSE the cursor is a composite `(timestamp, id)` keyset — see
/// `SyncCursorPosition` — rather than the single `Date` this lot shipped
/// with first, which could only skip an entire tie cluster at once), counts
/// the row as permanently dropped, and logs it.
///
/// Persisted the same way the cursor itself is (`UserDefaultsSyncSkipTracker`
/// mirrors `UserDefaultsSyncCursorStore`) rather than kept purely in-memory:
/// strikes need to survive an app relaunch between sync cycles, or a
/// learner who only foregrounds the app once a day would effectively never
/// accumulate them.
public protocol SyncSkipTracker: Sendable {

    /// Records one more cycle stuck on `headRowID` for `table` for a
    /// PERMANENT reason (an undecodable payload — see `RowApplyOutcome`).
    /// If a DIFFERENT id was tracked for this table before (or nothing
    /// was), the count resets to 1 — a new stuck candidate, not a
    /// continuation of the old one. Returns the new count. Tracked
    /// separately from `recordTransientSkip` — the two must never share a
    /// counter, see the type doc comment.
    @discardableResult
    func recordSkip(table: String, headRowID: UUID) -> Int

    /// Same bookkeeping as `recordSkip`, but for a row stuck for a
    /// TRANSIENT reason (an unresolved foreign key — see
    /// `RowApplyOutcome`). Tracked under an entirely separate counter so a
    /// transient block can never consume a strike toward `recordSkip`'s
    /// tight 3-cycle drop threshold, yet still needs SOME bound of its own
    /// — a parent row that never arrives (e.g. it was itself permanently
    /// dropped upstream) would otherwise pin this table's cursor forever,
    /// reopening this lot's original Critical A finding from the transient
    /// side.
    @discardableResult
    func recordTransientSkip(table: String, headRowID: UUID) -> Int

    /// Clears BOTH counters tracked for `table` — called once a cycle makes
    /// full progress on it (nothing stuck this time, so whatever stall
    /// happened before, permanent or transient, has self-healed) or once a
    /// row has been forcibly dropped by either counter, so the NEXT stuck
    /// row (if any) starts counting at 1 on both, not wherever the dropped
    /// row's counts left off.
    func clearSkip(table: String)

    /// Clears every table's tracked state, both counters. MUST be called
    /// everywhere `SyncCursorStore.resetAll()` is — consent revocation,
    /// account deletion, a pending cursor reset applied at the end of an
    /// in-flight cycle — see `SyncCursorStore.resetAll()`'s doc comment for
    /// why a stale strike count surviving a cursor reset is a real hazard,
    /// not just untidy state: a brand-new (or freshly re-provisioned)
    /// account's row could otherwise inherit strikes from a completely
    /// unrelated previous account and get dropped on its very first genuine
    /// stall.
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

    /// The TRANSIENT-reason counterpart of `headIDKey`/`countKey` — a
    /// separate key pair (not a shared one) so the permanent and transient
    /// strike counts can never clobber each other. Still under the shared
    /// `keyPrefix`, so `resetAll()`'s prefix sweep clears both without
    /// needing its own update.
    public static func transientHeadIDKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).transientHeadID"
    }

    public static func transientCountKey(forTable table: String) -> String {
        "\(keyPrefix)\(table).transientCount"
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
        recordSkip(
            headRowID: headRowID,
            idKey: SyncSkipTrackerPreferences.headIDKey(forTable: table),
            countKey: SyncSkipTrackerPreferences.countKey(forTable: table)
        )
    }

    @discardableResult
    public func recordTransientSkip(table: String, headRowID: UUID) -> Int {
        recordSkip(
            headRowID: headRowID,
            idKey: SyncSkipTrackerPreferences.transientHeadIDKey(forTable: table),
            countKey: SyncSkipTrackerPreferences.transientCountKey(forTable: table)
        )
    }

    /// Shared bookkeeping for both counters — `recordSkip`/`recordTransientSkip`
    /// differ only in WHICH key pair they read/write.
    private func recordSkip(headRowID: UUID, idKey: String, countKey: String) -> Int {
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
        defaults.removeObject(forKey: SyncSkipTrackerPreferences.transientHeadIDKey(forTable: table))
        defaults.removeObject(forKey: SyncSkipTrackerPreferences.transientCountKey(forTable: table))
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
    private var transientTracked: [String: (id: UUID, count: Int)] = [:]
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

    @discardableResult
    public func recordTransientSkip(table: String, headRowID: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let existing = transientTracked[table], existing.id == headRowID {
            let newCount = existing.count + 1
            transientTracked[table] = (headRowID, newCount)
            return newCount
        }
        transientTracked[table] = (headRowID, 1)
        return 1
    }

    public func clearSkip(table: String) {
        lock.lock(); defer { lock.unlock() }
        tracked.removeValue(forKey: table)
        transientTracked.removeValue(forKey: table)
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        tracked.removeAll()
        transientTracked.removeAll()
    }

    /// Test-only accessor — lets a test assert on the PERMANENT count
    /// without racing the actor doing the recording (this is
    /// `NSLock`-guarded like every other read here).
    public func currentCount(forTable table: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return tracked[table]?.count
    }

    /// Test-only accessor for the TRANSIENT count — mirrors `currentCount`.
    public func currentTransientCount(forTable table: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return transientTracked[table]?.count
    }
}
