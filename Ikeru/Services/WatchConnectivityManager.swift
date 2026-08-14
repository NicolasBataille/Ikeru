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

    /// Bounded, persisted set of `WatchQuizReviewBatch.sessionId` values
    /// already graded — `transferUserInfo` delivery is guaranteed but not
    /// documented as exactly-once, and a redelivered batch (e.g. a relaunch
    /// racing delivery) must not grade the same answers twice. Persisted
    /// (not just in-memory) because the redelivery this guards against can
    /// happen across a relaunch. Capped so it can't grow unbounded over the
    /// life of an install.
    private static let processedBatchIdsKey = "WatchConnectivityManager.processedBatchIds"
    private static let processedBatchIdsCap = 200

    override private init() {
        super.init()
    }

    // MARK: - Setup

    /// Activates WatchConnectivity if supported.
    /// - Parameter container: The SwiftData model container for persisting received data.
    func activate(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
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

    // MARK: - Send State to Watch

    /// Sends the current RPG state to the Watch via applicationContext.
    func sendStateToWatch() {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else { return }

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

    /// Processes a batch of individually-graded kana quiz answers from the
    /// Watch: grades each one through `CardRepository.gradeCard` — the same
    /// path the iPhone kana quiz uses — so it produces a real `ReviewLog`
    /// (FSRS scheduling, confusion-pair `answeredValue`, provenance) instead
    /// of only moving XP counters. Idempotent: a batch whose `sessionId` was
    /// already processed is skipped entirely.
    ///
    /// Call path this exercises, for a reviewer to re-trace without a build:
    /// `WatchQuizViewModel.selectAnswer` → `WatchSessionManager
    /// .sendQuizReviewBatch` → `transferUserInfo` → `WatchConnectivityManager
    /// .session(_:didReceiveUserInfo:)` → `processWatchQuizBatch` →
    /// `KanaCardRepository.allKanaCards()` (character → `CardDTO` lookup) →
    /// `CardRepository.gradeCard(surface: "watch")` → `ReviewLog`.
    private func processWatchQuizBatch(_ batch: WatchQuizReviewBatch) async {
        guard !isBatchAlreadyProcessed(batch.sessionId) else {
            Logger.sync.info("Ignoring already-processed Watch quiz batch \(batch.sessionId)")
            return
        }
        // Marked processed only once we know we can actually attempt
        // grading (`modelContainer` present) — marking it earlier and then
        // bailing on a nil container would drop the batch forever instead
        // of leaving it eligible for a later retry/redelivery.
        guard let container = modelContainer else { return }
        markBatchProcessed(batch.sessionId)
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

        var gradedEvents: [WatchQuizReviewBatch.Event] = []
        for event in batch.events {
            guard let card = cardByFront[event.targetCharacter] else {
                // No matching kana card on this device — e.g. the learner
                // hasn't chosen that kana group yet, or purged an unstarted
                // one. Skip rather than crash or grade the wrong card; the
                // event is logged, not silently dropped.
                Logger.sync.warning(
                    "Watch quiz answer for \(event.targetCharacter) has no matching kana card — skipped"
                )
                continue
            }

            guard Self.isEventEligible(event, eligibleFronts: eligibleFronts) else {
                // The card exists, but is outside the learner's current
                // group selection or was never graded before (`reps == 0`)
                // — grading it here would either quiz on an un-chosen group
                // or reintroduce the first-grade noise the P2 presentation
                // phase exists to remove. See `eligibleKanaFronts`.
                Logger.sync.warning(
                    "Watch quiz answer for \(event.targetCharacter) is not eligible for grading — skipped"
                )
                continue
            }

            // Same grade-mapping thresholds as the iPhone quiz
            // (`DrillUtilities.mapQuizResultToGrade`), so a wrist answer and
            // a phone answer with the same outcome/latency get the same
            // FSRS grade.
            let grade = mapQuizResultToGrade(correct: event.isCorrect, responseTimeMs: event.responseTimeMs)

            await cardRepo.gradeCard(
                cardId: card.id,
                grade: grade,
                responseTimeMs: event.responseTimeMs,
                now: event.answeredAt,
                answeredValue: event.answeredCharacter,
                exerciseType: Self.watchQuizExerciseType,
                surface: Self.watchSurface
            )
            gradedEvents.append(event)
        }

        let gradedCount = gradedEvents.count
        Logger.sync.info(
            "Graded \(gradedCount)/\(batch.events.count) Watch quiz answers via gradeCard (surface=watch)"
        )

        // Aggregate XP / review-count bump — same legacy mechanic
        // `WatchSessionResult` already drove, now fed from the graded
        // batch's own tallies instead of a separate message.
        //
        // Both `correctCount` and `totalQuestions` (below) are derived from
        // `gradedEvents`, NOT `batch.events`: an event can be present in the
        // batch but never graded — no matching card, outside the chosen
        // groups, or never-graded-before (`eligibleFronts` guard above) —
        // and counting those would inflate `totalReviewsCompleted` /
        // `correctCount` with reviews that produced no `ReviewLog`, the same
        // "counting reviews that did not happen" this change removes for the
        // pitch drill. Deriving both from the same `gradedEvents` list also
        // keeps them consistent with each other (a correctCount that could
        // exceed totalQuestions was a latent risk before this: the watch
        // could send more "correct" events than cards actually got graded).
        let correctCount = gradedEvents.filter(\.isCorrect).count
        processWatchResult(
            WatchSessionResult(
                correctCount: correctCount,
                totalQuestions: gradedCount,
                drillType: .kanaQuiz,
                completedAt: batch.events.last?.answeredAt ?? Date(),
                xpEarned: batch.xpEarned
            )
        )
    }

    // MARK: - Eligibility guard

    /// Whether `event` may be graded, given the `eligibleFronts` computed
    /// FRESH from current phone-side state (see `eligibleKanaFronts`).
    /// Extracted as a pure, `nonisolated` static function — no
    /// `ModelContainer`/`CardRepository` involved — specifically so the
    /// phone-side depth guard ("refuse to grade a card the Watch sent that
    /// isn't eligible, even though the Watch itself thought it was") is
    /// testable without a simulator.
    nonisolated static func isEventEligible(_ event: WatchQuizReviewBatch.Event, eligibleFronts: Set<String>) -> Bool {
        eligibleFronts.contains(event.targetCharacter)
    }

    // MARK: - Idempotency

    private func isBatchAlreadyProcessed(_ sessionId: UUID) -> Bool {
        processedBatchIds().contains(sessionId.uuidString)
    }

    private func markBatchProcessed(_ sessionId: UUID) {
        var ids = processedBatchIds()
        ids.append(sessionId.uuidString)
        if ids.count > Self.processedBatchIdsCap {
            ids.removeFirst(ids.count - Self.processedBatchIdsCap)
        }
        UserDefaults.standard.set(ids, forKey: Self.processedBatchIdsKey)
    }

    private func processedBatchIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.processedBatchIdsKey) ?? []
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
                await processWatchQuizBatch(batch)
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
