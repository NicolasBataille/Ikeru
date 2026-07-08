import Foundation

/// A single, calm "do this next" suggestion derived from the learner's
/// progress. Anti-gamification by design: it returns ONE next step (the first
/// unmet rung of the learning ladder), never a checklist or a pressure stack.
///
/// The ladder, confirmed with the product owner, is sequential and advances a
/// stage once its content reaches FSRS "familiar+" (the same threshold the
/// unlock service and `KanaProgress` already use):
///
///   Hiragana → Katakana → Vocabulary → Kanji → Grammar → Reading/Listening → Sakura
///
/// `current`/`required` expose the rung's progress (e.g. hiragana 12 / 46) so
/// the UI can show a quiet fraction. Localization lives in the app target: the
/// view maps `stage` to `LocalizedStringKey`s (Core's `String(localized:)`
/// resolves the wrong bundle), so this type carries no user-facing strings.
public struct NextStep: Equatable, Sendable {

    /// The learning stage the suggestion points at.
    public enum Stage: String, Sendable, Equatable, CaseIterable {
        case learnHiragana
        case learnKatakana
        case buildVocabulary
        case learnKanji
        case studyGrammar
        case readingListening
        case converseWithSakura
        case allCaughtUp
    }

    public let stage: Stage
    /// Progress toward this rung's goal (0 when the stage has no count).
    public let current: Int
    /// The rung's goal (0 when the stage has no count, e.g. `allCaughtUp`).
    public let required: Int

    public init(stage: Stage, current: Int, required: Int) {
        self.stage = stage
        self.current = current
        self.required = required
    }
}

/// Pure recommender (no I/O). Feed it the kana progress and a `LearnerSnapshot`
/// and it returns the single next step. Mirrors `JLPTReadinessFormula` /
/// `RestDayDetector` as a stateless value-in/value-out helper, so it is trivial
/// to unit-test.
public enum NextStepRecommender {

    /// Vocabulary familiar+ needed before suggesting kanji. Reuses the
    /// fill-in-the-blank unlock threshold so the suggestion and the actual
    /// exercise unlock agree.
    public static let vocabularyMilestone = DefaultExerciseUnlockService.fillInBlankVocabRequired
    /// Kanji familiar+ needed before suggesting grammar (matches the
    /// reading-passage kanji gate).
    public static let kanjiMilestone = DefaultExerciseUnlockService.readingPassageKanjiRequired
    /// Grammar points familiar+ needed before suggesting reading/listening
    /// (matches the sentence-construction gate).
    public static let grammarMilestone = DefaultExerciseUnlockService.sentenceConstructionGrammarRequired
    /// Vocabulary familiar+ that marks "ready for richer reading/listening"
    /// (matches the reading-passage vocab gate).
    public static let readingVocabularyMilestone = DefaultExerciseUnlockService.readingPassageVocabRequired

    /// Returns the first unmet rung of the ladder. `allCaughtUp` only when every
    /// rung is satisfied (including reaching the Sakura JLPT bar).
    public static func recommend(kana: KanaProgress, snapshot: LearnerSnapshot) -> NextStep {
        // 1 — Hiragana (per-character familiar+, out of 46).
        if kana.hiraganaMastered < KanaProgress.hiraganaTotal {
            return NextStep(stage: .learnHiragana,
                            current: kana.hiraganaMastered,
                            required: KanaProgress.hiraganaTotal)
        }
        // 2 — Katakana.
        if kana.katakanaMastered < KanaProgress.katakanaTotal {
            return NextStep(stage: .learnKatakana,
                            current: kana.katakanaMastered,
                            required: KanaProgress.katakanaTotal)
        }
        // 3 — Vocabulary.
        if snapshot.vocabularyMasteredFamiliarPlus < vocabularyMilestone {
            return NextStep(stage: .buildVocabulary,
                            current: snapshot.vocabularyMasteredFamiliarPlus,
                            required: vocabularyMilestone)
        }
        // 4 — Kanji.
        if snapshot.kanjiMasteredFamiliarPlus < kanjiMilestone {
            return NextStep(stage: .learnKanji,
                            current: snapshot.kanjiMasteredFamiliarPlus,
                            required: kanjiMilestone)
        }
        // 5 — Grammar.
        if snapshot.grammarPointsFamiliarPlus < grammarMilestone {
            return NextStep(stage: .studyGrammar,
                            current: snapshot.grammarPointsFamiliarPlus,
                            required: grammarMilestone)
        }
        // 6 — Reading & listening depth (more vocabulary).
        if snapshot.vocabularyMasteredFamiliarPlus < readingVocabularyMilestone {
            return NextStep(stage: .readingListening,
                            current: snapshot.vocabularyMasteredFamiliarPlus,
                            required: readingVocabularyMilestone)
        }
        // 7 — Sakura conversation, gated on reaching the JLPT bar (N4).
        if snapshot.jlptLevel < DefaultExerciseUnlockService.sakuraConversationMinJLPT {
            return NextStep(stage: .converseWithSakura, current: 0, required: 0)
        }
        return NextStep(stage: .allCaughtUp, current: 0, required: 0)
    }
}
