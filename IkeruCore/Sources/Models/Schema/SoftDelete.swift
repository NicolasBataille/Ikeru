import Foundation

/// A synced row that is deleted by **tombstoning** rather than by
/// `modelContext.delete(_:)`.
///
/// ## Why this exists
///
/// Every one of the 8 synced entities carries `updatedAt` / `deletedAt` /
/// `syncedAt` (`IkeruSchemaV4`, cloud-sync design spec §5.1), and the whole
/// sync stack downstream of the write already understands tombstones:
/// `SyncPayloadBuilder` serialises `deleted_at`, `SyncMergeRules.resolveWinner`
/// (rule 4) lets a tombstone beat any concurrent edit, and the pull actor
/// applies remote tombstones and excludes deleted rows from the rule-2 FSRS
/// replay. What was missing until this type existed was the **first link**:
/// nothing in production ever set `deletedAt`. Every user-facing deletion was
/// a hard `modelContext.delete(_:)`, which removes the row locally and leaves
/// **no trace at all** for the push to send — so the server row survived with
/// `deleted_at = null`, and any event that rewound the pull cursor
/// (`SyncCursorStore.resetAll()` on a backup off/on cycle, a reinstall, a new
/// anonymous identity) re-inserted the deleted row and the learner watched
/// their deletions come back.
///
/// ## The one rule callers must not break: never un-tombstone
///
/// Rule 4 gives a tombstone victory **regardless of timestamp**. Once a
/// deletion has reached the server, clearing `deletedAt` locally and pushing
/// again does not revive the row: the next pull compares a live local row
/// against a deleted remote one and re-kills it, forever. So a learner
/// re-adding something they deleted must get a **brand-new row with a new
/// `id`** — see `VocabularyModelActor.addEntry`, which is where this matters
/// in practice. There is deliberately no `revive()` here.
public protocol SoftDeletable: AnyObject {
    /// Local modification clock. Bumped alongside `deletedAt` so the push's
    /// delta filter (`SyncModelActor.isDirty`) sees the row as dirty.
    var updatedAt: Date { get set }

    /// Tombstone. Non-nil means the row was deleted locally and every read
    /// path must behave as if it were gone.
    var deletedAt: Date? { get set }
}

extension SoftDeletable {

    /// Whether this row has been deleted. Read paths filter on this.
    public var isTombstoned: Bool { deletedAt != nil }

    /// Marks the row deleted without destroying it, so the deletion can be
    /// pushed as `deleted_at` and can never be silently undone by a later
    /// pull.
    ///
    /// Idempotent: re-tombstoning an already-tombstoned row is a no-op, which
    /// preserves the *original* deletion instant. That matters because
    /// cascades overlap in practice (deleting a profile tombstones its cards,
    /// which tombstones their review logs; deleting one of those cards
    /// directly first must not have its timestamp rewritten afterwards).
    ///
    /// - Parameter now: The deletion instant. Injected rather than read from
    ///   the clock so tests can assert exact timestamps.
    public func tombstone(at now: Date = Date()) {
        guard deletedAt == nil else { return }
        deletedAt = now
        updatedAt = now
    }
}

// MARK: - Conformances
//
// 7 of the 8 synced entities. `CompanionChatMessage` is deliberately absent:
// it is neither pushed nor pulled (see `SyncPayloadBuilder`'s trailing
// comment and the absence of any `pushDirtyCompanion*` in `SyncModelActor`),
// so it has no resurrection vector — and tombstoning it would *retain* the
// text the learner typed to Sakura on a device where they asked for it to be
// erased. `CompanionChatRepository.clearHistory` keeps its hard delete on
// purpose.

extension UserProfile: SoftDeletable {}
extension RPGState: SoftDeletable {}
extension Card: SoftDeletable {}
extension ReviewLog: SoftDeletable {}
extension VocabularyEntry: SoftDeletable {}
extension VocabularyEncounter: SoftDeletable {}
extension ExerciseOutcomeLog: SoftDeletable {}
