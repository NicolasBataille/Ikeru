import Testing
import Foundation
@testable import IkeruCore

@Suite("LearnerSnapshotBuilder")
struct LearnerSnapshotBuilderTests {

    @Test("Builds vocab + kanji familiar+ counts from cards")
    func vocabKanjiCounts() {
        let cards = [
            fixture(type: .vocabulary, front: "vocab1", stability: 8.0, reps: 3),     // familiar
            fixture(type: .vocabulary, front: "vocab2", stability: 0.5, reps: 1),     // learning (excluded)
            fixture(type: .kanji, front: "\u{4E00}", stability: 30.0, reps: 5),       // mastered
            fixture(type: .kanji, front: "\u{4E8C}", stability: 8.0, reps: 4),        // familiar
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

    @Test("hiraganaMastered flips only when all 46 base kana are familiar+ (vocab cards)")
    func hiraganaDetection() {
        let allHiragana = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん")
        #expect(allHiragana.count == 46)

        // 45 of 46 — gate must NOT flip.
        var fortyFiveCards: [CardDTO] = []
        for ch in allHiragana.prefix(45) {
            fortyFiveCards.append(fixture(type: .vocabulary, front: String(ch), stability: 8.0, reps: 4))
        }
        #expect(fortyFiveCards.count == 45)

        let sFortyFive = LearnerSnapshotBuilder.build(
            cards: fortyFiveCards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(sFortyFive.hiraganaMastered == false)

        // All 46 — gate must flip true. Match production seeding (`.vocabulary`).
        var fortySixCards: [CardDTO] = []
        for ch in allHiragana {
            fortySixCards.append(fixture(type: .vocabulary, front: String(ch), stability: 8.0, reps: 4))
        }
        #expect(fortySixCards.count == 46)

        let sFortySix = LearnerSnapshotBuilder.build(
            cards: fortySixCards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(sFortySix.hiraganaMastered)
        #expect(sFortySix.katakanaMastered == false)
    }

    @Test("katakanaMastered flips only when all 46 base kana are familiar+ (vocab cards)")
    func katakanaDetection() {
        let allKatakana = Array("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン")
        #expect(allKatakana.count == 46)

        // 45 of 46 — gate must NOT flip.
        var fortyFiveCards: [CardDTO] = []
        for ch in allKatakana.prefix(45) {
            fortyFiveCards.append(fixture(type: .vocabulary, front: String(ch), stability: 8.0, reps: 4))
        }

        let sFortyFive = LearnerSnapshotBuilder.build(
            cards: fortyFiveCards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(sFortyFive.katakanaMastered == false)

        // All 46.
        var fortySixCards: [CardDTO] = []
        for ch in allKatakana {
            fortySixCards.append(fixture(type: .vocabulary, front: String(ch), stability: 8.0, reps: 4))
        }

        let sFortySix = LearnerSnapshotBuilder.build(
            cards: fortySixCards,
            jlptLevel: .n5,
            grammarPointsFamiliarPlus: 0,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            hasNewContentQueued: false,
            lastSessionAt: nil,
            now: Date()
        )
        #expect(sFortySix.katakanaMastered)
        #expect(sFortySix.hiraganaMastered == false)
    }

    @Test("Dakuten / voiced kana don't count toward base 46 mastery")
    func dakutenDoesNotCountTowardKana() {
        // 40 base hiragana + 6 dakuten (が ぎ ぐ げ ご ざ) = 46 cards total,
        // but only 40 of the base 46 are mastered → gate must NOT flip.
        let baseFronts = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらり") // 40 chars
        #expect(baseFronts.count == 40)

        let dakutenFronts: [String] = [
            "\u{304C}", // が
            "\u{304E}", // ぎ
            "\u{3050}", // ぐ
            "\u{3052}", // げ
            "\u{3054}", // ご
            "\u{3056}", // ざ
        ]

        var cards: [CardDTO] = []
        for ch in baseFronts {
            cards.append(fixture(type: .vocabulary, front: String(ch), stability: 8.0, reps: 4))
        }
        for front in dakutenFronts {
            cards.append(fixture(type: .vocabulary, front: front, stability: 8.0, reps: 4))
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
        #expect(s.hiraganaMastered == false)
    }

    @Test("kanjiMasteredFamiliarPlus counts only true kanji (not kana, not vocab)")
    func kanjiCountsTrueKanjiOnly() {
        let cards = [
            fixture(type: .kanji, front: "\u{4E00}", stability: 8.0, reps: 4), // 一 — true kanji
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
            now: Date()
        )
        #expect(s.kanjiMasteredFamiliarPlus == 1)
        #expect(s.hiraganaMastered == false)
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

    @Test("Base-kana constant sets contain exactly 46 characters each")
    func boundsConstants() {
        #expect(LearnerSnapshotBuilder.baseHiragana.count == 46)
        #expect(LearnerSnapshotBuilder.baseKatakana.count == 46)
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
