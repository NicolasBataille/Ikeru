import Foundation
import SwiftData
import os

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
/// 9. `text_imports` — standalone for the same reason: a `TextImport`'s
///    link to the vocabulary it produced is a scalar `entryIDs` array, not a
///    SwiftData relationship (see that model's doc comment for why the link
///    lives on this side), so nothing here has to arrive after anything else.
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

    /// After this many CONSECUTIVE cycles stuck on the exact same
    /// head-of-line row for a PERMANENT reason (`RowApplyOutcome.skippedPermanent`
    /// — an undecodable payload), that row is force-abandoned rather than
    /// retried forever — see `SyncSkipTracker`'s doc comment for the full
    /// rationale. 3 is deliberately small: a permanent skip reason cannot
    /// self-heal by waiting, so there is nothing to gain from a wider
    /// threshold — only a delay in making an unrecoverable problem visible.
    ///
    /// ⚠️ Does NOT apply to a TRANSIENT skip reason (an unresolved foreign
    /// key — `RowApplyOutcome.skippedTransient`) — that case is governed by
    /// the separate, much wider `transientPoisonDropThreshold` below. The
    /// two used to share this one counter/threshold (2026-08 lot-2 pull
    /// review, round 4 finding): "wait for a card that hasn't arrived yet"
    /// usually resolves within a cycle or two, since `cards` is pulled
    /// before `review_logs` every cycle — but not always within exactly 3,
    /// e.g. when the card itself is delayed behind an unrelated poison row
    /// that needs its own 3 cycles to be force-dropped first. Sharing the
    /// tight threshold force-abandoned real review history for rows that
    /// were only ever waiting, not actually unrecoverable.
    static let poisonDropThreshold = 3

    /// The TRANSIENT-reason counterpart of `poisonDropThreshold` — see that
    /// constant's doc comment and `RowApplyOutcome` for the full story. Much
    /// wider than 3 specifically because a transient block is EXPECTED to
    /// resolve on its own; this threshold exists only as a backstop against
    /// a parent row that never arrives at all (e.g. it was itself
    /// permanently dropped upstream, or a data-integrity issue server-side
    /// means it never will) — without SOME bound here, that case would pin
    /// this table's cursor forever, reopening this lot's original Critical A
    /// finding from the transient side. 50 is chosen as generous enough to
    /// absorb several rounds of an upstream permanent-drop recovery (3
    /// cycles each) with a wide margin, while still guaranteeing the pull
    /// cursor cannot stall indefinitely on a truly-never-arriving parent.
    static let transientPoisonDropThreshold = 50

    /// The 8 tables this actor pulls, in the dependency + merge-rule order
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
        "text_imports",
    ]

    // MARK: - Summary

    /// What one `pullAll` call actually did — every field here is something
    /// a caller (or a test) can verify happened, not just a success flag.
    struct PullSummary: Sendable, Equatable {
        /// True when rule 1 fired: the remote account had zero rows across
        /// every pulled table while the local store was non-empty, so
        /// nothing was applied and no cursor moved.
        ///
        /// The push that follows right after in
        /// `CloudSyncCoordinator.syncNow()` is what seeds the server in
        /// this case — but that claim is only actually true because
        /// `syncNow()` calls `SyncModelActor.markEverythingUnsynced()`
        /// FIRST when it sees this flag (see that method's doc comment).
        /// Without that call, a device whose local rows still carry
        /// `syncedAt` from a PREVIOUS, since-deleted server-side account
        /// (e.g. after `CloudDataDeletionService.deleteAllCloudData()`, or
        /// a rejected refresh token silently re-provisioning a brand-new
        /// anonymous identity — see `AnonymousIdentityManager`) would have
        /// every delta-filtered `pushDirty*` call see those rows as
        /// already synced and push NOTHING for them — only
        /// `profiles`/`rpg_states` (pushed unconditionally every cycle)
        /// would actually reach the new, empty account, while
        /// cards/logs/vocabulary silently stayed local-only. This was a
        /// real, previously-shipped defect (CRITIQUE B in the 2026-08
        /// lot-2 pull review), not a hypothetical this comment is
        /// pre-emptively guarding against.
        var seededFromLocal = false

        /// Rows newly CREATED locally this cycle, per table — a row this
        /// device had never seen before. A table absent from this
        /// dictionary was never queried this cycle only in the
        /// `seededFromLocal` case; otherwise every table in `pullOrder`
        /// has an entry, possibly `0`. Deliberately EXCLUDES redelivered
        /// rows on the 3 append-only tables (`review_logs`,
        /// `vocabulary_encounters`, `exercise_outcome_logs`) — see
        /// `alreadyPresentRowCounts` for those; folding them in here used
        /// to overstate how much work a cycle actually did (a table
        /// endlessly re-fetching the same already-applied boundary row
        /// from a `gte` cursor looked exactly as "busy" as one making real
        /// progress).
        var appliedRowCounts: [String: Int] = [:]

        /// Rows fetched but SKIPPED per table this cycle — a decode
        /// failure (unparseable payload, missing required field) or an
        /// unattachable foreign key (e.g. a `review_logs` row whose `card`
        /// no longer exists locally). Distinct from `appliedRowCounts`
        /// specifically so a pull that silently discards half a page is
        /// distinguishable from a clean one. A skipped row is normally
        /// retried on every future cycle until it succeeds — UNLESS it's
        /// also counted in `permanentlyDroppedRowCounts` below, in which
        /// case this cycle was its last retry.
        var skippedRowCounts: [String: Int] = [:]

        /// Append-only rows (see the 3 tables named on `appliedRowCounts`)
        /// that were fetched again but were ALREADY durably present
        /// locally — a safe, expected no-op redelivery (the keyset cursor
        /// boundary row, or a page re-sent after a crash between apply and
        /// cursor-advance), not new work. Kept distinct from
        /// `appliedRowCounts` so a table quietly re-fetching its own
        /// boundary forever doesn't read as "very active" to anything
        /// diagnosing this summary.
        var alreadyPresentRowCounts: [String: Int] = [:]

        /// Rows force-abandoned this cycle after `poisonDropThreshold`
        /// (PERMANENT skip reason) or `transientPoisonDropThreshold`
        /// (TRANSIENT skip reason) consecutive cycles stuck on the same
        /// row — see `SyncSkipTracker`'s and `RowApplyOutcome`'s doc
        /// comments for why the two reasons use different thresholds. Also
        /// counted in `skippedRowCounts` for the cycle they're dropped on
        /// (they WERE skipped, this is just the cycle retrying stops), but
        /// unlike an ordinary skip they will never be retried again: the
        /// cursor was deliberately advanced past them.
        var permanentlyDroppedRowCounts: [String: Int] = [:]

        /// Cards whose `fsrsState` was recomputed by an FSRS replay this
        /// cycle (rule 2). Exposed so a test can assert convergence
        /// happened, not just that no error was thrown.
        var replayedCardIDs: Set<UUID> = []

        var totalApplied: Int { appliedRowCounts.values.reduce(0, +) }
        var totalSkipped: Int { skippedRowCounts.values.reduce(0, +) }
        var totalPermanentlyDropped: Int { permanentlyDroppedRowCounts.values.reduce(0, +) }
    }

    enum SyncPullActorError: Error, Sendable, Equatable {
        /// A page came back at exactly `pageSize` rows, every row in it
        /// applied successfully, and the cursor STILL failed to make
        /// forward progress against it.
        ///
        /// With the composite `(server_updated_at, id)` cursor
        /// (`SyncCursorPosition`) this is now an anomaly guard, not the
        /// routine hazard it used to be under the earlier single-`Date`
        /// cursor design: a tie cluster wider than one page no longer
        /// stalls anything (every row's `id` gives it a unique position),
        /// and a genuinely unrecoverable ("poison") row is handled by
        /// `SyncSkipTracker`'s 3-strikes policy — which runs BEFORE this
        /// check is ever reached, and never throws. The only way this
        /// still fires is the residual case where every row in the page
        /// applied fine but their OWN `server_updated_at`/`id` (a pair
        /// `advanceCursor` reads independently of whatever `apply` needed
        /// to succeed) is missing or unparseable across the entire prefix
        /// — a shape that should not occur in practice. Kept as a loud
        /// last-resort signal rather than removed outright, per this
        /// project's "fail loudly, not silently" stance.
        ///
        /// `pullAll`'s per-table loop catches this (see there) rather than
        /// letting it propagate — a stall on ONE table must not take every
        /// table after it in `pullOrder` down with it. That used to be
        /// exactly what happened here (a previous review round's Critical
        /// A finding): this error propagating straight out of `pullAll`
        /// meant a stall on, say, `cards` silently meant `review_logs`
        /// through `text_imports` were never even queried that
        /// cycle. The `…SoFar` payloads let the catcher salvage what this
        /// table actually accomplished before the stall rather than
        /// reporting `0` for a table that may have applied several pages
        /// first.
        case cursorStalledOnFullPage(
            table: String,
            appliedSoFar: Int,
            skippedSoFar: Int,
            alreadyPresentSoFar: Int,
            permanentlyDroppedSoFar: Int
        )
    }

    // MARK: - Entry point

    /// Runs one full pull cycle: rule 1's cold-start guard, then every
    /// table in `pullOrder`, each fully paginated to exhaustion before the
    /// next table starts (so the ordering guarantees in the type doc
    /// comment hold even under pagination).
    func pullAll(
        transport: any SyncPullTransport,
        cursorStore: any SyncCursorStore,
        skipTracker: any SyncSkipTracker,
        accessToken: String,
        pageSize: Int = SyncPullActor.defaultPageSize
    ) async throws -> PullSummary {
        var summary = PullSummary()

        // MARK: Rule 1 — cold-start empty-cloud guard
        //
        // Only relevant on a device's VERY FIRST pull ever (no cursor for
        // ANY of the 8 tables) — a device mid-way through its sync history
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
            let applied: Int
            let skipped: Int
            let alreadyPresent: Int
            let permanentlyDropped: Int
            do {
                (applied, skipped, alreadyPresent, permanentlyDropped) = try await pullAndApply(
                    table: table,
                    transport: transport,
                    cursorStore: cursorStore,
                    skipTracker: skipTracker,
                    accessToken: accessToken,
                    pageSize: pageSize,
                    primedFirstPage: primedFirstPages[table],
                    pendingCardReplayIDs: &pendingCardReplayIDs
                )
            } catch let error as SyncPullActorError {
                // See `SyncPullActorError.cursorStalledOnFullPage`'s doc
                // comment: this table's anomaly must not silently take
                // every table after it in `pullOrder` down with it
                // (Critical A). Salvage whatever this table accomplished
                // before the stall and move on to the next table exactly
                // as if this one had simply run out of pages.
                switch error {
                case .cursorStalledOnFullPage(_, let appliedSoFar, let skippedSoFar, let alreadyPresentSoFar, let droppedSoFar):
                    Logger.sync.error(
                        "Cloud sync pull: \(table, privacy: .public) stalled (anomaly guard, see SyncPullActorError) — continuing with the next table"
                    )
                    applied = appliedSoFar
                    skipped = skippedSoFar
                    alreadyPresent = alreadyPresentSoFar
                    permanentlyDropped = droppedSoFar
                }
            }
            summary.appliedRowCounts[table] = applied
            summary.skippedRowCounts[table] = skipped
            summary.alreadyPresentRowCounts[table] = alreadyPresent
            summary.permanentlyDroppedRowCounts[table] = permanentlyDropped

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
        skipTracker: any SyncSkipTracker,
        accessToken: String,
        pageSize: Int,
        primedFirstPage: [SyncRow]?,
        pendingCardReplayIDs: inout Set<UUID>
    ) async throws -> (applied: Int, skipped: Int, alreadyPresent: Int, permanentlyDropped: Int) {
        var totalApplied = 0
        var totalSkipped = 0
        var totalAlreadyPresent = 0
        var totalPermanentlyDropped = 0
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

            guard !page.isEmpty else {
                // Caught up on this table — whatever was tracked as a
                // stuck candidate before (if anything) is moot now.
                skipTracker.clearSkip(table: table)
                break
            }

            let (appliedCount, outcomes, alreadyPresentCount) = try apply(
                table: table,
                rows: page,
                pendingCardReplayIDs: &pendingCardReplayIDs
            )
            totalApplied += appliedCount
            totalAlreadyPresent += alreadyPresentCount
            totalSkipped += page.count - appliedCount - alreadyPresentCount

            // MUST save before advancing the cursor, not after — see
            // `SyncCursorStore.setCursor`'s ordering contract doc comment.
            // Advancing first and saving later (previously done once at the
            // very end of `pullAll`) is exactly the "advance-before-apply"
            // failure mode that doc comment calls out: a crash between
            // advancing and the deferred save would leave the cursor past
            // rows that were never actually persisted, and the keyset
            // filter would skip them forever on the next pull. Mirrors
            // `SyncModelActor`'s per-batch `try modelContext.save()` on the
            // push side.
            try modelContext.save()

            // Advance the cursor over the PREFIX of `page` that was
            // actually applied — NOT over the whole page. A row skipped
            // mid-page (failed decode, unattachable FK, …) is still
            // counted in `outcomes` as `.skippedPermanent`/`.skippedTransient`;
            // if the cursor were allowed to jump past it to the max
            // position across the WHOLE page — including rows applied
            // AFTER the skipped one — the next cycle would start strictly
            // past the skipped row and it would never be redelivered,
            // silently and permanently. `page` is sorted
            // `server_updated_at.asc, id.asc` (see `SyncPullTransport`'s
            // doc comment), so `prefix(while:)` from the start is the
            // longest run this cycle can safely certify as durable; the
            // skipped row (and everything after it, even rows that
            // themselves applied fine) waits for the next cycle, which
            // re-fetches from the skipped row's own position and
            // re-delivers those later rows too — a safe no-op upsert for
            // the ones already applied here.
            let appliedPrefix = zip(page, outcomes).prefix(while: { $0.1 == .applied }).map(\.0)
            let advanced = cursorStore.advanceCursor(forTable: table, afterApplying: appliedPrefix)

            guard appliedPrefix.count < page.count else {
                // Full progress this page — nothing stuck on this table.
                skipTracker.clearSkip(table: table)

                // Anomaly guard — see `SyncPullActorError.cursorStalledOnFullPage`'s
                // doc comment for why this should be unreachable in normal
                // operation now, and why it's kept anyway.
                if page.count == pageSize, advanced == nil || advanced == since {
                    throw SyncPullActorError.cursorStalledOnFullPage(
                        table: table,
                        appliedSoFar: totalApplied,
                        skippedSoFar: totalSkipped,
                        alreadyPresentSoFar: totalAlreadyPresent,
                        permanentlyDroppedSoFar: totalPermanentlyDropped
                    )
                }
                if page.count < pageSize { break }
                continue
            }

            // A row stopped the safe prefix short — the head of this
            // table's unapplied rows this cycle. Resolve it (the
            // poison-row policy — see `resolveStuckRow`'s and
            // `SyncSkipTracker`'s doc comments) rather than either looping
            // forever on it or, on a full page, taking the whole cycle down
            // with it the way the old `Date`-only cursor design used to
            // (Critical A in the 2026-08 lot-2 pull review).
            let wasDropped = try resolveStuckRow(
                page: page,
                outcomes: outcomes,
                appliedPrefixCount: appliedPrefix.count,
                table: table,
                cursorStore: cursorStore,
                skipTracker: skipTracker,
                pageSize: pageSize,
                appliedSoFar: totalApplied,
                skippedSoFar: totalSkipped,
                alreadyPresentSoFar: totalAlreadyPresent,
                permanentlyDroppedSoFar: totalPermanentlyDropped
            )
            if wasDropped {
                totalPermanentlyDropped += 1
                continue
            }

            // Not yet at the drop threshold (or the stuck row can't even be
            // positioned — missing `server_updated_at`/`id`, residual
            // anomaly territory — see `resolveStuckRow`): this table makes
            // no further progress THIS cycle. Stop here rather than
            // throwing — the caller (`pullAll`) simply moves on to the next
            // table, and the next cycle retries this same row (accumulating
            // another strike if it's still the same one).
            break
        }

        return (totalApplied, totalSkipped, totalAlreadyPresent, totalPermanentlyDropped)
    }

    // `strikeCountAndThreshold` and `resolveStuckRow` — the poison-row
    // strike bookkeeping `pullAndApply` above calls into — live in
    // `SyncPullActor+StuckRowResolution.swift`, not here — split out purely
    // to stay under SwiftLint's `file_length`/`type_body_length` budgets,
    // same reasoning as `SyncPullActor+StandaloneTables.swift`. Neither is
    // `private` there for the same cross-file-extension reason `fetchOne`
    // below isn't.

    // MARK: - Row application dispatch

    /// Dispatches to the per-table apply function and returns, alongside the
    /// applied count, `outcomes` — one `RowApplyOutcome` per element of
    /// `rows`, IN THE SAME ORDER (see that type's doc comment for the three
    /// states and why a skip's REASON matters, not just that it happened).
    /// `pullAndApply` uses this to compute the safe cursor-advance prefix
    /// (`.applied` rows only) AND to route a stuck row to the right
    /// `SyncSkipTracker` counter — every per-table apply function this
    /// dispatches to — 4 of them below, plus the 4 standalone-table ones in
    /// `SyncPullActor+StandaloneTables.swift` — must append exactly one
    /// outcome per row it iterates, in order, or both computations silently
    /// misalign.
    ///
    /// The third element, `alreadyPresentCount`, is nonzero only for the 3
    /// append-only tables (`review_logs`, `vocabulary_encounters`,
    /// `exercise_outcome_logs`) — see `PullSummary.alreadyPresentRowCounts`
    /// for why a redelivered-but-already-applied row is tracked separately
    /// from `count` rather than folded into it.
    private func apply(
        table: String,
        rows: [SyncRow],
        pendingCardReplayIDs: inout Set<UUID>
    ) throws -> (count: Int, outcomes: [RowApplyOutcome], alreadyPresentCount: Int) {
        switch table {
        case "profiles":
            let result = try applyProfileRows(rows)
            return (result.count, result.outcomes, 0)
        case "rpg_states":
            let result = try applyRPGStateRows(rows)
            return (result.count, result.outcomes, 0)
        case "cards":
            let result = try applyCardRows(rows)
            pendingCardReplayIDs.formUnion(result.needsReplay)
            return (result.count, result.outcomes, 0)
        case "review_logs":
            let result = try applyReviewLogRows(rows)
            pendingCardReplayIDs.formUnion(result.touchedCardIDs)
            return (result.count, result.outcomes, result.alreadyPresentCount)
        case "vocabulary_entries":
            let result = try applyVocabularyEntryRows(rows)
            return (result.count, result.outcomes, 0)
        case "vocabulary_encounters":
            let result = try applyVocabularyEncounterRows(rows)
            return (result.count, result.outcomes, result.alreadyPresentCount)
        case "exercise_outcome_logs":
            let result = try applyExerciseOutcomeLogRows(rows)
            return (result.count, result.outcomes, result.alreadyPresentCount)
        case "text_imports":
            // `0` for `alreadyPresentCount`, like `vocabulary_entries`: this
            // table is not append-only, so a redelivered row goes through the
            // normal merge instead of being counted as a no-op redelivery.
            let result = try applyTextImportRows(rows)
            return (result.count, result.outcomes, 0)
        default:
            // Not one of `pullOrder`'s 8 tables — nothing calls `apply`
            // with any other value, so this is unreachable in practice;
            // fail loudly rather than silently dropping unknown rows.
            assertionFailure("SyncPullActor.apply called with unrecognized table: \(table)")
            return (0, Array(repeating: .skippedPermanent, count: rows.count), 0)
        }
    }

    // MARK: - Rule 1 support: local row count

    /// Sum of local rows across the same 8 tables this actor pulls — the
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
            + modelContext.fetchCount(FetchDescriptor<TextImport>())
    }

    // MARK: - profiles

    private struct ProfilePayload: Decodable {
        let displayName: String
        let createdAt: Date
        let settings: ProfileSettings
    }

    private func applyProfileRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome]) {
        var applied = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // `try?` on the decode, not `try` (CRITIQUE 2): a single
            // undecodable row (e.g. an enum value written by a newer app
            // version, or a null where this DTO expects a value) must skip
            // just that row, not throw out of `applyProfileRows` and abort
            // every table still left in `pullOrder` for this cycle. Always
            // PERMANENT here — `profiles` has no foreign key of its own to
            // wait on (see `RowApplyOutcome`).
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"],
                  let payload = try? SyncRowDecoding.decode(ProfilePayload.self, from: payloadValue) else {
                outcomes.append(.skippedPermanent)
                continue
            }

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
            outcomes.append(.applied)
        }
        return (applied, outcomes)
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

    private func applyRPGStateRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome]) {
        var applied = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // `try?` on the decode (CRITIQUE 2) — see `applyProfileRows`.
            // Always PERMANENT — `profile_id` below is optional and never
            // gates a skip (an unresolved profile just leaves the new
            // `RPGState` orphaned, see the `else` branch), so there is no
            // TRANSIENT case in this function.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"],
                  let payload = try? SyncRowDecoding.decode(RPGStatePayload.self, from: payloadValue) else {
                outcomes.append(.skippedPermanent)
                continue
            }
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
                //
                // GAP-04 (`docs/known-gaps.md`): this branch can run TWICE
                // in the SAME page when the server holds two `rpg_states`
                // rows for one profile (a reinstalled device's fresh push
                // landing next to an earlier device generation's still-live
                // row) — each remote row re-adopts THIS SAME local
                // `RPGState`, id-flipping it once per row. Verified
                // (`SyncPullDivergenceTests+RPGStateOrphan.swift`) to
                // stabilize to exactly one local row in one cycle, with
                // every counter preserved by `mergeRPGState`'s `max()` —
                // but the OTHER remote row's server-side id is never
                // adopted by anything again, and nothing ever deletes it:
                // one orphaned `rpg_states` row survives server-side per
                // affected profile. Decision (2026-08-15): accept this —
                // no counter is ever at risk, and a server-side cleanup job
                // is more moving parts than a cosmetic, unreachable row
                // justifies. Revisit only if `rpg_states` ever grows an
                // admin-facing view that would surface the orphan.
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
            outcomes.append(.applied)
        }
        return (applied, outcomes)
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

    /// Applies pulled `cards` rows. Returns, alongside the applied count and
    /// `outcomes` (see the `apply` dispatcher's doc comment), the set of
    /// card ids that need an FSRS replay pass (rule 2) once `review_logs`
    /// has been fully applied:
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
    ///
    /// ⚠️ CRITIQUE 4: a remote win against a card that ALREADY has local
    /// review logs does NOT copy the payload's scheduling fields
    /// (`fsrsState`/`easeFactor`/`interval`/`dueDate`/`lapseCount`) — only
    /// its content fields (`front`/`back`/`type`/`jlptLevel`/`leechFlag`).
    /// This save() happens per-page (`pullAndApply`), durably, BEFORE the
    /// replay pass that's supposed to be the sole authority over those
    /// fields even runs (`replayFSRS` only runs once, after the ENTIRE
    /// `review_logs` table finishes — see `pullAll`). If the payload's
    /// scheduling fields were written here and a later page (or the replay
    /// pass itself) then failed — a network error, a crash — the wrong,
    /// non-authoritative remote values would be left on disk permanently:
    /// the card's own row won't be re-delivered once the cursor has moved
    /// past it, so nothing would ever re-signal the correction is still
    /// owed. Leaving the existing (locally-derived) scheduling fields
    /// untouched here instead means a missed replay just leaves the prior —
    /// still internally consistent — local state in place, and the next
    /// successful replay (this cycle or a future one, since the card is
    /// still queued in `needsReplay`) corrects it for real.
    private func applyCardRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome], needsReplay: Set<UUID>) {
        var applied = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        var needsReplay: Set<UUID> = []
        for row in rows {
            // `try?` on the decode (CRITIQUE 2) — see `applyProfileRows`.
            // Always PERMANENT — `profile_id` below is optional and never
            // gates a skip, same reasoning as `applyRPGStateRows`.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"],
                  let payload = try? SyncRowDecoding.decode(CardPayload.self, from: payloadValue) else {
                outcomes.append(.skippedPermanent)
                continue
            }
            let profileID = SyncRowDecoding.uuid(row, "profile_id")

            if let existing = try fetchOne(Card.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                let hasLocalReviewLogs = !(existing.reviewLogs ?? []).isEmpty
                if winner == .remote {
                    existing.front = payload.front
                    existing.back = payload.back
                    existing.typeRawValue = payload.type
                    existing.leechFlag = payload.leechFlag
                    existing.jlptLevelRawValue = payload.jlptLevel
                    if !hasLocalReviewLogs {
                        // Only apply the payload's scheduling fields when
                        // there is no local log set for `replayFSRS` to
                        // derive them from instead — see this function's
                        // doc comment (CRITIQUE 4).
                        existing.fsrsState = payload.fsrsState
                        existing.easeFactor = payload.easeFactor
                        existing.interval = payload.interval
                        existing.dueDate = payload.dueDate
                        existing.lapseCount = payload.lapseCount
                    }
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
                if existing.deletedAt == nil, hasLocalReviewLogs {
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
            outcomes.append(.applied)
        }
        return (applied, outcomes, needsReplay)
    }

    // MARK: - review_logs

    private struct ReviewLogPayload: Decodable {
        let responseTimeMs: Int
    }

    private func applyReviewLogRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome], touchedCardIDs: Set<UUID>, alreadyPresentCount: Int) {
        var applied = 0
        var alreadyPresent = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        var touchedCardIDs: Set<UUID> = []
        for row in rows {
            // PERMANENT — the row itself is undecodable, not waiting on
            // anything.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"] else {
                outcomes.append(.skippedPermanent)
                continue
            }

            // Append-only per design spec §3 — a review log is never
            // updated after creation, only ever created (or, in principle,
            // tombstoned, though nothing in this codebase does that today —
            // see `ReviewLog`'s doc comment). So unlike every other table,
            // there is no "remote wins, overwrite fields" branch: if it
            // already exists locally, this row is a redelivery (the keyset
            // boundary row, or a re-applied already-seen id from a
            // previous cycle) and applying it again is a safe no-op — safe
            // enough to advance the cursor past (`.applied`), but not NEW
            // work, so it's counted separately in `alreadyPresent` rather
            // than in `applied` (see `PullSummary.alreadyPresentRowCounts`'s
            // doc comment).
            if let existing = try fetchOne(ReviewLog.self, id: common.id) {
                // …with ONE exception, and it is the reason this branch is
                // not a plain `continue`: a **tombstone** is the only field
                // an append-only row can legitimately change after
                // creation. Skipping the row wholesale meant a deletion
                // pushed by another device was received and thrown away —
                // the log outlived the card it belonged to, and
                // `CardModelActor.allReviewLogs(from:to:)` (which reads
                // `ReviewLog` directly, without going through the card)
                // kept feeding it into progress stats and the weekly
                // check-in forever. Reproduced across two containers
                // against one `FakeSyncServer`: `cards=0 logs=1`.
                //
                // Only ever nil → non-nil. A local tombstone is never
                // un-set by a remote row that still looks alive (merge
                // rule 4: a deletion does not get resurrected by a stale
                // peer that has not seen it yet).
                if existing.deletedAt == nil, let remoteDeletedAt = common.deletedAt {
                    existing.deletedAt = remoteDeletedAt
                    existing.updatedAt = max(existing.updatedAt, common.updatedAt)
                    existing.syncedAt = common.updatedAt
                }
                alreadyPresent += 1
                outcomes.append(.applied)
                continue
            }

            guard let cardID = SyncRowDecoding.uuid(row, "card_id"),
                  let card = try fetchOne(Card.self, id: cardID) else {
                // TRANSIENT (2026-08 lot-2 pull review, round 4 — see
                // `RowApplyOutcome`): the referenced card doesn't exist
                // locally YET. Expected in the ordinary case — `cards` is
                // pulled before `review_logs` in `pullOrder` — but a card
                // that is itself delayed (e.g. stuck behind an unrelated
                // poison row in `cards`, which can take up to
                // `poisonDropThreshold` cycles of its own to resolve) can
                // legitimately take more than a cycle or two to show up.
                // Skipped, not counted as applied — and (CRITIQUE 1) the
                // cursor is not allowed to advance past it either, so it's
                // retried on a future cycle. Previously classified
                // identically to a genuinely undecodable row, which force-
                // dropped this log for good after only 3 cycles even when
                // the card was still on its way — real review history lost
                // for a row that was never actually unrecoverable.
                outcomes.append(.skippedTransient)
                continue
            }
            // PERMANENT — the FK resolved; what's left undecodable here is
            // the row's own content, not something to wait on.
            guard let payload = try? SyncRowDecoding.decode(ReviewLogPayload.self, from: payloadValue),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at"),
                  let gradeRaw = SyncRowDecoding.number(row, "grade"),
                  let grade = Grade(rawValue: Int(gradeRaw)) else {
                outcomes.append(.skippedPermanent)
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
            outcomes.append(.applied)
        }
        return (applied, outcomes, touchedCardIDs, alreadyPresent)
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

    // MARK: - vocabulary_entries, vocabulary_encounters, exercise_outcome_logs, text_imports
    //
    // The 4 standalone (no FK dependency on `cards`/`review_logs`, no rule-2
    // replay involvement) apply functions live in
    // `SyncPullActor+StandaloneTables.swift`, not here — splitting them out
    // is what keeps this file/actor under SwiftLint's `file_length` (1200)
    // and `type_body_length` (600) budgets. `fetchOne` below is `internal`,
    // not `private`, specifically so that extension can still reach it.

    // MARK: - Fetch-by-id helper

    /// Fetches a single instance of `T` by its `id` property. Generic over
    /// every synced `@Model` type in this file — all 7 share the same
    /// `id: UUID` shape (see each model's doc comment), so one helper
    /// serves all of them rather than repeating this fetch 7 times.
    ///
    /// Not `private`: `SyncPullActor+StandaloneTables.swift`'s extension
    /// calls this too, and cross-file extensions of the same type cannot
    /// see each other's `private` members — only `internal` (the default
    /// for a symbol with no access modifier) is visible module-wide, which
    /// is exactly as narrow as this needs to be since `SyncPullActor`
    /// itself is never `public`.
    func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID) throws -> T? where T: SyncIdentifiable {
        let predicate = #Predicate<T> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // `SyncIdentifiable`, `SyncRowDecoding`, and `SyncPullDateParsing` live
    // in `SyncPullActor+RowDecoding.swift`, not here — split out purely to
    // stay under SwiftLint's `file_length` (1200 lines) budget, same
    // reasoning as `SyncPullActor+StandaloneTables.swift`.
}
