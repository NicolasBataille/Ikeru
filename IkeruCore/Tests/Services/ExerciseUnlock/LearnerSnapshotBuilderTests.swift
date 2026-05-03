import Testing
import Foundation
@testable import IkeruCore

@Suite("LearnerSnapshotBuilder")
struct LearnerSnapshotBuilderTests {

    @Test("Builds vocab + kanji familiar+ counts from cards")
    func vocabKanjiCounts() {
        let cards = [
            fixture(type: .vocabulary, stability: 8.0, reps: 3),                    // familiar
            fixture(type: .vocabulary, stability: 0.5, reps: 1),                    // learning (excluded)
            fixture(type: .kanji, front: "\u{4E00}", stability: 30.0, reps: 5),     // mastered
            fixture(type: .kanji, front: "\u{4E8C}", stability: 8.0, reps: 4),      // familiar
        ]
        let s = LearnerSnapshotBuilder.build(
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
        #expect(s.vocabularyMasteredFamiliarPlus == 1)
        #expect(s.kanjiMasteredFamiliarPlus == 2)
    }

    @Test("Detects hiragana mastery when all 46 syllabary cards are familiar+")
    func hiraganaDetection() {
        let allHiragana = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
        var cards: [CardDTO] = []
        for ch in allHiragana {
            cards.append(fixture(type: .kanji, front: String(ch), stability: 8.0, reps: 4))
        }
        #expect(cards.count == 46)

        let s = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(s.hiraganaMastered)
        #expect(s.katakanaMastered == false)
    }

    @Test("Counts due cards (dueDate <= now)")
    func dueCount() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cards = [
            fixture(type: .vocabulary, dueDate: now.addingTimeInterval(-3600)),
            fixture(type: .vocabulary, dueDate: now),
            fixture(type: .vocabulary, dueDate: now.addingTimeInterval(3600)),
        ]
        let s = LearnerSnapshotBuilder.build(
            cards: cards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: now
        )
        #expect(s.dueCardCount == 2)
    }

    /// Mirrors the actual `CardDTO` init in
    /// `IkeruCore/Sources/Repositories/CardRepository.swift`. The builder
    /// only reads `type`, `front`, `dueDate`, `fsrsState` — other fields
    /// are defaulted to neutral values.
    private func fixture(
        type: CardType,
        front: String = "x",
        stability: Double = 0,
        reps: Int = 0,
        dueDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
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
            leechFlag: false
        )
    }
}
