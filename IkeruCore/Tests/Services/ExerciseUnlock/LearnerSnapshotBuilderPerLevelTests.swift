import Testing
import Foundation
@testable import IkeruCore

@Suite("LearnerSnapshotBuilder per-level mastery dicts")
struct LearnerSnapshotBuilderPerLevelTests {

    @Test("Vocab card tagged N3 counts toward N3, N2, N1 (cumulative pool)")
    func n3VocabCountsCumulatively() {
        let card = fixture(
            type: .vocabulary,
            front: "tabemono",
            stability: 8.0,
            reps: 4,
            jlptLevel: .n3
        )
        let snap = LearnerSnapshotBuilder.build(
            cards: [card],
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(snap.vocabularyMasteredAtOrBelow[.n3] == 1)
        #expect(snap.vocabularyMasteredAtOrBelow[.n2] == 1)
        #expect(snap.vocabularyMasteredAtOrBelow[.n1] == 1)
        #expect(snap.vocabularyMasteredAtOrBelow[.n4] == 0)
        #expect(snap.vocabularyMasteredAtOrBelow[.n5] == 0)
    }

    @Test("Untagged familiar+ vocab card does NOT count toward any level")
    func untaggedExcluded() {
        let card = fixture(
            type: .vocabulary,
            front: "untagged",
            stability: 8.0,
            reps: 4,
            jlptLevel: nil
        )
        let snap = LearnerSnapshotBuilder.build(
            cards: [card],
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for level in JLPTLevel.allCases {
            #expect(snap.vocabularyMasteredAtOrBelow[level] == 0)
            #expect(snap.kanjiMasteredAtOrBelow[level] == 0)
            #expect(snap.grammarPointsMasteredAtOrBelow[level] == 0)
        }
    }

    @Test("Kanji at N5 counts toward all levels (cumulative)")
    func n5KanjiCumulative() {
        let card = fixture(
            type: .kanji,
            front: "\u{4E00}",
            stability: 8.0,
            reps: 4,
            jlptLevel: .n5
        )
        let snap = LearnerSnapshotBuilder.build(
            cards: [card],
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for level in JLPTLevel.allCases {
            #expect(snap.kanjiMasteredAtOrBelow[level] == 1)
        }
    }

    @Test("Grammar card tagged N4 counts toward N4, N3, N2, N1 — not N5")
    func n4GrammarCumulative() {
        let card = fixture(
            type: .grammar,
            front: "grammar-pt",
            stability: 8.0,
            reps: 4,
            jlptLevel: .n4
        )
        let snap = LearnerSnapshotBuilder.build(
            cards: [card],
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(snap.grammarPointsMasteredAtOrBelow[.n5] == 0)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n4] == 1)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n3] == 1)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n2] == 1)
        #expect(snap.grammarPointsMasteredAtOrBelow[.n1] == 1)
    }

    @Test("Below-familiar vocab card with JLPT tag does NOT count")
    func subfamiliarExcluded() {
        let card = fixture(
            type: .vocabulary,
            front: "learning",
            stability: 0.5,
            reps: 1,
            jlptLevel: .n5
        )
        let snap = LearnerSnapshotBuilder.build(
            cards: [card],
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for level in JLPTLevel.allCases {
            #expect(snap.vocabularyMasteredAtOrBelow[level] == 0)
        }
    }

    @Test("Mixed level vocab — N5 + N3 counts cumulate correctly")
    func mixedLevelsCumulate() {
        let cards = [
            fixture(type: .vocabulary, front: "n5a", stability: 8.0, reps: 4, jlptLevel: .n5),
            fixture(type: .vocabulary, front: "n5b", stability: 8.0, reps: 4, jlptLevel: .n5),
            fixture(type: .vocabulary, front: "n3a", stability: 8.0, reps: 4, jlptLevel: .n3),
        ]
        let snap = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(snap.vocabularyMasteredAtOrBelow[.n5] == 2)
        #expect(snap.vocabularyMasteredAtOrBelow[.n4] == 2)
        #expect(snap.vocabularyMasteredAtOrBelow[.n3] == 3)
        #expect(snap.vocabularyMasteredAtOrBelow[.n2] == 3)
        #expect(snap.vocabularyMasteredAtOrBelow[.n1] == 3)
    }

    private func fixture(
        type: CardType,
        front: String = "x",
        stability: Double = 0,
        reps: Int = 0,
        dueDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        jlptLevel: JLPTLevel? = nil
    ) -> CardDTO {
        CardDTO(
            id: UUID(),
            front: front,
            back: "",
            type: type,
            fsrsState: FSRSState(
                difficulty: 5,
                stability: stability,
                reps: reps,
                lapses: 0,
                lastReview: Date(timeIntervalSince1970: 1_799_000_000)
            ),
            easeFactor: 2.5,
            interval: 1,
            dueDate: dueDate,
            lapseCount: 0,
            leechFlag: false,
            jlptLevel: jlptLevel
        )
    }
}
