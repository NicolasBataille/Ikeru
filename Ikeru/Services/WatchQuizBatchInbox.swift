import Foundation
import IkeruCore
import os

// MARK: - PendingWatchQuizBatch

/// A Watch nano-session that has been **received** by the iPhone but not yet
/// fully graded, together with how far grading got.
///
/// Grading a batch is a long, suspended affair — one `await
/// CardRepository.gradeCard` per answer, each its own SwiftData transaction —
/// and the process can die at any of those suspension points (jetsam, force
/// quit, crash). The progress fields make a replay resume instead of
/// restarting: without them, re-grading a batch whose first six answers were
/// already written would duplicate six `ReviewLog` rows and apply six extra
/// FSRS transitions.
struct PendingWatchQuizBatch: Codable, Sendable {

    let batch: WatchQuizReviewBatch

    /// When `didReceiveUserInfo` handed this batch over. Only used for
    /// diagnostics and FIFO eviction order.
    let receivedAt: Date

    /// Index of the next `batch.events` entry to consider. Everything before
    /// it has already been either graded (a `ReviewLog` exists) or
    /// deliberately skipped (no matching card / not eligible).
    var nextEventIndex: Int

    /// How many events before `nextEventIndex` actually produced a
    /// `ReviewLog`. Carried across a replay so the final aggregate
    /// (`totalQuestions`) counts the whole nano-session, not just the part
    /// graded after the last relaunch.
    var gradedCount: Int

    /// How many of those were correct — same reason.
    var gradedCorrectCount: Int

    init(
        batch: WatchQuizReviewBatch,
        receivedAt: Date = Date(),
        nextEventIndex: Int = 0,
        gradedCount: Int = 0,
        gradedCorrectCount: Int = 0
    ) {
        self.batch = batch
        self.receivedAt = receivedAt
        self.nextEventIndex = nextEventIndex
        self.gradedCount = gradedCount
        self.gradedCorrectCount = gradedCorrectCount
    }
}

// MARK: - WatchQuizBatchAttribution

/// What the iPhone may do with a received batch, given which profile answered
/// it (`WatchQuizReviewBatch.profileId`) and which profile is active now.
///
/// Pure decision, deliberately split out from `WatchConnectivityManager`: the
/// manager is a `WCSession`-owning singleton that no unit test can construct,
/// and this is the rule GAP-17's defect 2 turns on.
enum WatchQuizBatchAttribution: String, Sendable {

    /// The batch belongs to the profile that is active right now (or cannot
    /// belong to anyone else) — grade it.
    case grade

    /// The batch belongs to a different profile that still exists on this
    /// device. Keep it queued and grade it when that profile is active
    /// again: everything grading needs — `CardRepository.activeProfileCards`,
    /// the eligible-kana set, `RPGState` — resolves through the *active*
    /// profile, so grading another profile's answers is not merely wrong
    /// here, it is impossible to do correctly. Discarding would throw away
    /// real reviews the learner did.
    case deferUntilProfileActive

    /// Unstamped batch (Watch build predating `profileId`) on a device with
    /// several profiles: it cannot be attributed to any of them, and grading
    /// it on whichever happens to be active would falsify two histories at
    /// once — the profile that gets the reviews it never did, and the one
    /// that keeps looking like it never revised. Dropped, loudly.
    case discardUnattributable

    /// The stamped profile no longer exists (deleted / tombstoned). Nothing
    /// can ever receive these reviews; keeping the entry would pin it in the
    /// inbox forever.
    case discardOrphaned
}

// MARK: - WatchQuizBatchInbox

/// Durable, bounded inbox of Watch nano-sessions awaiting grading on the
/// iPhone, plus the set of session ids already fully graded.
///
/// ## Why this exists (GAP-17 defect 1)
///
/// The previous flow marked a batch "processed" in `UserDefaults`
/// **before** the grading loop and its N suspension points. A process death
/// inside that window left the batch marked as done with zero `ReviewLog`
/// rows written — ten real reviews erased, permanently, because nothing
/// redelivers them.
///
/// That "nothing redelivers them" is the load-bearing claim, so it is worth
/// pinning to Apple's own words rather than intuition.
/// `WCSession.transferUserInfo(_:)`: *"Dictionaries sent using this method
/// are queued on the other device and delivered in the order in which they
/// were sent."* — the queue lives on the **receiving** device and is drained
/// by delivery. `session(_:didReceiveUserInfo:)`: *"The session object calls
/// this method when it successfully receives a data dictionary from its
/// counterpart."* Delivery is the acknowledged event; nothing in the API
/// acknowledges *processing*, and no documented mechanism re-presents a
/// dictionary that was already handed to the delegate. So merely moving the
/// "processed" mark later would protect nothing — the batch would be gone
/// either way.
///
/// Persisting the batch at reception is therefore the only fix that works,
/// and it is also correct under the opposite assumption: if a payload ever
/// *is* redelivered, `sessionId` dedupe (below) makes the replay a no-op.
/// One mechanism, both branches.
///
/// ## Durability
///
/// `UserDefaults` — the same store the previous "processed ids" list already
/// trusted, and an appropriate one here: values are handed to `cfprefsd`, a
/// separate process, at `set(_:forKey:)` time, so the write survives this
/// app's death even though the on-disk flush is asynchronous. It is not
/// crash-proof against device power loss; that is a deliberate trade for a
/// bounded, well-understood store rather than a hand-rolled file protocol
/// with its own data-protection failure modes while the device is locked.
struct WatchQuizBatchInbox {

    /// Batches received and not yet fully graded.
    static let pendingKey = "WatchConnectivityManager.pendingWatchQuizBatches"

    /// Session ids already fully graded. Key unchanged from before GAP-17 so
    /// existing installs keep their dedupe history across the update.
    static let processedKey = "WatchConnectivityManager.processedBatchIds"

    /// Cap on the processed-id ring so it can't grow unbounded over the life
    /// of an install.
    static let processedCap = 200

    /// Cap on queued-but-ungraded batches. Reached only by a learner who
    /// keeps answering on the wrist under a profile that never becomes
    /// active again (see `deferUntilProfileActive`); the oldest entry is
    /// then dropped. Bounded loss, chosen over an inbox that grows forever.
    static let pendingCap = 20

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reads

    func pending() -> [PendingWatchQuizBatch] {
        guard let data = defaults.data(forKey: Self.pendingKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PendingWatchQuizBatch].self, from: data)) ?? []
    }

    func processedIds() -> [String] {
        defaults.stringArray(forKey: Self.processedKey) ?? []
    }

    func isProcessed(_ sessionId: UUID) -> Bool {
        processedIds().contains(sessionId.uuidString)
    }

    // MARK: - Writes

    /// Records a freshly received batch, synchronously, before any grading is
    /// attempted. Returns `false` when the batch is a duplicate — already
    /// graded, or already queued — which is the whole idempotency guarantee:
    /// a redelivered `transferUserInfo` payload, or two interleaved delivery
    /// `Task`s for the same session, produce exactly one grading pass.
    ///
    /// Safe to call before the first `await` and cheap enough to belong
    /// there: one decode + one encode of a list capped at
    /// `pendingCap` entries.
    @discardableResult
    func admit(_ batch: WatchQuizReviewBatch, receivedAt: Date = Date()) -> Bool {
        guard !isProcessed(batch.sessionId) else { return false }
        var entries = pending()
        guard !entries.contains(where: { $0.batch.sessionId == batch.sessionId }) else { return false }
        entries.append(PendingWatchQuizBatch(batch: batch, receivedAt: receivedAt))
        if entries.count > Self.pendingCap {
            let dropped = entries.prefix(entries.count - Self.pendingCap)
            for entry in dropped {
                Logger.sync.error(
                    "Watch quiz inbox full — dropping ungraded batch \(entry.batch.sessionId) received \(entry.receivedAt)"
                )
            }
            entries.removeFirst(entries.count - Self.pendingCap)
        }
        write(entries)
        return true
    }

    /// Persists how far grading got for `sessionId`. Called after **each**
    /// graded answer so a process death costs at most the one `gradeCard`
    /// that was in flight, not the whole prefix.
    func recordProgress(
        sessionId: UUID,
        nextEventIndex: Int,
        gradedCount: Int,
        gradedCorrectCount: Int
    ) {
        var entries = pending()
        guard let index = entries.firstIndex(where: { $0.batch.sessionId == sessionId }) else { return }
        entries[index].nextEventIndex = nextEventIndex
        entries[index].gradedCount = gradedCount
        entries[index].gradedCorrectCount = gradedCorrectCount
        write(entries)
    }

    /// Removes `sessionId` from the queue and records it as processed, so a
    /// later redelivery is ignored.
    func complete(_ sessionId: UUID) {
        write(pending().filter { $0.batch.sessionId != sessionId })
        var ids = processedIds()
        guard !ids.contains(sessionId.uuidString) else { return }
        ids.append(sessionId.uuidString)
        if ids.count > Self.processedCap {
            ids.removeFirst(ids.count - Self.processedCap)
        }
        defaults.set(ids, forKey: Self.processedKey)
    }

    private func write(_ entries: [PendingWatchQuizBatch]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else {
            Logger.sync.error("Failed to encode pending Watch quiz batches — inbox left unchanged")
            return
        }
        defaults.set(data, forKey: Self.pendingKey)
    }

    // MARK: - Attribution

    /// Decides what may be done with a batch. See `WatchQuizBatchAttribution`
    /// for why each outcome is what it is.
    ///
    /// - Parameters:
    ///   - batchProfileId: the stamp the Watch sent, `nil` for a Watch build
    ///     predating it.
    ///   - activeProfileId: the profile active on this device right now.
    ///   - liveProfileIds: every non-deleted profile on this device.
    static func attribution(
        batchProfileId: UUID?,
        activeProfileId: UUID?,
        liveProfileIds: Set<UUID>
    ) -> WatchQuizBatchAttribution {
        guard let batchProfileId else {
            // Unstamped. With at most one profile on the device there is
            // nothing to mis-attribute it to, so the pre-GAP-17 behaviour
            // (grade it) stays correct; with several, it is unattributable.
            return liveProfileIds.count <= 1 ? .grade : .discardUnattributable
        }
        if batchProfileId == activeProfileId { return .grade }
        if liveProfileIds.contains(batchProfileId) { return .deferUntilProfileActive }
        return .discardOrphaned
    }
}

// MARK: - WatchQuizBatchTally

/// What a graded nano-session is worth, once the answers that could NOT be
/// graded are taken out.
///
/// All three numbers come from the same source — the answers that actually
/// produced a `ReviewLog` — so they cannot tell three different stories about
/// one nano-session. `xpEarned` used to be the exception, taken from the
/// Watch's claim regardless of what got graded (GAP-17 defect 3).
struct WatchQuizBatchTally: Equatable, Sendable {
    let gradedCount: Int
    let gradedCorrectCount: Int
    let xpEarned: Int

    /// XP to credit: derived from the correct answers that were graded, by
    /// the same rule the Watch used, and never more than the Watch itself
    /// claimed for the whole session. The cap matters when the two sides
    /// disagree about the rule (an older or newer Watch build) — this side
    /// then credits the smaller, defensible amount instead of inventing XP.
    static func creditedXP(gradedCorrectCount: Int, claimedXP: Int) -> Int {
        min(WatchQuizReviewBatch.xp(forCorrectAnswers: gradedCorrectCount), max(0, claimedXP))
    }
}

// MARK: - WatchQuizEventDisposition

/// What happens to one answer of a received batch.
enum WatchQuizEventDisposition: String, Sendable {
    case grade
    /// No kana card with that `front` exists on this device.
    case skipNoCard
    /// The card exists but isn't currently eligible — group deselected, or
    /// never graded before (`reps == 0`). See
    /// `WatchConnectivityManager.eligibleKanaFronts`.
    case skipIneligible
}

// MARK: - WatchQuizBatchGrader

/// Runs one queued nano-session's grading loop: resume point, per-answer
/// disposition, checkpoint after every answer, final tally.
///
/// Split out of `WatchConnectivityManager` so this — the part GAP-17's three
/// defects live in — can be exercised without a simulator: the manager is a
/// `WCSession`-owning `@MainActor` singleton with a private initializer, so
/// nothing about its grading loop was reachable from a test. Here the two
/// things the loop needs from the device (which fronts resolve to a card,
/// which are eligible) are plain inputs, and the grading side effect is an
/// injected closure — production passes `CardRepository.gradeCard`, a test
/// passes a recorder.
@MainActor
struct WatchQuizBatchGrader {

    let inbox: WatchQuizBatchInbox

    /// Kana `front` → card id, resolved on the phone from
    /// `KanaCardRepository.allKanaCards()`.
    let cardIdByFront: [String: UUID]

    /// Fronts eligible for grading RIGHT NOW, recomputed phone-side and
    /// never trusted from the Watch.
    let eligibleFronts: Set<String>

    /// The actual grading side effect (one `ReviewLog` per call).
    let gradeAnswer: (UUID, WatchQuizReviewBatch.Event) async -> Void

    /// Whether an answer can be graded, and why not when it can't.
    func disposition(for event: WatchQuizReviewBatch.Event) -> WatchQuizEventDisposition {
        guard cardIdByFront[event.targetCharacter] != nil else { return .skipNoCard }
        guard eligibleFronts.contains(event.targetCharacter) else { return .skipIneligible }
        return .grade
    }

    /// Grades `entry` from its recorded resume point to the end, checkpointing
    /// progress in the inbox after **every** answer, and returns what the
    /// nano-session is worth.
    ///
    /// Resuming (rather than restarting) is what keeps a replay honest: the
    /// answers before `nextEventIndex` already have their `ReviewLog` rows,
    /// and re-grading them would duplicate both the rows and their FSRS
    /// transitions. The counters are carried across the interruption too, so
    /// the aggregate covers the whole nano-session and not just the part
    /// graded since the last relaunch.
    func grade(_ entry: PendingWatchQuizBatch) async -> WatchQuizBatchTally {
        let batch = entry.batch
        var nextEventIndex = entry.nextEventIndex
        var gradedCount = entry.gradedCount
        var gradedCorrectCount = entry.gradedCorrectCount

        while nextEventIndex < batch.events.count {
            let event = batch.events[nextEventIndex]
            switch disposition(for: event) {
            case .grade:
                if let cardId = cardIdByFront[event.targetCharacter] {
                    await gradeAnswer(cardId, event)
                    gradedCount += 1
                    if event.isCorrect { gradedCorrectCount += 1 }
                }
            case .skipNoCard:
                // e.g. the learner hasn't chosen that kana group yet, or
                // purged an unstarted one. Skipped rather than graded onto
                // the wrong card — and logged, not silently dropped.
                Logger.sync.warning(
                    "Watch quiz answer for \(event.targetCharacter) has no matching kana card — skipped"
                )
            case .skipIneligible:
                Logger.sync.warning(
                    "Watch quiz answer for \(event.targetCharacter) is not eligible for grading — skipped"
                )
            }

            nextEventIndex += 1
            // Checkpointed after EVERY answer, graded or skipped: a process
            // death now costs at most the single grade that was in flight,
            // instead of the whole nano-session (GAP-17 defect 1).
            inbox.recordProgress(
                sessionId: batch.sessionId,
                nextEventIndex: nextEventIndex,
                gradedCount: gradedCount,
                gradedCorrectCount: gradedCorrectCount
            )
        }

        return WatchQuizBatchTally(
            gradedCount: gradedCount,
            gradedCorrectCount: gradedCorrectCount,
            xpEarned: WatchQuizBatchTally.creditedXP(
                gradedCorrectCount: gradedCorrectCount,
                claimedXP: batch.xpEarned
            )
        )
    }
}
