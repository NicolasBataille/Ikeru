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
    /// inbox's DURABLE state while each grade is in flight — which is exactly
    /// the state a process death at that instant would leave behind, whether
    /// it lands just before `gradeCard` or just after it returns (the two are
    /// deliberately indistinguishable on disk; see `WatchQuizBatchGrader
    /// .grade`).
    private final class GradeRecorder {
        var graded: [String] = []
        var checkpointDuringEachGrade: [PendingWatchQuizBatch] = []
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
                    recorder.checkpointDuringEachGrade.append(entry)
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

        // "The process died with answer #4's `gradeCard` in flight." That
        // instant's persisted state is the 4th captured checkpoint: answer #4
        // is already consumed (`nextEventIndex == 4`) but not yet counted
        // (`gradedCount == 3`), because the resume point moves before the
        // side effect and the counters only after it.
        let crashState = firstRecorder.checkpointDuringEachGrade[3]
        #expect(crashState.nextEventIndex == 4)
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

        // Only the six answers past the resume point are re-sent to
        // `gradeCard`: the already-written ReviewLogs are not duplicated and
        // their FSRS transitions are not re-applied — including answer #4's,
        // which may or may not have landed before the crash. That ambiguity
        // is resolved in the losing direction on purpose.
        #expect(replayRecorder.graded.count == 6)
        // The counters carried across the interruption cover the rest of the
        // nano-session: 9 of 10, under-counting the interrupted answer rather
        // than re-grading it. `ReviewLog` — the authoritative record — holds
        // either 9 or 10 rows depending on where exactly the crash landed;
        // neither is more than the learner actually answered.
        #expect(tally.gradedCount == 9)
        #expect(tally.gradedCorrectCount == 7)
        #expect(tally.xpEarned == 7 * WatchQuizReviewBatch.xpPerCorrectAnswer)
    }

    /// Ten answers, all correct, each one identifiable by its index
    /// (`responseTimeMs`) so a re-graded answer is visible as a duplicate
    /// rather than hiding behind a repeated `targetCharacter`.
    private func makeIndexedBatch() -> WatchQuizReviewBatch {
        let fronts = ["あ", "い", "う", "え", "お"]
        let events = (0..<10).map { index in
            WatchQuizReviewBatch.Event(
                targetCharacter: fronts[index % fronts.count],
                answeredCharacter: fronts[index % fronts.count],
                isCorrect: true,
                responseTimeMs: index,
                answeredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
        return WatchQuizReviewBatch(
            events: events,
            xpEarned: WatchQuizReviewBatch.xp(forCorrectAnswers: 10),
            profileId: nil
        )
    }

    @Test("a death AFTER a gradeCard returns, before its checkpoint, must not re-grade that answer")
    func deathBetweenGradeAndCheckpointDoesNotDuplicate() async {
        let fronts: Set<String> = ["あ", "い", "う", "え", "お"]
        let batch = makeIndexedBatch()

        // Pass 1. The snapshot taken INSIDE `gradeAnswer` is the durable
        // state at the instant that answer's `gradeCard` has just returned:
        // the `ReviewLog` row exists, and whatever the inbox holds right now
        // is all a relaunch would find.
        let inbox = makeInbox()
        #expect(inbox.admit(batch))
        var firstPassGraded: [Int] = []
        var stateWhenGradeReturned: [PendingWatchQuizBatch] = []
        let firstGrader = WatchQuizBatchGrader(
            inbox: inbox,
            cardIdByFront: Dictionary(uniqueKeysWithValues: fronts.map { ($0, UUID()) }),
            eligibleFronts: fronts,
            gradeAnswer: { _, event in
                firstPassGraded.append(event.responseTimeMs)
                if let entry = inbox.pending().first { stateWhenGradeReturned.append(entry) }
            }
        )
        _ = await firstGrader.grade(inbox.pending().first!)
        #expect(firstPassGraded == Array(0..<10))

        // "Answer #4 (index 3) was written to the store, then the process was
        // jetsammed before the grader could checkpoint it."
        let crashIndex = 3
        let crashState = stateWhenGradeReturned[crashIndex]
        let gradedBeforeCrash = Array(firstPassGraded.prefix(crashIndex + 1))

        // Relaunch on exactly that persisted state.
        let replayName = "\(suiteName).crashAfterGrade"
        let replayInbox = WatchQuizBatchInbox(defaults: UserDefaults(suiteName: replayName)!)
        defer { UserDefaults.standard.removePersistentDomain(forName: replayName) }
        #expect(replayInbox.admit(batch))
        replayInbox.recordProgress(
            sessionId: batch.sessionId,
            nextEventIndex: crashState.nextEventIndex,
            gradedCount: crashState.gradedCount,
            gradedCorrectCount: crashState.gradedCorrectCount
        )
        var replayGraded: [Int] = []
        let replayGrader = WatchQuizBatchGrader(
            inbox: replayInbox,
            cardIdByFront: Dictionary(uniqueKeysWithValues: fronts.map { ($0, UUID()) }),
            eligibleFronts: fronts,
            gradeAnswer: { _, event in replayGraded.append(event.responseTimeMs) }
        )
        let tally = await replayGrader.grade(replayInbox.pending().first!)

        // The load-bearing assertion: across the crash and the replay, no
        // answer reaches `gradeCard` twice. A duplicate here is a duplicate
        // `ReviewLog` row AND a second FSRS transition for one wrist answer —
        // exactly what `PendingWatchQuizBatch`'s doc says the progress fields
        // exist to prevent, and the opposite of the "losing a bonus is a
        // smaller lie than inventing progression" rule this same drain
        // applies when ordering `inbox.complete()` against the XP bump.
        let allGraded = gradedBeforeCrash + replayGraded
        #expect(
            Set(allGraded).count == allGraded.count,
            "answer(s) graded twice across the crash: \(allGraded)"
        )
        #expect(allGraded.count <= batch.events.count)

        // And the aggregate never claims MORE reviews than were written.
        #expect(tally.gradedCount <= allGraded.count)
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
