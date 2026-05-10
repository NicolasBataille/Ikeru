import Testing
import Foundation
@testable import IkeruCore

@Suite("RestDayDetector")
struct RestDayDetectorTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("All four conditions met → rest day")
    func allConditions() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 48, .writing: 47, .speaking: 49],
            dueCardCount: 4,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now))
    }

    @Test("Due cards >= 5 prevents rest day")
    func tooManyDue() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 5,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("Imbalance > 15% prevents rest day")
    func skillImbalance() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 100, .listening: 80, .writing: 60, .speaking: 70],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("Last session > 24h ago expires rest day")
    func expires() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: now.addingTimeInterval(-25 * 3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("New content queue blocks rest day")
    func newContent() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: true,
            lastSessionAt: now.addingTimeInterval(-3600)
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }

    @Test("Nil lastSessionAt prevents rest day (never had a session)")
    func nilLastSession() {
        let p = LearnerSnapshot(
            jlptLevel: .n5,
            vocabularyMasteredFamiliarPlus: 0,
            kanjiMasteredFamiliarPlus: 0,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [.reading: 50, .listening: 50, .writing: 50, .speaking: 50],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
        #expect(RestDayDetector.shouldShowRestDay(profile: p, now: now) == false)
    }
}
