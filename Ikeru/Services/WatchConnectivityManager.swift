import Foundation
import WatchConnectivity
import SwiftData
import IkeruCore
import os

// MARK: - WatchConnectivityManager

/// Manages WatchConnectivity session on the iPhone side.
/// Sends RPG state updates to Watch and receives Watch session results.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    private var session: WCSession?
    private var modelContainer: ModelContainer?

    /// Pending session results received from Watch (queued while offline).
    @Published private(set) var pendingResults: [WatchSessionResult] = []

    // MARK: - ReviewLog provenance (chantier #46)
    //
    // Watch quiz answers are graded through the SAME `CardRepository
    // .gradeCard` the iPhone kana drill uses (`kana.quiz` /
    // `iphone.drill` — see `KanaDrillViewModel`), just with `surface`
    // set to the reserved `"watch"` literal that `ReviewLog.surface`'s
    // doc comment already declares (this was the first call site to
    // ever write it).
    private static let watchQuizExerciseType = "kana.quiz"
    private static let watchSurface = "watch"

    /// Durable queue of received-but-not-yet-graded Watch nano-sessions, and
    /// the bounded set of session ids already graded (idempotency). See
    /// `WatchQuizBatchInbox` for why reception must persist the batch itself
    /// rather than just a "processed" flag.
    private let inbox = WatchQuizBatchInbox()

    /// Serializes inbox drains. Every drain is chained behind the previous
    /// one so two triggers (a delivery landing while the launch replay is
    /// still running, say) can't grade the same queued batch concurrently —
    /// the `await`s inside a drain are exactly the interleaving points that
    /// would otherwise allow it.
    private var drainTask: Task<Void, Never>?

    /// Whether the profile-change observer is already registered, so a
    /// second `activate(modelContainer:)` doesn't stack a duplicate.
    private var isObservingProfileChanges = false

    override private init() {
        super.init()
    }

    // MARK: - Setup

    /// Activates WatchConnectivity if supported.
    /// - Parameter container: The SwiftData model container for persisting received data.
    func activate(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        // Launch-time replay: anything the inbox still holds is a
        // nano-session that was received but never finished grading — most
        // likely because the process died mid-loop last time. This is the
        // production call site that makes the durable inbox mean something;
        // without it, persisting at reception would just be a write nobody
        // reads. Called BEFORE the `WCSession.isSupported()` guard on
        // purpose: a queued batch must still be replayed on a device where
        // WatchConnectivity is unavailable or the session fails to activate.
        observeProfileChanges()
        scheduleWatchQuizDrain()
        guard WCSession.isSupported() else {
            Logger.sync.info("WatchConnectivity not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        Logger.sync.info("WatchConnectivity session activated")
    }

    /// Re-drains the inbox when the learner switches profile: a batch parked
    /// as `deferUntilProfileActive` becomes gradable the moment its own
    /// profile is active again, and waiting for the next cold launch to
    /// notice would strand real reviews for days.
    ///
    /// Also re-pushes state to the Watch. Without this, `WatchSessionManager
    /// .activeProfileId` (and the eligible-kana set it's sent alongside)
    /// only refreshes on the next reactive trigger — the next
    /// `processWatchResult`, or the next session activation — so a learner
    /// who switches profile on the phone and immediately starts a wrist quiz
    /// would answer questions from the OLD profile's eligible pool, stamped
    /// with the OLD profile id. Harmless by construction (the batch would
    /// just defer until that profile is active again — see
    /// `WatchQuizBatchAttribution`), but it silently parks real wrist work
    /// that could have been graded immediately. `sendStateToWatch()`'s own
    /// guards make this a safe no-op when there's no paired Watch.
    private func observeProfileChanges() {
        guard !isObservingProfileChanges else { return }
        isObservingProfileChanges = true
        NotificationCenter.default.addObserver(
            forName: .ikeruActiveProfileDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WatchConnectivityManager.shared.scheduleWatchQuizDrain()
                WatchConnectivityManager.shared.sendStateToWatch()
            }
        }
    }

    // MARK: - Send State to Watch

    /// Sends the current RPG state to the Watch via applicationContext.
    func sendStateToWatch() {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }
        // Told to the Watch so it can stamp the nano-sessions it sends back
        // with the profile that answered them (GAP-17 defect 2). Read here,
        // on the same context and at the same moment as the RPG state and
        // the eligible-kana set, so all three describe one profile.
        let activeProfileId = ActiveProfileResolver.fetchActiveProfile(in: context)?.id

        let cardRepo = CardRepository(modelContainer: container)
        Task { @MainActor in
            let dueCards = await cardRepo.dueCards(before: Date())

            let payload = WatchSyncPayload(
                xp: state.xp,
                level: state.level,
                totalReviews: state.totalReviewsCompleted,
                dueCardCount: dueCards.count,
                source: .iPhone
            )

            // Merged into the SAME applicationContext dictionary — see
            // `WatchEligibleKanaPayload`'s doc for why a second
            // `updateApplicationContext` call can't be used instead.
            let eligibleCharacters = await eligibleKanaFronts(cardRepository: cardRepo)
            var contextDict = payload.toDictionary()
            contextDict[WatchEligibleKanaPayload.contextKey] = Array(eligibleCharacters)
            if let activeProfileId {
                contextDict[WatchQuizReviewBatch.activeProfileContextKey] = activeProfileId.uuidString
            }

            do {
                try session.updateApplicationContext(contextDict)
                Logger.sync.info(
                    "Sent state to Watch: level=\(state.level), xp=\(state.xp), eligibleKana=\(eligibleCharacters.count)"
                )
            } catch {
                Logger.sync.error("Failed to send state to Watch: \(error.localizedDescription)")
            }
        }
    }

    /// Kana fronts the Watch quiz may draw questions from: the learner's
    /// CURRENTLY chosen kana groups (`StudySetStore.chosenGroups`)
    /// intersected with kana already graded at least once
    /// (`fsrsState.reps > 0`) — see `WatchEligibleKanaPayload`'s doc for why
    /// `reps > 0` is the right bar (the P2 presentation phase already
    /// guarantees a never-graded card's first FSRS grade measures retention,
    /// not first-encounter noise; the Watch quiz has no presentation UI of
    /// its own, so it must stay off any card that hasn't cleared that bar
    /// yet).
    ///
    /// Recomputed fresh from the current selection on EVERY call — this is
    /// the single source of truth both `sendStateToWatch` (what to tell the
    /// Watch is eligible) and `processWatchQuizBatch` (what to actually
    /// accept for grading) resolve against, so a Watch that answered against
    /// a stale copy of this set can never get a stale answer graded: the
    /// receiving side re-derives the truth instead of trusting what the
    /// Watch sent.
    private func eligibleKanaFronts(cardRepository: CardRepository) async -> Set<String> {
        let kanaRepo = KanaCardRepository(cardRepository: cardRepository)
        let chosenGroups = StudySetStore.chosenGroups
        let scoped = await kanaRepo.cardsForGroups(chosenGroups)
        return Set(scoped.filter { $0.fsrsState.reps > 0 }.map(\.front))
    }

    // MARK: - Process Watch Results

    /// Processes a Watch session result by awarding XP and persisting.
    private func processWatchResult(_ result: WatchSessionResult) {
        guard let container = modelContainer else { return }
        let context = container.mainContext

        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }

        state.xp += result.xpEarned
        state.level = RPGConstants.levelForXP(state.xp)
        // `totalReviewsCompleted` is presented to the learner as a count of
        // reviews — only bump it for a drill that actually tested recall.
        // `.pitchAccent` is a haptic exposure exercise with no correctness
        // signal (see `HapticPitchDrillView.nextWord()`): counting it here
        // would claim reviews that never happened. XP is still awarded
        // above — a completed exposure exercise is still worth something —
        // just not counted as a "review".
        if result.drillType == .kanaQuiz {
            state.totalReviewsCompleted += result.totalQuestions
        }

        do {
            try context.save()
        } catch {
            Logger.sync.error("Failed to save Watch session result: \(error.localizedDescription)")
        }
        Logger.sync.info(
            "Processed Watch session: +\(result.xpEarned) XP, drill=\(result.drillType.rawValue)"
        )

        // Send updated state back to Watch
        sendStateToWatch()
    }

    /// Takes delivery of a batch of individually-graded kana quiz answers
    /// from the Watch, by writing it to the durable inbox — and nothing
    /// else. Grading happens in `drainWatchQuizInbox`, which the caller
    /// schedules right after.
    ///
    /// **This split is the fix, not an organisational nicety.** Reception is
    /// a synchronous, suspension-free prefix, so the batch is durable before
    /// the first `await`; grading is a long chain of suspension points, each
    /// of which the process can die at. The previous revision instead marked
    /// the batch "processed" up front and then graded, so a death mid-loop
    /// left the nano-session marked done with zero `ReviewLog` rows and
    /// nothing anywhere to replay it from — the comment there reasoned about
    /// exactly this danger but only guarded the `modelContainer` check, a
    /// fraction of the real window. See `WatchQuizBatchInbox` for why no
    /// redelivery would have saved it.
    ///
    /// Idempotent: a `sessionId` already graded, or already queued, is
    /// refused here (see `WatchQuizBatchInbox.admit`).
    ///
    /// Call path this exercises, for a reviewer to re-trace without a build:
    /// `WatchQuizViewModel.selectAnswer` → `WatchSessionManager
    /// .sendQuizReviewBatch` → `transferUserInfo` → `WatchConnectivityManager
    /// .session(_:didReceiveUserInfo:)` → `receiveWatchQuizBatch` (durable
    /// queue) → `scheduleWatchQuizDrain` → `gradePendingBatch` →
    /// `KanaCardRepository.allKanaCards()` (character → `CardDTO` lookup) →
    /// `CardRepository.gradeCard(surface: "watch")` → `ReviewLog`.
    func receiveWatchQuizBatch(_ batch: WatchQuizReviewBatch) {
        guard inbox.admit(batch) else {
            Logger.sync.info("Ignoring already-received Watch quiz batch \(batch.sessionId)")
            return
        }
        Logger.sync.info("Queued Watch quiz batch \(batch.sessionId) with \(batch.events.count) answers")
    }

    /// Grades every batch the inbox holds, oldest first, and empties it as it
    /// goes. Chained behind any drain already running (see `drainTask`).
    ///
    /// A nil `modelContainer` returns without touching the queue: the
    /// batches stay pending and the next trigger — at the very least the
    /// `activate(modelContainer:)` of the next launch — retries them. That
    /// is the same reasoning the previous revision applied to its
    /// "processed" marker, now extended to the whole grading window instead
    /// of only the container check.
    func scheduleWatchQuizDrain() {
        let previous = drainTask
        drainTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.drainWatchQuizInbox()
        }
    }

    private func drainWatchQuizInbox() async {
        guard let container = modelContainer else { return }
        let queued = inbox.pending()
        guard !queued.isEmpty else { return }
        Logger.sync.info("Draining \(queued.count) pending Watch quiz batch(es)")
        for entry in queued {
            await gradePendingBatch(entry, container: container)
        }
    }

    /// Grades one queued nano-session, resuming at `entry.nextEventIndex`.
    private func gradePendingBatch(_ entry: PendingWatchQuizBatch, container: ModelContainer) async {
        let batch = entry.batch
        let context = container.mainContext
        let liveProfileIds = Set(Self.liveProfiles(in: context).map(\.id))
        let attribution = WatchQuizBatchInbox.attribution(
            batchProfileId: batch.profileId,
            activeProfileId: ActiveProfileResolver.fetchActiveProfile(in: context)?.id,
            liveProfileIds: liveProfileIds
        )
        switch attribution {
        case .grade:
            break
        case .deferUntilProfileActive:
            // Kept, not graded: see `WatchQuizBatchAttribution`. Re-tried on
            // the next profile switch and on every launch.
            Logger.sync.info(
                "Watch quiz batch \(batch.sessionId) belongs to another profile — kept queued until it is active"
            )
            return
        case .discardUnattributable, .discardOrphaned:
            Logger.sync.error(
                "Discarding Watch quiz batch \(batch.sessionId): \(attribution.rawValue)"
            )
            inbox.complete(batch.sessionId)
            return
        }

        let cardRepo = CardRepository(modelContainer: container)
        let kanaRepo = KanaCardRepository(cardRepository: cardRepo)

        // Character → card lookup. The Watch quiz pool (`KanaData.hiragana`)
        // is static and doesn't know about `Card`/`CardDTO` at all — it
        // reports which character was the target and which was chosen, and
        // this side resolves that back to a real kana `Card` the same way
        // `KanaCardRepository` already identifies one (`front` membership in
        // the `KanaGroup` catalog).
        let kanaCards = await kanaRepo.allKanaCards()
        let cardByFront = Dictionary(kanaCards.map { ($0.front, $0) }, uniquingKeysWith: { first, _ in first })

        // Re-derived from CURRENT phone-side truth, never trusted from the
        // Watch — see `eligibleKanaFronts`'s doc. A Watch that answered
        // against a stale copy (e.g. it was out of range while the learner
        // changed groups, or while a card crossed reps 0 → 1 elsewhere) must
        // not get that answer graded just because it made it into a batch.
        let eligibleFronts = await eligibleKanaFronts(cardRepository: cardRepo)

        // Re-check attribution: `allKanaCards()`/`eligibleKanaFronts()` above
        // each suspend, and both are scoped to whichever profile is active
        // WHEN THEY RUN (`CardRepository.allCards()` →
        // `activeProfileCards()`) — not the profile the first attribution
        // check above verified. A profile switch landing in that window
        // would otherwise build `cardByFront`/`eligibleFronts` against the
        // NEW profile while grading the OLD profile's batch: the exact
        // cross-profile corruption this whole mechanism exists to prevent,
        // just narrowed from "any time between quiz and delivery" to this
        // one `await` pair. Bail without completing — the batch stays
        // queued and the next drain (profile switch back, or next launch)
        // re-attributes it correctly.
        let recheck = WatchQuizBatchInbox.attribution(
            batchProfileId: batch.profileId,
            activeProfileId: ActiveProfileResolver.fetchActiveProfile(in: context)?.id,
            liveProfileIds: liveProfileIds
        )
        guard recheck == .grade else {
            Logger.sync.info(
                "Watch quiz batch \(batch.sessionId): active profile changed mid-drain — deferring re-check"
            )
            return
        }

        let grader = WatchQuizBatchGrader(
            inbox: inbox,
            cardIdByFront: cardByFront.mapValues(\.id),
            eligibleFronts: eligibleFronts,
            gradeAnswer: { cardId, event in
                // Same grade-mapping thresholds as the iPhone quiz
                // (`DrillUtilities.mapQuizResultToGrade`), so a wrist answer
                // and a phone answer with the same outcome/latency get the
                // same FSRS grade.
                let grade = mapQuizResultToGrade(correct: event.isCorrect, responseTimeMs: event.responseTimeMs)
                await cardRepo.gradeCard(
                    cardId: cardId,
                    grade: grade,
                    responseTimeMs: event.responseTimeMs,
                    now: event.answeredAt,
                    answeredValue: event.answeredCharacter,
                    exerciseType: Self.watchQuizExerciseType,
                    surface: Self.watchSurface
                )
            }
        )
        let tally = await grader.grade(entry)

        Logger.sync.info(
            "Graded \(tally.gradedCount)/\(batch.events.count) Watch quiz answers via gradeCard (surface=watch)"
        )

        // Removed from the queue and marked processed BEFORE the aggregate
        // bump, not after. Two non-atomic stores are involved (the inbox in
        // `UserDefaults`, the RPG counters in SwiftData) and one of the two
        // orders has to be chosen: dying in this window then costs one
        // nano-session's XP bump, whereas the reverse order would re-apply
        // XP and `totalReviewsCompleted` on replay for reviews that happened
        // once. Losing a bonus is a smaller lie than inventing progression,
        // and the `ReviewLog` rows — the part the scheduler and every
        // ReviewLog-derived count read — are already durable at this point
        // either way.
        inbox.complete(batch.sessionId)

        // Aggregate XP / review-count bump — same legacy mechanic
        // `WatchSessionResult` already drove, now fed from the graded
        // batch's own tallies instead of a separate message.
        //
        // All THREE fields are derived from what was actually graded, not
        // from what the Watch sent: an event can be present in the batch and
        // never graded — no matching card, outside the chosen groups, or
        // never-graded-before (`eligibleFronts` guard above). Counting those
        // would inflate `totalReviewsCompleted` / `correctCount` with
        // reviews that produced no `ReviewLog`, the same "counting reviews
        // that did not happen" this path removes for the pitch drill.
        //
        // `xpEarned` was the field that still escaped that rule (GAP-17
        // defect 3): deselecting a kana group between the quiz and the
        // delivery produced zero graded answers, zero `ReviewLog` rows —
        // and a full nano-session's XP anyway. All three now come from the
        // same tally (`WatchQuizBatchTally`).
        processWatchResult(
            WatchSessionResult(
                correctCount: tally.gradedCorrectCount,
                totalQuestions: tally.gradedCount,
                drillType: .kanaQuiz,
                completedAt: batch.events.last?.answeredAt ?? Date(),
                xpEarned: tally.xpEarned
            )
        )
    }

    /// Every profile that hasn't been tombstoned. Used to decide whether an
    /// unstamped or foreign-stamped batch can be attributed at all — see
    /// `WatchQuizBatchInbox.attribution`.
    private static func liveProfiles(in context: ModelContext) -> [UserProfile] {
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.deletedAt == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Logger.sync.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            Logger.sync.info("WCSession activated: \(activationState.rawValue)")
            // Push current state (RPG counters + eligible-kana set) to the
            // Watch as soon as the session activates. Without this,
            // `sendStateToWatch()`'s only other call site was reactive
            // (`processWatchResult`, itself reachable only after the Watch
            // has ALREADY sent something) — so a fresh pairing, a fresh
            // install, or a plain app relaunch would never push an
            // eligible-kana set at all, leaving the Watch stuck on "Nothing
            // to review here yet" even for a learner with plenty of graded
            // kana on the phone. `sendStateToWatch()`'s own guards
            // (`isPaired`, `isWatchAppInstalled`, `modelContainer` present)
            // make this a safe no-op when there's no paired Watch or the
            // container isn't set up yet.
            Task { @MainActor in
                sendStateToWatch()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Logger.sync.info("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Logger.sync.info("WCSession deactivated — reactivating")
        session.activate()
    }

    /// Receives queued Watch payloads via transferUserInfo — either a
    /// per-card `WatchQuizReviewBatch` (kana quiz, chantier #46) or a
    /// legacy aggregate-only `WatchSessionResult` (pitch drill, or an old
    /// Watch build). Tried in that order; the two formats' required keys
    /// don't overlap (see `WatchQuizReviewBatch.fromDictionary`'s doc), so
    /// this never misparses one as the other.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        if let batch = WatchQuizReviewBatch.fromDictionary(userInfo) {
            Task { @MainActor in
                // `receiveWatchQuizBatch` is the SYNCHRONOUS prefix of this
                // hop: it persists the batch before the first suspension
                // point, so the nano-session survives a process death at any
                // `await` inside the drain that follows. It also makes two
                // interleaved delivery `Task`s for the same `sessionId`
                // collapse into one grading pass, since the second one finds
                // the first's entry already queued.
                receiveWatchQuizBatch(batch)
                scheduleWatchQuizDrain()
            }
            return
        }

        guard let result = WatchSessionResult.fromDictionary(userInfo) else {
            Logger.sync.warning("Received unrecognized userInfo from Watch")
            return
        }

        Task { @MainActor in
            processWatchResult(result)
        }
    }

    /// Receives application context updates from Watch.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = WatchSyncPayload.fromDictionary(applicationContext) else {
            Logger.sync.warning("Received unrecognized applicationContext from Watch")
            return
        }

        Logger.sync.info("Received state from Watch: level=\(payload.level), xp=\(payload.xp)")

        Task { @MainActor in
            guard let container = modelContainer else { return }
            let context = container.mainContext
            guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }

            let localPayload = WatchSyncPayload(
                xp: state.xp,
                level: state.level,
                totalReviews: state.totalReviewsCompleted,
                dueCardCount: 0,
                source: .iPhone
            )

            let winner = SyncConflictResolver.resolve(local: localPayload, remote: payload)
            if winner.source == .watch {
                state.xp = winner.xp
                state.level = winner.level
                state.totalReviewsCompleted = winner.totalReviews
                do {
                    try context.save()
                } catch {
                    Logger.sync.error("Failed to save synced Watch state: \(error.localizedDescription)")
                }
                Logger.sync.info("Applied Watch state: level=\(winner.level), xp=\(winner.xp)")
            }
        }
    }
}
