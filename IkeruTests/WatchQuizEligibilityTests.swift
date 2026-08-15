import Testing
import Foundation
import IkeruCore
@testable import Ikeru

/// Pure-Swift coverage for the two defects closed by the "Watch quiz scope
/// and sync" chantier — no simulator, no `WCSession`, no `WatchSessionManager`
/// singleton involved:
///
///  (a) the Watch quiz pool must be restricted to the eligible-kana set
///      synced from the iPhone (chosen groups ∩ already graded), not the
///      full hiragana catalog — see `WatchEligibleKanaPayload
///      .filterKanaEntries`, which `WatchQuizViewModel.eligiblePool`
///      delegates to.
///  (b) the iPhone must refuse to grade a Watch-submitted answer whose
///      target character isn't in a FRESHLY recomputed eligible set, even
///      if the Watch's own (possibly stale) copy thought it was eligible —
///      see `WatchQuizBatchGrader.disposition(for:)`, which is the decision
///      the production grading loop branches on (it used to be
///      `WatchConnectivityManager.isEventEligible`, moved with GAP-17 so the
///      whole loop, not just this predicate, became testable).
@Suite("WatchQuizEligibility")
@MainActor
struct WatchQuizEligibilityTests {

    // MARK: - (a) Pool filtering

    @Test("filterKanaEntries keeps only entries whose character is eligible")
    func filterKanaEntriesRestrictsToEligibleCharacters() {
        let pool = KanaData.hiragana
        let eligible = ["あ", "い", "う"]

        let filtered = WatchEligibleKanaPayload.filterKanaEntries(pool, toCharacters: eligible)

        #expect(filtered.count == 3)
        #expect(Set(filtered.map(\.character)) == Set(eligible))
    }

    @Test("filterKanaEntries ignores characters not present in the pool")
    func filterKanaEntriesIgnoresUnknownCharacters() {
        let pool = KanaData.hiragana
        // "ア" is katakana — never present in the hiragana pool — and "ん"
        // is a real hiragana entry, so only the latter should survive.
        let filtered = WatchEligibleKanaPayload.filterKanaEntries(pool, toCharacters: ["ア", "ん"])

        #expect(filtered.map(\.character) == ["ん"])
    }

    // MARK: - (a) Empty-set case

    @Test("filterKanaEntries returns an empty pool for an empty eligible set")
    func filterKanaEntriesEmptyEligibleSetYieldsEmptyPool() {
        let filtered = WatchEligibleKanaPayload.filterKanaEntries(KanaData.hiragana, toCharacters: [])
        #expect(filtered.isEmpty)
    }

    // `WatchQuizViewModel.eligiblePool` itself lives in the watchOS-only
    // `IkeruWatch` target, which this app-target test suite (`@testable
    // import Ikeru`) has no visibility into — there is no watchOS test
    // target in this project to run a direct test against it (see the type's
    // own doc comment). It is a thin delegate to
    // `WatchEligibleKanaPayload.filterKanaEntries(KanaData.hiragana,
    // toCharacters:)`, so the tests above already exercise its full logic;
    // the two below pin the SAME scenarios `WatchQuizViewModel.startSession`
    // relies on, against the exact call it makes.

    @Test("the hiragana catalog filtered by an empty eligible set is empty — mirrors a never-synced Watch")
    func hiraganaCatalogEmptyBeforeAnySync() {
        // Mirrors `WatchSessionManager.eligibleKanaCharacters`'s own default
        // (`[]`, not "everything") for a Watch that hasn't received an
        // applicationContext yet — see its doc comment.
        let pool = WatchEligibleKanaPayload.filterKanaEntries(KanaData.hiragana, toCharacters: [])
        #expect(pool.isEmpty)
    }

    @Test("the hiragana catalog filtered by a katakana-only eligible set is empty")
    func hiraganaCatalogKatakanaOnlySelectionYieldsEmptyPool() {
        // The quiz has no katakana mode yet — a learner who has only
        // chosen/graded katakana must see an honest empty pool, not a silent
        // fallback to the full hiragana catalog.
        let pool = WatchEligibleKanaPayload.filterKanaEntries(KanaData.hiragana, toCharacters: ["ア", "イ", "ウ", "エ"])
        #expect(pool.isEmpty)
    }

    // MARK: - (b) Context round-trip

    @Test("WatchEligibleKanaPayload round-trips through a context dictionary")
    func contextRoundTrip() {
        let payload = WatchEligibleKanaPayload(characters: ["あ", "い"])
        var dict: [String: Any] = ["someOtherKey": 42]
        dict[WatchEligibleKanaPayload.contextKey] = payload.contextValue

        let decoded = WatchEligibleKanaPayload.fromContext(dict)
        #expect(decoded?.characters == ["あ", "い"])
    }

    @Test("WatchEligibleKanaPayload.fromContext is nil when the key is absent")
    func fromContextNilWhenKeyMissing() {
        // A dictionary shaped like an OLDER iPhone build's applicationContext
        // (no eligible-kana key at all) must decode to `nil`, not `[]`-that-
        // looks-like-nil — callers are responsible for treating both the
        // same way, but this type itself must not manufacture an answer.
        let decoded = WatchEligibleKanaPayload.fromContext(["xp": 10, "level": 2])
        #expect(decoded == nil)
    }

    // MARK: - (b) Phone-side grading refusal

    private func makeEvent(target: String) -> WatchQuizReviewBatch.Event {
        WatchQuizReviewBatch.Event(
            targetCharacter: target,
            answeredCharacter: target,
            isCorrect: true,
            responseTimeMs: 1_000,
            answeredAt: Date()
        )
    }

    /// A grader whose card lookup knows every front in `eligibleFronts` plus
    /// anything explicitly listed in `alsoKnownFronts` (a card that exists on
    /// the device but is not currently eligible). Its `gradeAnswer` is never
    /// invoked by these tests — they exercise the decision, not the side
    /// effect (see `WatchQuizBatchInboxTests` for the loop itself).
    private func makeGrader(
        eligibleFronts: Set<String>,
        alsoKnownFronts: Set<String> = []
    ) -> WatchQuizBatchGrader {
        let known = eligibleFronts.union(alsoKnownFronts)
        return WatchQuizBatchGrader(
            inbox: WatchQuizBatchInbox(defaults: UserDefaults(suiteName: "WatchQuizEligibilityTests")!),
            cardIdByFront: Dictionary(uniqueKeysWithValues: known.map { ($0, UUID()) }),
            eligibleFronts: eligibleFronts,
            gradeAnswer: { _, _ in }
        )
    }

    @Test("an event whose target is in the eligible set is graded")
    func dispositionAcceptsEligibleTarget() {
        let grader = makeGrader(eligibleFronts: ["あ", "い"])
        #expect(grader.disposition(for: makeEvent(target: "あ")) == .grade)
    }

    @Test("an event whose target is outside the fresh eligible set is skipped, not graded")
    func dispositionRefusesIneligibleTarget() {
        // Simulates a stale Watch copy: the Watch believed "ゐ" was
        // eligible (maybe it was, before the learner deselected its group,
        // or before the card had ever been graded) but the PHONE's own
        // freshly recomputed set — the only thing that should matter — no
        // longer contains it. The card itself still exists on the device,
        // so this must be the *ineligible* skip, not the *no card* one.
        let grader = makeGrader(eligibleFronts: ["あ", "い"], alsoKnownFronts: ["ゐ"])
        #expect(grader.disposition(for: makeEvent(target: "ゐ")) == .skipIneligible)
    }

    @Test("an event with no matching card on this device is skipped")
    func dispositionRefusesUnknownCharacter() {
        let grader = makeGrader(eligibleFronts: ["あ", "い"])
        #expect(grader.disposition(for: makeEvent(target: "ゑ")) == .skipNoCard)
    }

    @Test("every event is skipped when the eligible set is empty")
    func dispositionRefusesAllWhenEligibleSetEmpty() {
        let grader = makeGrader(eligibleFronts: [], alsoKnownFronts: ["あ"])
        #expect(grader.disposition(for: makeEvent(target: "あ")) == .skipIneligible)
    }
}
