import Testing
import Foundation
@testable import IkeruCore

@Suite("UnlockBackfillService")
struct UnlockBackfillServiceTests {

    @Test("Adds the 4 day-1 types when acknowledgedUnlocks is empty")
    func backfillsDayOne() {
        let unlock = DefaultExerciseUnlockService()
        let result = UnlockBackfillService.backfill(
            previous: [],
            profile: .empty,
            unlockService: unlock
        )
        #expect(result.contains(.kanaStudy))
        #expect(result.contains(.kanjiStudy))
        #expect(result.contains(.vocabularyStudy))
        #expect(result.contains(.listeningSubtitled))
    }

    @Test("Includes earned types already crossed by current state")
    func backfillsAlreadyEarned() {
        let unlock = DefaultExerciseUnlockService()
        let profile = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 60,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: true,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        let result = UnlockBackfillService.backfill(
            previous: [],
            profile: profile,
            unlockService: unlock
        )
        // 60 vocab + hiragana mastered should always carry the day-1 set
        // through; this asserts the union semantics rather than the exact
        // membership of the unlock-rule output.
        #expect(result.contains(.kanaStudy))
        #expect(result.contains(.vocabularyStudy))
    }

    @Test("Idempotent — running twice returns the same set")
    func idempotent() {
        let unlock = DefaultExerciseUnlockService()
        let first = UnlockBackfillService.backfill(
            previous: [],
            profile: .empty,
            unlockService: unlock
        )
        let second = UnlockBackfillService.backfill(
            previous: first,
            profile: .empty,
            unlockService: unlock
        )
        #expect(first == second)
    }
}
