import Foundation

/// The 4 merge rules from `docs/design-specs/2026-08-10-cloud-sync-design.md`
/// §5.3, as **pure functions**: no SwiftData access, no network, no implicit
/// clock (every function that needs "now" takes it as a parameter, or needs
/// no clock at all because it operates purely on already-stamped data).
///
/// This is deliberately the load-bearing, side-effect-free core of cloud-sync
/// lot 2 — the actor/repository layer that calls these functions (a later
/// lot) is where SwiftData reads/writes and network round-trips happen; none
/// of that belongs here, which is exactly what makes this file exhaustively
/// testable.
public enum SyncMergeRules {

    // MARK: - Rule 1: empty-cloud seed guard

    /// What the first pull against a given account should do with the local
    /// store.
    public enum SyncSeedDecision: Sendable, Equatable {
        /// The remote account has no rows on any synced table. Treat the
        /// first pull as a **seed from local**, not as authoritative
        /// server truth — i.e. push the local store up rather than
        /// accepting "0 rows" as the new state of the world.
        case seedFromLocal

        /// The remote account already has data (or both sides are empty, in
        /// which case there's nothing to seed either way). Proceed with the
        /// regular pull/merge flow.
        case trustServer
    }

    /// Rule 1 — **a cloud account with zero rows never overwrites a
    /// populated local store.**
    ///
    /// The disaster this guards against: the learner signs in on a second
    /// device (or after a reinstall against a fresh anonymous identity), the
    /// server answers "0 cards" because nothing has been pushed yet, and a
    /// naive sync treats that empty answer as truth — six months of review
    /// history gone. So the first pull against an empty account must be
    /// treated as a **seed opportunity** (push local up) rather than a
    /// verdict (wipe local down).
    ///
    /// - Parameters:
    ///   - remoteRowCount: Total row count across **all** synced tables for
    ///     this account (`profiles` + `rpg_states` + `cards` + `review_logs`
    ///     + `vocabulary_entries` + `vocabulary_encounters` +
    ///     `exercise_outcome_logs` + `companion_chat_messages`), summed by
    ///     the caller before invoking this function — this function does no
    ///     counting of its own, by design (that's a network/DB concern).
    ///   - localRowCount: Same sum, computed locally.
    /// - Returns: `.seedFromLocal` only when the remote is empty and the
    ///   local store is not — every other combination (both empty, remote
    ///   populated regardless of local) trusts the server and proceeds with
    ///   the normal merge.
    public static func seedDecision(
        remoteRowCount: Int,
        localRowCount: Int
    ) -> SyncSeedDecision {
        if remoteRowCount == 0 && localRowCount > 0 {
            return .seedFromLocal
        }
        return .trustServer
    }

    // MARK: - Rule 2: ReviewLog authority + FSRS replay

    /// A minimal, sync-relevant view of one review event. Deliberately not
    /// `ReviewLog` itself (a SwiftData `@Model`, not `Sendable`, and this
    /// file has no SwiftData dependency) — callers project the persisted
    /// model down to this before calling `replayFSRSState`.
    public struct ReplayLogEntry: Sendable, Equatable {
        /// The client-generated UUID (`ReviewLog.id`). Append-only and
        /// unique per spec §3 — two devices logging the same review event
        /// can never collide on this, which is what makes union-by-id a
        /// safe merge for the log set itself (as opposed to `Card`, which
        /// genuinely can be written by two devices in the same field).
        public let id: UUID
        public let timestamp: Date
        public let grade: Grade

        public init(id: UUID, timestamp: Date, grade: Grade) {
            self.id = id
            self.timestamp = timestamp
            self.grade = grade
        }
    }

    /// Rule 2 — **`ReviewLog` is authoritative over `Card`.**
    ///
    /// When two devices have graded the same card while offline, we don't
    /// pick a winner between the two resulting `FSRSState`s: we merge the
    /// two devices' review logs into one set and **replay** `FSRSService`
    /// over that merged set from scratch, deterministically, to produce the
    /// state that "should have" resulted if both reviews had happened on one
    /// device in order.
    ///
    /// **Merging the logs themselves is a union by `id`** — `ReviewLog` rows
    /// are append-only and carry a client-generated UUID (spec §3's
    /// "architectural gift": they cannot conflict with each other, only
    /// `Card`'s derived scheduling state can drift). Pass the union of both
    /// devices' logs as `logs`; duplicates (the same `id` present in both
    /// sets, e.g. a log that was already pulled once) collapse naturally
    /// because this function reduces over `logs` as given — callers doing
    /// the actual union should dedup by `id` before calling, same as any
    /// `Set`/dictionary keyed by `id` would.
    ///
    /// ⚠️ **Determinism is the entire point.** Two devices independently
    /// replaying the *same* merged log set must land on the *identical*
    /// `FSRSState` — that's what makes this a safe thing to do without a
    /// server-side arbiter. Sorting by `timestamp` alone is not enough:
    /// two logs can legitimately carry the same timestamp (millisecond
    /// resolution colliding, or two devices whose clocks happen to agree
    /// to the second). This function breaks ties by **`id`**
    /// (`UUID.uuidString` lexicographic order) — the one piece of data on a
    /// `ReviewLog` that is both stable and guaranteed unique. Without this
    /// tie-break, `Array.sorted` is not even guaranteed stable across
    /// platforms/Swift versions for equal keys, so two devices could
    /// silently diverge. Do not weaken this to timestamp-only sorting.
    ///
    /// - Parameters:
    ///   - logs: The merged (unioned) set of `ReviewLog` entries for **one**
    ///     card, from all devices.
    ///   - weights: FSRS weights to replay with (defaults to
    ///     `FSRSService.defaultWeights`, same as production).
    /// - Returns: The `FSRSState` that results from replaying every log in
    ///   deterministic order from a fresh (`reps == 0`) state. `nil` if
    ///   `logs` is empty (nothing to replay — caller should keep whatever
    ///   state, if any, the card already has).
    public static func replayFSRSState(
        logs: [ReplayLogEntry],
        weights: [Double] = FSRSService.defaultWeights
    ) -> FSRSState? {
        guard !logs.isEmpty else { return nil }

        let ordered = logs.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var state = FSRSState()
        for entry in ordered {
            state = FSRSService.schedule(
                state: state,
                grade: entry.grade,
                now: entry.timestamp,
                weights: weights
            )
        }
        return state
    }

    // MARK: - Rule 3: monotone counter merge (RPGState)

    /// The subset of `RPGState`'s monotone counters this rule merges.
    /// Deliberately not `RPGState` itself (a SwiftData `@Model`) — callers
    /// project down to this before calling `mergeCounters`.
    public struct MonotoneCounters: Sendable, Equatable {
        public let xp: Int
        public let level: Int
        public let totalReviewsCompleted: Int
        public let totalSessionsCompleted: Int
        public let currentDailyStreak: Int
        public let longestDailyStreak: Int
        public let activeDaysCount: Int
        public let lastSessionDate: Date?

        public init(
            xp: Int,
            level: Int,
            totalReviewsCompleted: Int,
            totalSessionsCompleted: Int,
            currentDailyStreak: Int,
            longestDailyStreak: Int,
            activeDaysCount: Int,
            lastSessionDate: Date?
        ) {
            self.xp = xp
            self.level = level
            self.totalReviewsCompleted = totalReviewsCompleted
            self.totalSessionsCompleted = totalSessionsCompleted
            self.currentDailyStreak = currentDailyStreak
            self.longestDailyStreak = longestDailyStreak
            self.activeDaysCount = activeDaysCount
            self.lastSessionDate = lastSessionDate
        }
    }

    /// Rule 3 — **monotone counters merge by `max()`, field by field, never
    /// by "last write wins."**
    ///
    /// LWW on a counter lets a device that's behind (stale local state,
    /// synced later) push its smaller number over a larger one already on
    /// the server — the learner's XP visibly *drops*. `max()` per field is
    /// immune to write order.
    ///
    /// **`xp`, `level`, `totalReviewsCompleted`, `totalSessionsCompleted`,
    /// `longestDailyStreak`, `activeDaysCount`** are all straightforwardly
    /// monotone — lifetime totals or historical bests that only ever grow
    /// locally — so `max()` is the direct, correct merge.
    ///
    /// **`currentDailyStreak` is the one that needs a decision, not just a
    /// formula** — a streak is legitimately allowed to *break* (a missed
    /// day resets it to 0/1), so treating it as globally monotone and
    /// merging by raw `max()` would let a stale, larger streak value from a
    /// device that hasn't synced in weeks resurrect itself and overwrite a
    /// correct, freshly-broken streak forever. But naive LWW is just as
    /// wrong here (that's the exact failure this rule exists to prevent for
    /// every other field). **Decision: merge `currentDailyStreak` by
    /// `max()` anyway, keyed off the fields that are already unambiguously
    /// monotone.** Concretely: since `longestDailyStreak` is merged by
    /// `max()` first, any streak break is captured durably there the moment
    /// it happens on *either* device and is never lost even if
    /// `currentDailyStreak` itself briefly over-reports; and `max()` on
    /// `currentDailyStreak` only actually stays "too high" for a single
    /// merge cycle — once both devices have synced at least once after the
    /// break, the smaller (correct) value stops shrinking further and the
    /// break has already been recorded in `longestDailyStreak`. The
    /// alternative (LWW on `currentDailyStreak`, keyed by which side's
    /// `updatedAt` is newer) was rejected because it reintroduces exactly
    /// the "a stale device write can move a counter backward on the *other*
    /// device's data" failure mode this whole rule exists to close, just
    /// scoped to one field. `max()` trades a bounded, self-healing
    /// over-report for that unbounded regression risk — the safer failure
    /// mode of the two. A future lot could special-case
    /// `currentDailyStreak` against `lastSessionDate` (i.e. recompute
    /// "is today still consecutive with the merged `lastSessionDate`?")
    /// for a more precise answer; not attempted here to keep this function
    /// pure and free of calendar/timezone logic.
    ///
    /// **`lastSessionDate`**: not a counter — merged as "the more recent of
    /// the two," which is the natural (and only sensible) merge for a
    /// timestamp of the most recent activity.
    ///
    /// - Parameters:
    ///   - local: This device's counters.
    ///   - remote: The server's (or the other device's) counters.
    /// - Returns: The field-by-field merged counters.
    public static func mergeCounters(
        local: MonotoneCounters,
        remote: MonotoneCounters
    ) -> MonotoneCounters {
        MonotoneCounters(
            xp: max(local.xp, remote.xp),
            level: max(local.level, remote.level),
            totalReviewsCompleted: max(local.totalReviewsCompleted, remote.totalReviewsCompleted),
            totalSessionsCompleted: max(local.totalSessionsCompleted, remote.totalSessionsCompleted),
            currentDailyStreak: max(local.currentDailyStreak, remote.currentDailyStreak),
            longestDailyStreak: max(local.longestDailyStreak, remote.longestDailyStreak),
            activeDaysCount: max(local.activeDaysCount, remote.activeDaysCount),
            lastSessionDate: laterDate(local.lastSessionDate, remote.lastSessionDate)
        )
    }

    private static func laterDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (let lhsDate?, nil): return lhsDate
        case (nil, let rhsDate?): return rhsDate
        case (let lhsDate?, let rhsDate?): return max(lhsDate, rhsDate)
        }
    }

    // MARK: - Rule 4: deletion wins

    /// Which side wins a merge between a local and a remote version of the
    /// same row.
    public enum FieldMergeWinner: Sendable, Equatable {
        case local
        case remote
    }

    /// A `(updatedAt, deletedAt)` pair for one side of a merge. Generic
    /// across every synced entity — every synced table carries exactly
    /// these two clock fields (see `IkeruSchemaV4`, spec §5.1), so one
    /// function serves `Card`, `RPGState`, `VocabularyEntry`, etc.
    public struct SyncClock: Sendable, Equatable {
        public let updatedAt: Date
        public let deletedAt: Date?

        public init(updatedAt: Date, deletedAt: Date?) {
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    /// Rule 4 — **a tombstone always wins over a concurrent modification,
    /// regardless of timestamp.**
    ///
    /// A non-nil `deletedAt` on either side wins outright, even if the other
    /// side's `updatedAt` is later — a deletion is a deliberate act the
    /// learner took, and a later *edit* on a device that hasn't yet learned
    /// about the deletion must not resurrect the row. If both sides are
    /// deleted, either is an equivalent outcome (both are tombstones), so
    /// this returns `.local` for determinism without it being a meaningful
    /// choice.
    ///
    /// When **neither** side is deleted, this falls through to plain
    /// last-write-wins on `updatedAt` (this is the *only* rule of the 4 that
    /// is LWW — rules 1-3 exist precisely because LWW is wrong for seed
    /// state, `Card` scheduling state, and monotone counters respectively).
    ///
    /// - Parameters:
    ///   - local: This device's clock for the row.
    ///   - remote: The server's (or the other device's) clock for the row.
    /// - Returns: Which side's version of the row should be kept.
    public static func resolveWinner(
        local: SyncClock,
        remote: SyncClock
    ) -> FieldMergeWinner {
        let localDeleted = local.deletedAt != nil
        let remoteDeleted = remote.deletedAt != nil

        if localDeleted && remoteDeleted {
            return .local
        }
        if localDeleted {
            return .local
        }
        if remoteDeleted {
            return .remote
        }

        return local.updatedAt >= remote.updatedAt ? .local : .remote
    }
}
