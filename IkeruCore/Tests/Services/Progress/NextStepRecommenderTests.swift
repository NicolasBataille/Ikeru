import Testing
import Foundation
@testable import IkeruCore

@Suite("NextStepRecommender — first-unmet-rung ladder")
struct NextStepRecommenderTests {

    private let hiraganaTotal = KanaProgress.hiraganaTotal   // 46
    private let katakanaTotal = KanaProgress.katakanaTotal   // 46

    /// Snapshot with all advanced rungs satisfied, so a test can isolate one
    /// rung by lowering just its field.
    private func snapshot(
        jlptLevel: JLPTLevel = .n5,
        vocab: Int = 0,
        kanji: Int = 0,
        grammar: Int = 0
    ) -> LearnerSnapshot {
        LearnerSnapshot(
            jlptLevel: jlptLevel,
            vocabularyMasteredFamiliarPlus: vocab,
            kanjiMasteredFamiliarPlus: kanji,
            hiraganaMastered: false,
            katakanaMastered: false,
            grammarPointsFamiliarPlus: grammar,
            listeningAccuracyLast30: 0,
            listeningRecallLast30Days: 0,
            skillBalances: [:],
            dueCardCount: 0,
            hasNewContentQueued: false,
            lastSessionAt: nil
        )
    }

    @Test("Brand-new learner is pointed at hiragana")
    func brandNewLearnsHiragana() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: 0, katakanaMastered: 0),
            snapshot: snapshot()
        )
        #expect(step.stage == .learnHiragana)
        #expect(step.current == 0)
        #expect(step.required == hiraganaTotal)
    }

    @Test("Partial hiragana stays on hiragana with an honest fraction")
    func partialHiragana() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: 12, katakanaMastered: 0),
            snapshot: snapshot()
        )
        #expect(step.stage == .learnHiragana)
        #expect(step.current == 12)
    }

    @Test("Hiragana complete advances to katakana")
    func hiraganaDoneLearnsKatakana() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: 10),
            snapshot: snapshot()
        )
        #expect(step.stage == .learnKatakana)
        #expect(step.current == 10)
        #expect(step.required == katakanaTotal)
    }

    @Test("Both kana complete advances to vocabulary")
    func bothKanaDoneBuildsVocabulary() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(vocab: 0)
        )
        #expect(step.stage == .buildVocabulary)
        #expect(step.required == NextStepRecommender.vocabularyMilestone)
    }

    @Test("Vocabulary milestone met advances to kanji")
    func vocabularyDoneLearnsKanji() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(vocab: NextStepRecommender.vocabularyMilestone, kanji: 0)
        )
        #expect(step.stage == .learnKanji)
    }

    @Test("Kanji milestone met advances to grammar")
    func kanjiDoneStudiesGrammar() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(
                vocab: NextStepRecommender.vocabularyMilestone,
                kanji: NextStepRecommender.kanjiMilestone,
                grammar: 0
            )
        )
        #expect(step.stage == .studyGrammar)
        #expect(step.required == NextStepRecommender.grammarMilestone)
    }

    @Test("Grammar met advances to reading/listening")
    func grammarDoneReadsAndListens() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(
                vocab: NextStepRecommender.vocabularyMilestone,
                kanji: NextStepRecommender.kanjiMilestone,
                grammar: NextStepRecommender.grammarMilestone
            )
        )
        #expect(step.stage == .readingListening)
        #expect(step.required == NextStepRecommender.readingVocabularyMilestone)
    }

    @Test("Rich vocab but still N5 suggests conversing with Sakura")
    func readyForSakura() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(
                jlptLevel: .n5,
                vocab: NextStepRecommender.readingVocabularyMilestone,
                kanji: NextStepRecommender.kanjiMilestone,
                grammar: NextStepRecommender.grammarMilestone
            )
        )
        #expect(step.stage == .converseWithSakura)
    }

    @Test("Everything satisfied and past the JLPT bar is all caught up")
    func allCaughtUp() {
        let step = NextStepRecommender.recommend(
            kana: KanaProgress(hiraganaMastered: hiraganaTotal, katakanaMastered: katakanaTotal),
            snapshot: snapshot(
                jlptLevel: .n4,
                vocab: NextStepRecommender.readingVocabularyMilestone,
                kanji: NextStepRecommender.kanjiMilestone,
                grammar: NextStepRecommender.grammarMilestone
            )
        )
        #expect(step.stage == .allCaughtUp)
    }
}
