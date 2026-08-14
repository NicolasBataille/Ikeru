import Foundation
import os

/// The poison-row / stuck-row strike bookkeeping `SyncPullActor.pullAndApply`
/// calls into — split out of `SyncPullActor.swift` itself purely to stay
/// under SwiftLint's `file_length` (1200 lines) and `type_body_length` (600
/// lines, actor body) budgets, same reasoning as
/// `SyncPullActor+StandaloneTables.swift`'s own doc comment. There is no
/// behavioral reason these two couldn't live in the main file. Neither is
/// `private`, for the same cross-file-extension reason `fetchOne` in
/// `SyncPullActor.swift` isn't — see that method's doc comment.
extension SyncPullActor {

    /// Picks WHICH `SyncSkipTracker` counter to record a stuck row's strike
    /// against, and the threshold that counter is compared to. A PERMANENT
    /// reason (an undecodable payload) can never self-heal, so it keeps the
    /// tight `poisonDropThreshold`. A TRANSIENT reason (an unresolved
    /// foreign key) is expected to self-heal once its parent row's own
    /// table catches up, so it gets the much wider
    /// `transientPoisonDropThreshold` instead — and, critically, never
    /// touches the permanent counter at all, so waiting on a late parent
    /// can never itself trigger the permanent drop. See `RowApplyOutcome`'s
    /// doc comment for the full story.
    func strikeCountAndThreshold(
        for outcome: RowApplyOutcome,
        table: String,
        stuckID: UUID,
        stuckIndex: Int,
        skipTracker: any SyncSkipTracker
    ) -> (strikes: Int, threshold: Int) {
        switch outcome {
        case .applied:
            // Structurally unreachable: the caller only reaches this
            // function for a row whose outcome is NOT `.applied` (see
            // `pullAndApply`'s `prefix(while:)`). Handled defensively —
            // same "fail loudly, not silently" stance as the `apply`
            // dispatcher's own unreachable `default:` case — rather than
            // crashing the whole pull cycle over a defensive invariant.
            assertionFailure("Stuck row for \(table) at index \(stuckIndex) was unexpectedly marked .applied")
            return (skipTracker.recordSkip(table: table, headRowID: stuckID), Self.poisonDropThreshold)
        case .skippedPermanent:
            return (skipTracker.recordSkip(table: table, headRowID: stuckID), Self.poisonDropThreshold)
        case .skippedTransient:
            return (skipTracker.recordTransientSkip(table: table, headRowID: stuckID), Self.transientPoisonDropThreshold)
        }
    }

    /// Resolves the row that stopped `pullAndApply`'s applied-prefix short
    /// this page. Returns `true` if the row was just force-abandoned
    /// (cursor advanced past it — caller should bump its own
    /// `totalPermanentlyDropped` and `continue` the pagination loop),
    /// `false` if this table simply makes no further progress THIS cycle
    /// (caller should `break`).
    ///
    /// The 4 `…SoFar` parameters exist ONLY to populate
    /// `SyncPullActorError.cursorStalledOnFullPage` if the residual anomaly
    /// guard fires (an unparseable `id` on a full page) — see that error
    /// case's doc comment.
    func resolveStuckRow(
        page: [SyncRow],
        outcomes: [RowApplyOutcome],
        appliedPrefixCount: Int,
        table: String,
        cursorStore: any SyncCursorStore,
        skipTracker: any SyncSkipTracker,
        pageSize: Int,
        appliedSoFar: Int,
        skippedSoFar: Int,
        alreadyPresentSoFar: Int,
        permanentlyDroppedSoFar: Int
    ) throws -> Bool {
        let stuckRow = page[appliedPrefixCount]
        let stuckOutcome = outcomes[appliedPrefixCount]
        guard let stuckID = SyncRowDecoding.uuid(stuckRow, "id") else {
            // The stuck row's own `id` doesn't even parse — cannot be
            // tracked by the skip tracker (nothing to key it on), and every
            // apply function already requires a parseable `id` to do
            // anything at all (see `SyncRowDecoding.common`), so a row
            // shaped like this should never reach here in practice. Same
            // residual-anomaly territory as `SyncPullActorError.cursorStalledOnFullPage`'s
            // doc comment: only escalate to the loud safety net when the
            // page was full (matching the pre-existing "full page, no
            // progress" signature).
            if page.count == pageSize {
                throw SyncPullActorError.cursorStalledOnFullPage(
                    table: table,
                    appliedSoFar: appliedSoFar,
                    skippedSoFar: skippedSoFar,
                    alreadyPresentSoFar: alreadyPresentSoFar,
                    permanentlyDroppedSoFar: permanentlyDroppedSoFar
                )
            }
            return false
        }

        // Route to the counter matching WHY this row is stuck — see
        // `strikeCountAndThreshold`'s and `RowApplyOutcome`'s doc comments.
        let (strikes, threshold) = strikeCountAndThreshold(
            for: stuckOutcome,
            table: table,
            stuckID: stuckID,
            stuckIndex: appliedPrefixCount,
            skipTracker: skipTracker
        )

        guard strikes >= threshold,
              case .string(let stuckTimestamp)? = stuckRow["server_updated_at"] else {
            return false
        }

        // `threshold` consecutive cycles stuck on the SAME row: abandon it,
        // visibly, rather than pinning this table's cursor forever.
        // `setCursor`, not `advanceCursor` — this row was never durably
        // applied, so routing through `advanceCursor` (whose contract is
        // specifically "the rows behind this were already applied") would
        // be exactly the kind of comment-lies-about-the-code-next-to-it
        // this project's rules forbid. This is a deliberate skip, spelled
        // out as one, made SAFE (rather than a data-loss risk) precisely
        // because the composite cursor can point at this one row exactly,
        // without touching anything else that shares its timestamp.
        cursorStore.setCursor(SyncCursorPosition(timestamp: stuckTimestamp, id: stuckID), forTable: table)
        skipTracker.clearSkip(table: table)
        Logger.sync.error(
            "Cloud sync: permanently dropping unrecoverable row \(stuckID, privacy: .public) in \(table, privacy: .public) after \(strikes) consecutive cycles (\(String(describing: stuckOutcome), privacy: .public))"
        )
        return true
    }
}
