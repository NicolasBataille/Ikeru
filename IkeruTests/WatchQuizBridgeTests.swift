import Testing
import Foundation
import IkeruCore
@testable import Ikeru

/// Replays the three GAP-17 failure scenarios against the code that runs in
/// production, without a simulator or a paired Watch:
///
///  1. **The process dies mid-grading.** Is the nano-session replayable, or
///     gone? Asserted as persisted state at each instant — what exists in the
///     inbox when, and what a relaunch would find.
///  2. **A profile switch between the quiz and the delivery.** Are B's cards
///     protected, and is A's work kept?
///  3. **A kana group deselected between the quiz and the delivery.** Do the
///     three credited fields (reviews, correct, XP) tell the same story?
///
/// Plus the wire compatibility the profile stamp depends on: an old Watch
/// build's payload (no `profileId`) must still decode, and a nil stamp must
/// never put an `NSNull` in a `transferUserInfo` dictionary.
@Suite("WatchQuizBridge")
@MainActor
final class WatchQuizBridgeTests {

    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "WatchQuizBridgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Fixtures

    private func makeInbox() -> WatchQuizBatchInbox {
        WatchQuizBatchInbox(defaults: defaults)
    }

    private func makeEvent(target: String, correct: Bool = true) -> WatchQuizReviewBatch.Event {
        WatchQuizReviewBatch.Event(
            targetCharacter: target,
            answeredCharacter: correct ? target : "ん",
            isCorrect: correct,
            responseTimeMs: 1_200,
            answeredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// A ten-answer nano-session over `fronts`, eight of them correct — the
    /// shape `WatchQuizViewModel` produces (`totalQuestions == 10`).
    private func makeBatch(
        fronts: [String] = ["あ", "い", "う", "え", "お"],
        profileId: UUID? = nil
    ) -> WatchQuizReviewBatch {
        let events = (0..<10).map { index in
            makeEvent(target: fronts[index % fronts.count], correct: index % 5 != 4)
        }
        return WatchQuizReviewBatch(
            events: events,
            xpEarned: WatchQuizReviewBatch.xp(forCorrectAnswers: events.filter(\.isCorrect).count),
            profileId: profileId
        )
    }

    /// Records every answer the grader actually grades, and snapshots the
    /// inbox's DURABLE state at the moment each grade is about to happen —
    /// which is exactly the state a process death at that instant would
    /// leave behind.
    private final class GradeRecorder {
        var graded: [String] = []
        var checkpointBeforeEachGrade: [PendingWatchQuizBatch] = []
    }

    private func makeGrader(
        inbox: WatchQuizBatchInbox,
        knownFronts: Set<String>,
        eligibleFronts: Set<String>,
        recorder: GradeRecorder
    ) -> WatchQuizBatchGrader {
        WatchQuizBatchGrader(
            inbox: inbox,
            cardIdByFront: Dictionary(uniqueKeysWithValues: knownFronts.map { ($0, UUID()) }),
            eligibleFronts: eligibleFronts,
            gradeAnswer: { _, event in
                if let entry = inbox.pending().first {
                    recorder.checkpointBeforeEachGrade.append(entry)
                }
                recorder.graded.append(event.targetCharacter)
            }
        )
    }

    // MARK: - Scenario 1: the process dies mid-grading

    @Test("a received batch is durable before any grading happens, and is not marked processed")
    func receptionPersistsBeforeGrading() {
        let inbox = makeInbox()
        let batch = makeBatch()

        // This is the whole synchronous reception prefix — everything that
        // happens before the first `await` of the grading path.
        #expect(inbox.admit(batch))

        // The state a process death right here would leave: the batch itself
        // is on disk, and it is NOT recorded as processed — so the launch
        // replay (`WatchConnectivityManager.activate`) finds work to do. The
        // pre-GAP-17 code persisted the opposite pair (processed = true, no
        // batch anywhere), which is why the ten answers were unrecoverable.
        #expect(inbox.pending().count == 1)
        #expect(inbox.pending().first?.batch.sessionId == batch.sessionId)
        #expect(inbox.pending().first?.nextEventIndex == 0)
        #expect(!inbox.isProcessed(batch.sessionId))
    }

    @Test("a death mid-grading replays the remaining answers only — never the ones already graded")
    func interruptedGradingResumesWithoutDuplicating() async {
        let fronts: Set<String> = ["あ", "い", "う", "え", "お"]
        let batch = makeBatch()

        // Pass 1 — runs to completion, capturing the durable checkpoint seen
        // at the start of each answer.
        let firstInbox = makeInbox()
        #expect(firstInbox.admit(batch))
        let firstRecorder = GradeRecorder()
        let firstGrader = makeGrader(
            inbox: firstInbox,
            knownFronts: fronts,
            eligibleFronts: fronts,
            recorder: firstRecorder
        )
        _ = await firstGrader.grade(firstInbox.pending().first!)
        #expect(firstRecorder.graded.count == 10)

        // "The process died just as answer #4 was about to be graded." That
        // instant's persisted state is the 4th captured checkpoint: three
        // answers already have their ReviewLog, the rest do not.
        let crashState = firstRecorder.checkpointBeforeEachGrade[3]
        #expect(crashState.nextEventIndex == 3)
        #expect(crashState.gradedCount == 3)

        // Relaunch: a fresh inbox holding exactly that state.
        let replayInbox = WatchQuizBatchInbox(
            defaults: UserDefaults(suiteName: "\(suiteName).replay")!
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suiteName).replay") }
        #expect(replayInbox.admit(batch))
        replayInbox.recordProgress(
            sessionId: batch.sessionId,
            nextEventIndex: crashState.nextEventIndex,
            gradedCount: crashState.gradedCount,
            gradedCorrectCount: crashState.gradedCorrectCount
        )

        let replayRecorder = GradeRecorder()
        let replayGrader = makeGrader(
            inbox: replayInbox,
            knownFronts: fronts,
            eligibleFronts: fronts,
            recorder: replayRecorder
        )
        let tally = await replayGrader.grade(replayInbox.pending().first!)

        // Only the seven un-graded answers are re-sent to `gradeCard`: the
        // three already-written ReviewLogs are not duplicated, and their FSRS
        // transitions are not re-applied.
        #expect(replayRecorder.graded.count == 7)
        // …while the aggregate still covers the whole nano-session, because
        // the counters were carried across the interruption.
        #expect(tally.gradedCount == 10)
        #expect(tally.gradedCorrectCount == 8)
    }

    // MARK: - Scenario 2: the happy path has not regressed

    @Test("a normal nano-session grades every answer and empties the inbox")
    func happyPathGradesEveryAnswer() async {
        let fronts: Set<String> = ["あ", "い", "う", "え", "お"]
        let inbox = makeInbox()
        let batch = makeBatch()
        #expect(inbox.admit(batch))

        let recorder = GradeRecorder()
        let grader = makeGrader(inbox: inbox, knownFronts: fronts, eligibleFronts: fronts, recorder: recorder)
        let tally = await grader.grade(inbox.pending().first!)

        #expect(recorder.graded.count == 10)
        #expect(tally.gradedCount == 10)
        #expect(tally.gradedCorrectCount == 8)
        #expect(tally.xpEarned == 8 * WatchQuizReviewBatch.xpPerCorrectAnswer)

        // The manager removes the entry once the tally is in hand; after that
        // the session is closed for good.
        inbox.complete(batch.sessionId)
        #expect(inbox.pending().isEmpty)
        #expect(inbox.isProcessed(batch.sessionId))
    }

    // MARK: - Scenario 3: profile switch between the quiz and the delivery

    @Test("a batch answered under another profile is never graded on the active one")
    func batchFromAnotherProfileIsNotGradedHere() {
        let profileA = UUID()
        let profileB = UUID()

        #expect(
            WatchQuizBatchInbox.attribution(
                batchProfileId: profileA,
                activeProfileId: profileB,
                liveProfileIds: [profileA, profileB]
            ) == .deferUntilProfileActive
        )
    }

    @Test("that batch is kept, not thrown away — it is graded when its own profile is active again")
    func batchFromAnotherProfileStaysQueued() {
        let profileA = UUID()
        let profileB = UUID()
        let inbox = makeInbox()
        let batch = makeBatch(profileId: profileA)
        #expect(inbox.admit(batch))

        // While B is active the batch is skipped by the drain (attribution
        // above) — the entry must still be there afterwards.
        #expect(inbox.pending().count == 1)
        #expect(!inbox.isProcessed(batch.sessionId))

        // Switching back to A makes it gradable, with nothing lost.
        #expect(
            WatchQuizBatchInbox.attribution(
                batchProfileId: profileA,
                activeProfileId: profileA,
                liveProfileIds: [profileA, profileB]
            ) == .grade
        )
        #expect(inbox.pending().first?.batch.events.count == 10)
    }

    @Test("an unstamped batch is graded on a single-profile device and dropped on a multi-profile one")
    func unstampedBatchAttribution() {
        let onlyProfile = UUID()
        // Old Watch build, one profile: nothing to mis-attribute it to.
        #expect(
            WatchQuizBatchInbox.attribution(
                batchProfileId: nil,
                activeProfileId: onlyProfile,
                liveProfileIds: [onlyProfile]
            ) == .grade
        )
        // Old Watch build, two profiles: unattributable, so dropped rather
        // than credited to whichever happens to be active.
        #expect(
            WatchQuizBatchInbox.attribution(
                batchProfileId: nil,
                activeProfileId: onlyProfile,
                liveProfileIds: [onlyProfile, UUID()]
            ) == .discardUnattributable
        )
    }

    @Test("a batch stamped with a deleted profile is discarded rather than queued forever")
    func orphanedBatchIsDiscarded() {
        let deleted = UUID()
        let live = UUID()
        #expect(
            WatchQuizBatchInbox.attribution(
                batchProfileId: deleted,
                activeProfileId: live,
                liveProfileIds: [live]
            ) == .discardOrphaned
        )
    }

    // MARK: - Scenario 4: kana group deselected between the quiz and the delivery

    @Test("no gradable answer means no reviews, no correct answers and no XP")
    func deselectedGroupCreditsNothing() async {
        let inbox = makeInbox()
        let batch = makeBatch()
        #expect(batch.xpEarned == 40, "the Watch claims a full nano-session's XP")
        #expect(inbox.admit(batch))

        // The learner deselected the group these answers came from: the cards
        // still exist on the device, but nothing is eligible any more.
        let recorder = GradeRecorder()
        let grader = makeGrader(
            inbox: inbox,
            knownFronts: ["あ", "い", "う", "え", "お"],
            eligibleFronts: [],
            recorder: recorder
        )
        let tally = await grader.grade(inbox.pending().first!)

        #expect(recorder.graded.isEmpty)
        #expect(tally.gradedCount == 0)
        #expect(tally.gradedCorrectCount == 0)
        // The defect: 40 XP used to be credited here for zero graded reviews
        // and zero ReviewLog rows.
        #expect(tally.xpEarned == 0)
    }

    @Test("XP never exceeds what the Watch itself claimed for the session")
    func creditedXPIsCappedByTheWatchClaim() {
        #expect(WatchQuizBatchTally.creditedXP(gradedCorrectCount: 10, claimedXP: 5) == 5)
        #expect(WatchQuizBatchTally.creditedXP(gradedCorrectCount: 1, claimedXP: 100)
            == WatchQuizReviewBatch.xpPerCorrectAnswer)
        #expect(WatchQuizBatchTally.creditedXP(gradedCorrectCount: 0, claimedXP: -5) == 0)
    }

    // MARK: - Scenario 5: the same batch delivered twice

    @Test("a redelivered batch produces exactly one grading pass")
    func redeliveryIsIdempotent() {
        let inbox = makeInbox()
        let batch = makeBatch()

        #expect(inbox.admit(batch), "first delivery is queued")
        #expect(!inbox.admit(batch), "a second delivery, before grading, is refused")
        #expect(inbox.pending().count == 1)

        inbox.complete(batch.sessionId)
        #expect(!inbox.admit(batch), "a redelivery after grading is refused too")
        #expect(inbox.pending().isEmpty)
    }

    @Test("the pending queue is bounded")
    func pendingQueueIsCapped() {
        let inbox = makeInbox()
        let batches = (0...WatchQuizBatchInbox.pendingCap).map { _ in makeBatch() }
        for batch in batches {
            #expect(inbox.admit(batch))
        }
        #expect(inbox.pending().count == WatchQuizBatchInbox.pendingCap)
        // FIFO: the oldest queued session is the one dropped.
        #expect(inbox.pending().first?.batch.sessionId == batches[1].sessionId)
    }

    // MARK: - Wire compatibility for the profile stamp

    @Test("an unstamped batch round-trips with no null in the transfer dictionary")
    func unstampedBatchProducesNoNullOnTheWire() {
        let dict = makeBatch(profileId: nil).toDictionary()
        // `transferUserInfo` rejects non-property-list values; an NSNull here
        // would be a hard exception at send time.
        #expect(!dict.values.contains { $0 is NSNull })
        #expect(dict["profileId"] == nil)
        #expect(WatchQuizReviewBatch.fromDictionary(dict)?.profileId == nil)
    }

    @Test("a stamped batch round-trips through the transfer dictionary")
    func stampedBatchRoundTrips() {
        let profileId = UUID()
        let dict = makeBatch(profileId: profileId).toDictionary()
        #expect(WatchQuizReviewBatch.fromDictionary(dict)?.profileId == profileId)
    }

    @Test("a payload from a Watch build that predates the stamp still decodes")
    func legacyPayloadWithoutProfileIdStillDecodes() {
        // Exactly what an older Watch sends: every key except `profileId`.
        var dict = makeBatch(profileId: UUID()).toDictionary()
        dict["profileId"] = nil
        let decoded = WatchQuizReviewBatch.fromDictionary(dict)
        #expect(decoded != nil, "a missing stamp must not turn an old Watch build into data loss")
        #expect(decoded?.profileId == nil)
        #expect(decoded?.events.count == 10)
    }

    @Test("the active profile id travels on the applicationContext the Watch already receives")
    func activeProfileIdIsReadFromApplicationContext() {
        let profileId = UUID()
        var context: [String: Any] = ["xp": 120, "level": 3]
        context[WatchEligibleKanaPayload.contextKey] = ["あ", "い"]
        context[WatchQuizReviewBatch.activeProfileContextKey] = profileId.uuidString

        #expect(WatchQuizReviewBatch.activeProfileId(fromContext: context) == profileId)
        // An iPhone build predating GAP-17 sends no such key: the Watch then
        // stamps nothing rather than guessing.
        #expect(WatchQuizReviewBatch.activeProfileId(fromContext: ["xp": 120]) == nil)
    }
}
