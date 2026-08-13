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
///      see `WatchConnectivityManager.isEventEligible`.
@Suite("WatchQuizEligibility")
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

    @Test("isEventEligible accepts an event whose target is in the eligible set")
    func isEventEligibleAcceptsEligibleTarget() {
        let event = makeEvent(target: "あ")
        #expect(WatchConnectivityManager.isEventEligible(event, eligibleFronts: ["あ", "い"]))
    }

    @Test("isEventEligible refuses an event whose target is outside the fresh eligible set")
    func isEventEligibleRefusesIneligibleTarget() {
        // Simulates a stale Watch copy: the Watch believed "ゐ" was
        // eligible (maybe it was, before the learner deselected its group,
        // or before the card had ever been graded) but the PHONE's own
        // freshly recomputed set — the only thing that should matter — no
        // longer contains it.
        let event = makeEvent(target: "ゐ")
        #expect(!WatchConnectivityManager.isEventEligible(event, eligibleFronts: ["あ", "い"]))
    }

    @Test("isEventEligible refuses every event when the eligible set is empty")
    func isEventEligibleRefusesAllWhenEligibleSetEmpty() {
        let event = makeEvent(target: "あ")
        #expect(!WatchConnectivityManager.isEventEligible(event, eligibleFronts: []))
    }
}
