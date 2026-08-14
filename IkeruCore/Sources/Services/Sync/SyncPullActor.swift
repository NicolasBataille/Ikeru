import Foundation
import SwiftData

/// Background `ModelActor` that pulls remote rows and applies them to the
/// local store, honoring the 4 merge rules from
/// `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.3 — mirrors the
/// `SyncModelActor` pattern (background-thread SwiftData access via
/// `@ModelActor`, per-entity method split, `SyncPayloadBuilder`'s row shape
/// read in reverse) rather than inventing a new isolation strategy.
///
/// ## Table order — and why it's fixed, not incidental
///
/// 1. `profiles` — every other synced row that carries a `profile_id`
///    foreign key needs the local `UserProfile` to exist first.
/// 2. `rpg_states` — depends on `profiles` (attaches via `profile_id`).
/// 3. `cards` — depends on `profiles`. Applied BEFORE `review_logs` because
///    `ReviewLog.init` requires a live local `Card` to attach to (its
///    `card` property is optional, but the initializer parameter is not) —
///    a review log for a card this device has never seen has nowhere to
///    attach. A tombstoned or brand-new card is still created as a shell
///    here so that attachment point exists.
/// 4. `review_logs` — depends on `cards`. Applied before any FSRS replay
///    happens, precisely BECAUSE rule 2 requires the full merged log set
///    to be on disk before replay runs — replaying against a partial log
///    set (e.g. only the just-pulled page, ignoring pre-existing local
///    logs) would silently under-replay.
/// 5. FSRS replay pass, immediately after step 4 — recomputes
///    `fsrsState`/`dueDate`/`interval`/`lapseCount` for every card whose
///    local review-log set changed in this pull OR whose row was just
///    overwritten by a remote win (see `applyCardRows`'s doc comment for
///    why the latter also needs a replay, not just the former).
/// 6. `vocabulary_entries` — standalone (no FK dependency on the above).
/// 7. `vocabulary_encounters` — depends on `vocabulary_entries` (attaches
///    via `entry_id`), same reasoning as review_logs → cards.
/// 8. `exercise_outcome_logs` — standalone (`profileID` is a scalar, not a
///    SwiftData relationship — see that model's doc comment — so no FK
///    ordering constraint applies).
///
/// `companion_chat_messages` is never pulled here, mirroring
/// `SyncModelActor`'s push side, which never pushes it either — see
/// `SyncPayloadBuilder`'s trailing comment. That table needs a separate
/// opt-in (design spec §5.4/§7) that doesn't exist yet; pulling it would
/// leak conversation content onto a device the learner never consented to
/// sync it to.
@ModelActor
actor SyncPullActor {

    /// Rows requested per page. Deliberately larger than `SyncModelActor`'s
    /// 500-row push batch size — `SyncPullTransport`'s doc comment warns
    /// that a single push transaction stamps every row in it with an
    /// IDENTICAL `server_updated_at` (Postgres `now()`, not
    /// `clock_timestamp()`), so a pull page must comfortably exceed the
    /// largest realistic single-push batch or a tie cluster can span two
    /// pages and stall the cursor (see `advancePastFullPage` below).
    static let defaultPageSize = 1000

    /// The 7 tables this actor pulls, in the dependency + merge-rule order
    /// documented on the type. `companion_chat_messages` is excluded — see
    /// the type doc comment.
    static let pullOrder = [
        "profiles",
        "rpg_states",
        "cards",
        "review_logs",
        "vocabulary_entries",
        "vocabulary_encounters",
        "exercise_outcome_logs",
    ]

    // MARK: - Summary

    /// What one `pullAll` call actually did — every field here is something
    /// a caller (or a test) can verify happened, not just a success flag.
    struct PullSummary: Sendable, Equatable {
        /// True when rule 1 fired: the remote account had zero rows across
        /// every pulled table while the local store was non-empty, so
        /// nothing was applied and no cursor moved — the caller's push
        /// (already scheduled to run right after pull in
        /// `CloudSyncCoordinator.syncNow()`) is what seeds the server.
        var seededFromLocal = false

        /// Rows actually applied (created or updated), per table. A table
        /// absent from this dictionary was never queried this cycle only
        /// in the `seededFromLocal` case; otherwise every table in
        /// `pullOrder` has an entry, possibly `0`.
        var appliedRowCounts: [String: Int] = [:]

        /// Cards whose `fsrsState` was recomputed by an FSRS replay this
        /// cycle (rule 2). Exposed so a test can assert convergence
        /// happened, not just that no error was thrown.
        var replayedCardIDs: Set<UUID> = []

        var totalApplied: Int { appliedRowCounts.values.reduce(0, +) }
    }

    enum SyncPullActorError: Error, Sendable, Equatable {
        /// A page came back at exactly `pageSize` rows but the cursor did
        /// not advance past it — the tie-cluster-wider-than-one-page hazard
        /// `SyncPullTransport` warns about. Aborting this table's pagination
        /// loop here (leaving its cursor where it safely still is) is
        /// correct per that type's own guidance: "better to abandon that
        /// page than to spin." The next `pullAll` call re-fetches the same
        /// page and makes the same call — this does not silently lose the
        /// tie cluster, it makes the stall visible instead of hanging.
        case cursorStalledOnFullPage(table: String)
    }

    // MARK: - Entry point

    /// Runs one full pull cycle: rule 1's cold-start guard, then every
    /// table in `pullOrder`, each fully paginated to exhaustion before the
    /// next table starts (so the ordering guarantees in the type doc
    /// comment hold even under pagination).
    func pullAll(
        transport: any SyncPullTransport,
        cursorStore: any SyncCursorStore,
        accessToken: String,
        pageSize: Int = SyncPullActor.defaultPageSize
    ) async throws -> PullSummary {
        var summary = PullSummary()

        // MARK: Rule 1 — cold-start empty-cloud guard
        //
        // Only relevant on a device's VERY FIRST pull ever (no cursor for
        // ANY of the 7 tables) — a device mid-way through its sync history
        // has already proven the server isn't empty by definition of
        // having a cursor. Rather than issuing separate "is it empty?"
        // probe requests (which would race the real pagination for the
        // same page against `MockSyncPullTransport`'s FIFO-per-table queue
        // in tests, silently consuming a page nothing then applies), this
        // fetches the FIRST page of every table exactly once — the same
        // request the pagination loop below would make anyway — and reuses
        // that result either to decide "seed from local" (discard, nothing
        // was applied yet so there's nothing to undo) or to feed directly
        // into the normal apply/paginate path with no page wasted.
        let isColdStart = Self.pullOrder.allSatisfy { cursorStore.cursor(forTable: $0) == nil }
        var primedFirstPages: [String: [SyncRow]] = [:]

        if isColdStart {
            for table in Self.pullOrder {
                primedFirstPages[table] = try await transport.fetchRows(
                    table: table,
                    since: nil,
                    limit: pageSize,
                    accessToken: accessToken
                )
            }
            let remoteIsEmpty = primedFirstPages.values.allSatisfy { $0.isEmpty }
            if remoteIsEmpty {
                let localCount = try localRowCount()
                let decision = SyncMergeRules.seedDecision(
                    remoteRowCount: 0,
                    localRowCount: localCount
                )
                if decision == .seedFromLocal {
                    summary.seededFromLocal = true
                    return summary
                }
                // Both empty (`trustServer` with `localCount == 0`): fall
                // through to the normal path below, which will apply
                // nothing (every primed page is empty) and leave every
                // cursor at `nil` — the next `pullAll` call re-runs this
                // same guard, which is correct: nothing has been decided
                // yet, there is nothing to seed and nothing to trust.
            }
        }

        // MARK: Per-table pull + apply, in dependency order
        //
        // `pendingCardReplayIDs` threads BETWEEN the `cards` and
        // `review_logs` steps deliberately — it is NOT reset per table.
        // `applyCardRows` (the `cards` step) can flag a card as needing a
        // replay (a remote win against a card that already has local
        // review logs) BEFORE `review_logs` has even run this cycle; that
        // candidate must survive into the replay call below, unioned with
        // whatever `review_logs` itself flags, or a remote-won card with no
        // NEWLY-pulled log this cycle would silently keep its pulled
        // (non-authoritative, per rule 2) payload state forever.
        var pendingCardReplayIDs: Set<UUID> = []

        for table in Self.pullOrder {
            let applied = try await pullAndApply(
                table: table,
                transport: transport,
                cursorStore: cursorStore,
                accessToken: accessToken,
                pageSize: pageSize,
                primedFirstPage: primedFirstPages[table],
                pendingCardReplayIDs: &pendingCardReplayIDs
            )
            summary.appliedRowCounts[table] = applied

            if table == "review_logs" {
                // Everything either step could have flagged is now known,
                // and every log either step could depend on is now on disk
                // (this table just finished all its pages, each already
                // saved before its own cursor advanced — see
                // `pullAndApply`) — replay exactly once here, not per-page
                // and not per-table.
                summary.replayedCardIDs = try replayFSRS(forCardIDs: pendingCardReplayIDs)
                pendingCardReplayIDs.removeAll()
                // Persist the replayed card state promptly rather than
                // deferring to the trailing `save()` below — narrows the
                // window in which a crash could leave a card's
                // `fsrsState`/`dueDate` un-replayed after its underlying
                // logs are already durable (the logs themselves are never
                // at risk either way — see `pullAndApply`'s per-page save).
                try modelContext.save()
            }
        }

        // Harmless final flush — every page and the replay step above
        // already saved before its own cursor moved, so this has nothing
        // left to do on the success path. Kept as defensive insurance, not
        // load-bearing for the durability contract itself.
        try modelContext.save()
        return summary
    }

    // MARK: - Per-table pagination

    private func pullAndApply(
        table: String,
        transport: any SyncPullTransport,
        cursorStore: any SyncCursorStore,
        accessToken: String,
        pageSize: Int,
        primedFirstPage: [SyncRow]?,
        pendingCardReplayIDs: inout Set<UUID>
    ) async throws -> Int {
        var totalApplied = 0
        var isFirstIteration = true

        while true {
            let since = cursorStore.cursor(forTable: table)
            let page: [SyncRow]
            if isFirstIteration, let primedFirstPage {
                // Reuse the page already fetched by the rule-1 probe above
                // instead of re-requesting it — see `pullAll`'s comment.
                page = primedFirstPage
            } else {
                page = try await transport.fetchRows(
                    table: table,
                    since: since,
                    limit: pageSize,
                    accessToken: accessToken
                )
            }
            isFirstIteration = false

            guard !page.isEmpty else { break }

            totalApplied += try apply(table: table, rows: page, pendingCardReplayIDs: &pendingCardReplayIDs)

            // MUST save before advancing the cursor, not after — see
            // `SyncCursorStore.setCursor`'s ordering contract doc comment.
            // Advancing first and saving later (previously done once at the
            // very end of `pullAll`) is exactly the "advance-before-apply"
            // failure mode that doc comment calls out: a crash between
            // advancing and the deferred save would leave the cursor past
            // rows that were never actually persisted, and `gte` would skip
            // them forever on the next pull. Mirrors `SyncModelActor`'s
            // per-batch `try modelContext.save()` on the push side.
            try modelContext.save()
            let advanced = cursorStore.advanceCursor(forTable: table, afterApplying: page)

            if page.count < pageSize {
                // Short page: caught up, stop regardless of whether the
                // cursor moved (an all-tied short page is still "done").
                break
            }
            // Full page: more may follow, UNLESS the cursor failed to
            // advance — the tie-cluster-wider-than-one-page hazard
            // `SyncPullTransport` documents. Hard stop per its guidance,
            // rather than re-issuing the identical request forever.
            if advanced == nil {
                throw SyncPullActorError.cursorStalledOnFullPage(table: table)
            }
        }

        return totalApplied
    }

    // MARK: - Row application dispatch

    private func apply(table: String, rows: [SyncRow], pendingCardReplayIDs: inout Set<UUID>) throws -> Int {
        switch table {
        case "profiles":
            return try applyProfileRows(rows)
        case "rpg_states":
            return try applyRPGStateRows(rows)
        case "cards":
            let result = try applyCardRows(rows)
            pendingCardReplayIDs.formUnion(result.needsReplay)
            return result.count
        case "review_logs":
            let result = try applyReviewLogRows(rows)
            pendingCardReplayIDs.formUnion(result.touchedCardIDs)
            return result.count
        case "vocabulary_entries":
            return try applyVocabularyEntryRows(rows)
        case "vocabulary_encounters":
            return try applyVocabularyEncounterRows(rows)
        case "exercise_outcome_logs":
            return try applyExerciseOutcomeLogRows(rows)
        default:
            // Not one of `pullOrder`'s 7 tables — nothing calls `apply`
            // with any other value, so this is unreachable in practice;
            // fail loudly rather than silently dropping unknown rows.
            assertionFailure("SyncPullActor.apply called with unrecognized table: \(table)")
            return 0
        }
    }

    // MARK: - Rule 1 support: local row count

    /// Sum of local rows across the same 7 tables this actor pulls — the
    /// `localRowCount` half of `SyncMergeRules.seedDecision`. Deliberately
    /// NOT counting `CompanionChatMessage`: that table is never pulled or
    /// pushed by this lot (see the type doc comment), so it isn't part of
    /// what "the account has data" means here.
    private func localRowCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<UserProfile>())
            + modelContext.fetchCount(FetchDescriptor<RPGState>())
            + modelContext.fetchCount(FetchDescriptor<Card>())
            + modelContext.fetchCount(FetchDescriptor<ReviewLog>())
            + modelContext.fetchCount(FetchDescriptor<VocabularyEntry>())
            + modelContext.fetchCount(FetchDescriptor<VocabularyEncounter>())
            + modelContext.fetchCount(FetchDescriptor<ExerciseOutcomeLog>())
    }

    // MARK: - profiles

    private struct ProfilePayload: Decodable {
        let displayName: String
        let createdAt: Date
        let settings: ProfileSettings
    }

    private func applyProfileRows(_ rows: [SyncRow]) throws -> Int {
        var applied = 0
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }
            let payload = try SyncRowDecoding.decode(ProfilePayload.self, from: payloadValue)

            if let existing = try fetchOne(UserProfile.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                if winner == .remote {
                    existing.displayName = payload.displayName
                    existing.settings = payload.settings
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
            } else {
                let profile = UserProfile(displayName: payload.displayName, settings: payload.settings)
                profile.id = common.id
                profile.createdAt = payload.createdAt
                profile.updatedAt = common.updatedAt
                profile.deletedAt = common.deletedAt
                profile.syncedAt = common.updatedAt
                modelContext.insert(profile)
            }
            applied += 1
        }
        return applied
    }

    // MARK: - rpg_states

    private struct RPGStatePayload: Decodable {
        let xp: Int
        let level: Int
        let totalReviewsCompleted: Int
        let totalSessionsCompleted: Int
        let currentDailyStreak: Int
        let longestDailyStreak: Int
        let activeDaysCount: Int
        let lastSessionDate: Date?
    }

    private func applyRPGStateRows(_ rows: [SyncRow]) throws -> Int {
        var applied = 0
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }
            let payload = try SyncRowDecoding.decode(RPGStatePayload.self, from: payloadValue)
            let profileID = SyncRowDecoding.uuid(row, "profile_id")

            // Rule 3 applies to the counters regardless of which side's
            // clock is newer — never LWW here. Rule 4 (tombstone) is
            // layered on top for `deletedAt`/`updatedAt` only.
            let remoteCounters = SyncMergeRules.MonotoneCounters(
                xp: payload.xp,
                level: payload.level,
                totalReviewsCompleted: payload.totalReviewsCompleted,
                totalSessionsCompleted: payload.totalSessionsCompleted,
                currentDailyStreak: payload.currentDailyStreak,
                longestDailyStreak: payload.longestDailyStreak,
                activeDaysCount: payload.activeDaysCount,
                lastSessionDate: payload.lastSessionDate
            )

            if let existing = try fetchOne(RPGState.self, id: common.id) {
                mergeRPGState(existing, remoteCounters: remoteCounters, common: common)
            } else if let profileID,
                      let profile = try fetchOne(UserProfile.self, id: profileID),
                      let orphanState = profile.rpgState,
                      (try? fetchOne(RPGState.self, id: orphanState.id)) != nil,
                      orphanState.id != common.id {
                // `UserProfile.init` always mints its own fresh `RPGState`
                // (see that type's initializer). When a profile row was
                // just created earlier in THIS pull (or already existed
                // locally) and the remote `rpg_states` row for it carries a
                // DIFFERENT id, adopting the remote id onto the existing
                // `RPGState` — rather than inserting a second one — avoids
                // orphaning the profile's original state object. An
                // orphaned second `RPGState` would still get swept up by
                // `SyncModelActor.pushAllRPGStates` (which pushes
                // unconditionally, not by delta) and permanently litter the
                // server with a junk row per affected device.
                orphanState.id = common.id
                mergeRPGState(orphanState, remoteCounters: remoteCounters, common: common)
            } else {
                let state = RPGState(
                    xp: remoteCounters.xp,
                    level: remoteCounters.level,
                    totalReviewsCompleted: remoteCounters.totalReviewsCompleted
                )
                state.id = common.id
                state.totalSessionsCompleted = remoteCounters.totalSessionsCompleted
                state.currentDailyStreak = remoteCounters.currentDailyStreak
                state.longestDailyStreak = remoteCounters.longestDailyStreak
                state.activeDaysCount = remoteCounters.activeDaysCount
                state.lastSessionDate = remoteCounters.lastSessionDate
                state.updatedAt = common.updatedAt
                state.deletedAt = common.deletedAt
                state.syncedAt = common.updatedAt
                if let profileID {
                    state.profile = try fetchOne(UserProfile.self, id: profileID)
                }
                modelContext.insert(state)
            }
            applied += 1
        }
        return applied
    }

    private func mergeRPGState(
        _ existing: RPGState,
        remoteCounters: SyncMergeRules.MonotoneCounters,
        common: SyncRowDecoding.CommonFields
    ) {
        let localCounters = SyncMergeRules.MonotoneCounters(
            xp: existing.xp,
            level: existing.level,
            totalReviewsCompleted: existing.totalReviewsCompleted,
            totalSessionsCompleted: existing.totalSessionsCompleted,
            currentDailyStreak: existing.currentDailyStreak,
            longestDailyStreak: existing.longestDailyStreak,
            activeDaysCount: existing.activeDaysCount,
            lastSessionDate: existing.lastSessionDate
        )
        let merged = SyncMergeRules.mergeCounters(local: localCounters, remote: remoteCounters)

        existing.xp = merged.xp
        existing.level = merged.level
        existing.totalReviewsCompleted = merged.totalReviewsCompleted
        existing.totalSessionsCompleted = merged.totalSessionsCompleted
        existing.currentDailyStreak = merged.currentDailyStreak
        existing.longestDailyStreak = merged.longestDailyStreak
        existing.activeDaysCount = merged.activeDaysCount
        existing.lastSessionDate = merged.lastSessionDate

        // Rule 4, layered on top of the rule-3 counter merge: a tombstone
        // from either side wins outright.
        let winner = SyncMergeRules.resolveWinner(
            local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
            remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
        )
        existing.deletedAt = winner == .remote ? common.deletedAt : existing.deletedAt
        // The merged counters are a NEW local truth that may exceed what
        // the server holds (e.g. local was ahead on one field) — but
        // `SyncModelActor.pushAllRPGStates` pushes every row unconditionally
        // every cycle regardless of `updatedAt`/`syncedAt` (see that type's
        // doc comment), so there is no dirty-flag correctness requirement
        // to satisfy here the way there is for `Card`. `updatedAt` is
        // still bumped to the newer of the two clocks for bookkeeping
        // honesty (it should reflect when this row last actually changed).
        existing.updatedAt = max(existing.updatedAt, common.updatedAt)
        existing.syncedAt = common.updatedAt
    }

    // MARK: - cards

    private struct CardPayload: Decodable {
        let front: String
        let back: String
        let type: String
        let fsrsState: FSRSState
        let easeFactor: Double
        let interval: Int
        let dueDate: Date
        let lapseCount: Int
        let leechFlag: Bool
        let jlptLevel: String?
    }

    /// Applies pulled `cards` rows. Returns, alongside the applied count,
    /// the set of card ids that need an FSRS replay pass (rule 2) once
    /// `review_logs` has been fully applied:
    ///
    /// - Every card with at least one LOCAL review log already on disk —
    ///   whether that card was just created, or overwritten by a remote
    ///   win — because the payload's own `fsrsState`/`dueDate`/etc. are
    ///   NOT authoritative per rule 2; only a replay over the full merged
    ///   log set is. Skipping this for a remote-win card would let a
    ///   pulled payload silently override state a fuller local log set
    ///   could derive more correctly, until some later cycle happens to
    ///   re-touch it.
    /// - A card with zero review logs (freshly created, never graded on
    ///   either side) has nothing to replay — its pulled scheduling fields
    ///   are applied as-is, since rule 2 has nothing to arbitrate.
    private func applyCardRows(_ rows: [SyncRow]) throws -> (count: Int, needsReplay: Set<UUID>) {
        var applied = 0
        var needsReplay: Set<UUID> = []
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }
            let payload = try SyncRowDecoding.decode(CardPayload.self, from: payloadValue)
            let profileID = SyncRowDecoding.uuid(row, "profile_id")

            if let existing = try fetchOne(Card.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                if winner == .remote {
                    existing.front = payload.front
                    existing.back = payload.back
                    existing.typeRawValue = payload.type
                    existing.fsrsState = payload.fsrsState
                    existing.easeFactor = payload.easeFactor
                    existing.interval = payload.interval
                    existing.dueDate = payload.dueDate
                    existing.lapseCount = payload.lapseCount
                    existing.leechFlag = payload.leechFlag
                    existing.jlptLevelRawValue = payload.jlptLevel
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
                if existing.deletedAt == nil, !(existing.reviewLogs ?? []).isEmpty {
                    needsReplay.insert(existing.id)
                }
            } else {
                let card = Card(
                    front: payload.front,
                    back: payload.back,
                    type: CardType(rawValue: payload.type) ?? .kanji,
                    fsrsState: payload.fsrsState,
                    easeFactor: payload.easeFactor,
                    interval: payload.interval,
                    dueDate: payload.dueDate,
                    lapseCount: payload.lapseCount,
                    leechFlag: payload.leechFlag,
                    jlptLevel: payload.jlptLevel.flatMap(JLPTLevel.init(rawValue:))
                )
                card.id = common.id
                card.updatedAt = common.updatedAt
                card.deletedAt = common.deletedAt
                card.syncedAt = common.updatedAt
                if let profileID {
                    card.profile = try fetchOne(UserProfile.self, id: profileID)
                }
                modelContext.insert(card)
                // Brand new locally, so it has no local review logs yet —
                // nothing to replay until `review_logs` potentially attaches
                // some to it later in this same pull cycle. `applyReviewLogRows`
                // adds any card it touches to the replay set on its own.
            }
            applied += 1
        }
        return (applied, needsReplay)
    }

    // MARK: - review_logs

    private struct ReviewLogPayload: Decodable {
        let responseTimeMs: Int
    }

    private func applyReviewLogRows(_ rows: [SyncRow]) throws -> (count: Int, touchedCardIDs: Set<UUID>) {
        var applied = 0
        var touchedCardIDs: Set<UUID> = []
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }

            // Append-only per design spec §3 — a review log is never
            // updated after creation, only ever created (or, in principle,
            // tombstoned, though nothing in this codebase does that today —
            // see `ReviewLog`'s doc comment). So unlike every other table,
            // there is no "remote wins, overwrite fields" branch: if it
            // already exists locally, this row is a redelivery (the `gte`
            // pagination boundary, or a re-applied already-seen id from a
            // previous cycle) and applying it again is a safe no-op.
            if try fetchOne(ReviewLog.self, id: common.id) != nil {
                applied += 1
                continue
            }

            guard let cardID = SyncRowDecoding.uuid(row, "card_id"),
                  let card = try fetchOne(Card.self, id: cardID) else {
                // The referenced card doesn't exist locally — shouldn't
                // happen given `cards` is pulled before `review_logs` in
                // `pullOrder`, but a row for a card this device has never
                // synced (e.g. a card later hard-deleted server-side
                // outside this app's own tombstone flow) must not crash
                // the whole pull over one unattachable log. Skipped, not
                // counted as applied.
                continue
            }
            guard let payload = try? SyncRowDecoding.decode(ReviewLogPayload.self, from: payloadValue),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at"),
                  let gradeRaw = SyncRowDecoding.number(row, "grade"),
                  let grade = Grade(rawValue: Int(gradeRaw)) else {
                continue
            }

            let log = ReviewLog(
                card: card,
                grade: grade,
                responseTimeMs: payload.responseTimeMs,
                timestamp: timestamp,
                answeredValue: SyncRowDecoding.string(row, "answered_value"),
                exerciseType: SyncRowDecoding.string(row, "exercise_type"),
                surface: SyncRowDecoding.string(row, "surface")
            )
            log.id = common.id
            log.updatedAt = common.updatedAt
            log.deletedAt = common.deletedAt
            log.syncedAt = common.updatedAt
            modelContext.insert(log)

            if common.deletedAt == nil {
                touchedCardIDs.insert(cardID)
            }
            applied += 1
        }
        return (applied, touchedCardIDs)
    }

    // MARK: - Rule 2: FSRS replay

    /// Replays every card in `cardIDs` from its FULL local `reviewLogs` set
    /// (pre-existing + anything `review_logs` just attached) and writes the
    /// result back — this is what makes two offline devices that graded the
    /// same card converge, per rule 2. A card is left untouched (not even
    /// its `updatedAt` bumped) when the replay result is byte-identical to
    /// what's already stored, so a pull that changes nothing doesn't mark
    /// every touched card dirty for the very next push — avoiding a
    /// pull → push → pull → push ping-pong between two devices that are
    /// actually already converged.
    ///
    /// Returns the subset of `cardIDs` whose state actually changed —
    /// callers/tests can use this to distinguish "replay ran and changed
    /// something" from "replay ran and confirmed nothing needed to change."
    @discardableResult
    private func replayFSRS(forCardIDs cardIDs: Set<UUID>) throws -> Set<UUID> {
        var changed: Set<UUID> = []
        for cardID in cardIDs {
            guard let card = try fetchOne(Card.self, id: cardID), card.deletedAt == nil else { continue }
            // Queried directly against `ReviewLog`, NOT via `card.reviewLogs`
            // relationship traversal: a `ReviewLog` just inserted moments
            // earlier in THIS SAME `review_logs` step (same unsaved
            // `modelContext`, no `save()` between the two) is not reliably
            // reflected yet in an already-faulted to-many relationship
            // array — verified empirically (`SyncPullDivergenceTests`'
            // convergence test failed with exactly one device's log missing
            // from the replay until this was changed to a direct fetch). A
            // fresh `FetchDescriptor<ReviewLog>` query against this context
            // DOES see the same context's own pending inserts (same
            // mechanism `fetchOne` already relies on throughout this file).
            let logs = try modelContext
                .fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.card?.id == cardID }))
                .filter { $0.deletedAt == nil }
            guard let replayed = SyncMergeRules.replayFSRSState(
                logs: logs.map { .init(id: $0.id, timestamp: $0.timestamp, grade: $0.grade) }
            ) else { continue }

            let desiredRetention = clampedDesiredRetention(for: card)
            let referenceNow = replayed.lastReview ?? Date()
            let newDueDate = FSRSService.dueDate(
                for: replayed,
                desiredRetention: desiredRetention,
                now: referenceNow
            )
            let newInterval = max(1, Int(newDueDate.timeIntervalSince(referenceNow) / 86400))

            let unchanged = card.fsrsState == replayed
                && card.lapseCount == replayed.lapses
                && card.interval == newInterval
                && card.dueDate == newDueDate
            if unchanged { continue }

            card.fsrsState = replayed
            card.lapseCount = replayed.lapses
            card.interval = newInterval
            card.dueDate = newDueDate
            // A replay result that differs from what's on disk is a NEW
            // local truth the server hasn't seen (it may only have one
            // device's half of the merged log set) — bump `updatedAt` past
            // `syncedAt` so `SyncModelActor.pushDirtyCards`'s delta filter
            // picks this row up on the push that follows this pull in
            // `CloudSyncCoordinator.syncNow()`, converging the server too.
            card.updatedAt = max(card.updatedAt, referenceNow, Date())
            changed.insert(cardID)
        }
        return changed
    }

    /// Mirrors `CardRepository`'s `activeDesiredRetention()` clamp, scoped
    /// to the specific card's own profile rather than "the active profile"
    /// — this actor has no concept of which profile is active (that's a
    /// `UserDefaults`-backed app-layer notion `CardRepository` reads
    /// separately), and a replay must be correct for whichever profile
    /// actually owns the card being replayed. Falls back to the FSRS
    /// default (0.9) for an orphan card (no `profile` relationship), same
    /// default `CardRepository.activeDesiredRetention()` uses when no
    /// active profile can be resolved at all.
    private func clampedDesiredRetention(for card: Card) -> Double {
        guard let raw = card.profile?.settings.desiredRetention else { return 0.9 }
        return min(max(raw, FSRSService.desiredRetentionRange.lowerBound), FSRSService.desiredRetentionRange.upperBound)
    }

    // MARK: - vocabulary_entries

    private struct VocabularyEntryPayload: Decodable {
        let word: String
        let reading: String
        let meaning: String
        let jlptLevel: String?
        let fsrsState: FSRSState
        let easeFactor: Double
        let interval: Int
        let dueDate: Date
        let lapseCount: Int
        let isInDictionary: Bool
        let createdAt: Date
    }

    /// No rule-2 equivalent here — `VocabularyEntry` has no append-only log
    /// to replay from (see `SyncPayloadBuilder`'s doc comment on that
    /// table), so this is a plain rule-4 (tombstone-aware LWW) apply.
    private func applyVocabularyEntryRows(_ rows: [SyncRow]) throws -> Int {
        var applied = 0
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }
            let payload = try SyncRowDecoding.decode(VocabularyEntryPayload.self, from: payloadValue)

            if let existing = try fetchOne(VocabularyEntry.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                if winner == .remote {
                    existing.word = payload.word
                    existing.reading = payload.reading
                    existing.meaning = payload.meaning
                    existing.jlptLevelRawValue = payload.jlptLevel
                    existing.fsrsState = payload.fsrsState
                    existing.easeFactor = payload.easeFactor
                    existing.interval = payload.interval
                    existing.dueDate = payload.dueDate
                    existing.lapseCount = payload.lapseCount
                    existing.isInDictionary = payload.isInDictionary
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
            } else {
                let entry = VocabularyEntry(
                    word: payload.word,
                    reading: payload.reading,
                    meaning: payload.meaning,
                    jlptLevel: payload.jlptLevel.flatMap(JLPTLevel.init(rawValue:)),
                    isInDictionary: payload.isInDictionary,
                    fsrsState: payload.fsrsState,
                    easeFactor: payload.easeFactor,
                    interval: payload.interval,
                    dueDate: payload.dueDate,
                    lapseCount: payload.lapseCount,
                    createdAt: payload.createdAt
                )
                entry.id = common.id
                entry.updatedAt = common.updatedAt
                entry.deletedAt = common.deletedAt
                entry.syncedAt = common.updatedAt
                modelContext.insert(entry)
            }
            applied += 1
        }
        return applied
    }

    // MARK: - vocabulary_encounters

    private struct VocabularyEncounterPayload: Decodable {
        let source: String
    }

    private func applyVocabularyEncounterRows(_ rows: [SyncRow]) throws -> Int {
        var applied = 0
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }

            // Append-only, same reasoning as `applyReviewLogRows`.
            if try fetchOne(VocabularyEncounter.self, id: common.id) != nil {
                applied += 1
                continue
            }

            guard let entryID = SyncRowDecoding.uuid(row, "entry_id"),
                  let entry = try fetchOne(VocabularyEntry.self, id: entryID) else {
                continue
            }
            guard let payload = try? SyncRowDecoding.decode(VocabularyEncounterPayload.self, from: payloadValue),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at") else {
                continue
            }

            // `contextSnippet` is never pushed (see `SyncPayloadBuilder`'s
            // trailing comment on this table) — a pulled encounter has no
            // snippet to restore, so it's left empty rather than fabricated.
            let encounter = VocabularyEncounter(
                source: EncounterSource(rawValue: payload.source) ?? .sakuraChat,
                contextSnippet: "",
                entry: entry,
                timestamp: timestamp
            )
            encounter.id = common.id
            encounter.updatedAt = common.updatedAt
            encounter.deletedAt = common.deletedAt
            encounter.syncedAt = common.updatedAt
            modelContext.insert(encounter)
            applied += 1
        }
        return applied
    }

    // MARK: - exercise_outcome_logs

    private struct ExerciseOutcomeLogPayload: Decodable {
        let skill: String
        let accuracy: Double
    }

    private func applyExerciseOutcomeLogRows(_ rows: [SyncRow]) throws -> Int {
        var applied = 0
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row) else { continue }
            guard let payloadValue = row["payload"] else { continue }

            // Append-only, same reasoning as `applyReviewLogRows`.
            if try fetchOne(ExerciseOutcomeLog.self, id: common.id) != nil {
                applied += 1
                continue
            }

            guard let profileID = SyncRowDecoding.uuid(row, "profile_id"),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at"),
                  let payload = try? SyncRowDecoding.decode(ExerciseOutcomeLogPayload.self, from: payloadValue) else {
                continue
            }

            let log = ExerciseOutcomeLog(
                skill: SkillType(rawValue: payload.skill) ?? .listening,
                accuracy: payload.accuracy,
                profileID: profileID,
                timestamp: timestamp
            )
            log.id = common.id
            log.updatedAt = common.updatedAt
            log.deletedAt = common.deletedAt
            log.syncedAt = common.updatedAt
            modelContext.insert(log)
            applied += 1
        }
        return applied
    }

    // MARK: - Fetch-by-id helper

    /// Fetches a single instance of `T` by its `id` property. Generic over
    /// every synced `@Model` type in this file — all 7 share the same
    /// `id: UUID` shape (see each model's doc comment), so one helper
    /// serves all of them rather than repeating this fetch 7 times.
    private func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID) throws -> T? where T: SyncIdentifiable {
        let predicate = #Predicate<T> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - SyncIdentifiable

/// Narrow conformance so `SyncPullActor.fetchOne` can write `$0.id == id`
/// inside a `#Predicate` generically — `#Predicate`'s macro expansion needs
/// the `id` property to be visible on the generic type at the call site,
/// which a bare `PersistentModel` constraint doesn't provide.
private protocol SyncIdentifiable {
    var id: UUID { get }
}

extension UserProfile: SyncIdentifiable {}
extension RPGState: SyncIdentifiable {}
extension Card: SyncIdentifiable {}
extension ReviewLog: SyncIdentifiable {}
extension VocabularyEntry: SyncIdentifiable {}
extension VocabularyEncounter: SyncIdentifiable {}
extension ExerciseOutcomeLog: SyncIdentifiable {}

// MARK: - SyncRowDecoding

/// Decodes the fields `SyncPullTransport` returns from a real PostgREST
/// `SELECT *` response — the reverse direction of `SyncPayloadBuilder`
/// (which only ever WRITES a `SyncRow`). Kept private to this file, same
/// scoping choice `SyncCursorTimestampParsing` makes in
/// `SyncCursorStore.swift` for the same underlying reason.
private enum SyncRowDecoding {

    struct CommonFields {
        let id: UUID
        let updatedAt: Date
        let deletedAt: Date?
    }

    enum DecodingError: Error, Sendable {
        case missingField(String)
    }

    /// Every synced row carries `id` and `updated_at` unconditionally, and
    /// `deleted_at` as a nullable column. Throws rather than returning
    /// `nil` so a malformed row (missing/unparseable `id` or `updated_at`)
    /// is distinguishable, at the call site, from "this row is fine but has
    /// no `deleted_at`" — callers that don't care about telling those apart
    /// use `try?`.
    static func common(_ row: SyncRow) throws -> CommonFields {
        guard let id = uuid(row, "id") else { throw DecodingError.missingField("id") }
        guard let updatedAt = date(row, "updated_at") else { throw DecodingError.missingField("updated_at") }
        return CommonFields(id: id, updatedAt: updatedAt, deletedAt: date(row, "deleted_at"))
    }

    static func string(_ row: SyncRow, _ key: String) -> String? {
        guard case .string(let value)? = row[key] else { return nil }
        return value
    }

    static func number(_ row: SyncRow, _ key: String) -> Double? {
        guard case .number(let value)? = row[key] else { return nil }
        return value
    }

    static func uuid(_ row: SyncRow, _ key: String) -> UUID? {
        string(row, key).flatMap(UUID.init(uuidString:))
    }

    static func date(_ row: SyncRow, _ key: String) -> Date? {
        string(row, key).flatMap(SyncPullDateParsing.parse)
    }

    /// Decodes a nested `payload` `JSONValue` object into a typed DTO,
    /// through a LOCAL decoder (`payloadDecoder` below) rather than the
    /// shared `SyncJSON.decoder` — see `SyncPullDateParsing`'s doc comment
    /// for why: `SyncJSON.decoder`'s date strategy only accepts the
    /// always-fractional form this codebase's own encoder writes, and a
    /// real Postgres row can legitimately omit the fraction. Encoding
    /// `value` back through `SyncJSON.encoder` first is safe regardless of
    /// that encoder's date strategy — a `JSONValue` never contains a raw
    /// `Date`, only the already-stringified form, so no date-encoding logic
    /// runs on this leg at all.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try SyncJSON.encoder.encode(value)
        return try payloadDecoder.decode(T.self, from: data)
    }

    private static let payloadDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SyncPullDateParsing.parse(raw) else {
                throw Swift.DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()
}

// MARK: - SyncPullDateParsing

/// Tolerant ISO-8601 parsing for every date this actor reads off the wire —
/// row-level columns (`updated_at`, `deleted_at`, `occurred_at`) AND, via
/// `SyncRowDecoding.payloadDecoder` above, dates nested inside a `payload`
/// object (`dueDate`, `lastReview`, `createdAt`, `lastSessionDate`).
///
/// Duplicated from (not shared with — out of this lot's file perimeter)
/// `SyncCursorStore.swift`'s private `SyncCursorTimestampParsing`, for the
/// exact same empirically-verified reason: real Postgres `to_json` output
/// DROPS the fractional-seconds part entirely for an exact-second
/// timestamp (`"2026-08-14T10:00:00+00:00"`, no decimal point) while
/// `SyncJSON.dateFormatter` is configured `.withFractionalSeconds`-only and
/// returns `nil` on that shape. Every Date field this actor decodes off a
/// real row is exposed to the same hazard `server_updated_at` is — not just
/// the cursor column — so the same two-formatter fallback is needed here
/// too, not only in the cursor store.
private enum SyncPullDateParsing {

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSecond: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? wholeSecond.date(from: raw)
    }
}
