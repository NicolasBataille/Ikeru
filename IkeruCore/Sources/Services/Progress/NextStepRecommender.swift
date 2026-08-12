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
/// Sakura is no longer gated on a JLPT bar (see `recommend` step 7): the
/// unlock service opened it to N5 beginners, and N5 is the floor of
/// `JLPTLevel`, so a JLPT comparison can never fire.
///
/// `converseWithSakura` is the ladder's terminal rung: there is no signal in
/// `LearnerSnapshot` today for "has already conversed with Sakura" (the
/// obvious candidate, `skillBalances[.speaking]`, is shared with
/// `speakingPractice` drills and would be a contaminated proxy — see
/// `recommend` step 7), so once a learner clears rung 6 the honest
/// recommendation is simply "go talk to Sakura", indefinitely. There used to
/// be an `allCaughtUp` rung 8 gated on the same vocabulary milestone as rung
/// 6/7 — a condition that could never be false once rung 7 was reached, i.e.
/// a fake guard that made `allCaughtUp` permanently unreachable. It has been
/// removed rather than left as dead branch; re-add it only alongside a real
/// "has conversed" signal.
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
        /// The ladder's terminal rung — see the type-level doc comment above
        /// for why there is no rung past this one today.
        case converseWithSakura
    }

    public let stage: Stage
    /// Progress toward this rung's goal (0 when the stage has no count).
    public let current: Int
    /// The rung's goal (0 when the stage has no count, e.g. `converseWithSakura`).
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

    /// Returns the first unmet rung of the ladder, falling through to the
    /// terminal `.converseWithSakura` once every earlier rung — including the
    /// vocabulary depth that makes Sakura worthwhile — is satisfied (see step
    /// 7's comment for why that rung has no further gate).
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
        // 7 — Sakura conversation. Previously gated on reaching a JLPT bar
        // (N4), but `DefaultExerciseUnlockService.sakuraConversationMinJLPT`
        // is now N5 — the floor of `JLPTLevel` — so that comparison could
        // never fire again and silently made this rung unreachable, the
        // exact opposite of the intent behind opening Sakura to beginners.
        //
        // A later attempt re-gated this rung on the same vocabulary depth
        // already required by step 6 (`readingVocabularyMilestone`) — but by
        // the time execution reaches this line, step 6's `if` has already
        // proven that condition true, so it was a tautology: an `if` that can
        // never be false is not a guard, it's dead-code theatre, and it made
        // the `.allCaughtUp` rung it gated permanently unreachable too.
        //
        // The honest fix is to stop pretending there is a gate here.
        // `LearnerSnapshot` has no "already conversed with Sakura" signal to
        // check instead (checked `skillBalances`: `.speaking` is shared with
        // `speakingPractice`, so a nonzero value doesn't mean "conversed with
        // Sakura specifically" — a contaminated proxy, not a real one). So
        // `.converseWithSakura` is the ladder's explicit terminal rung: once
        // a learner clears every earlier rung, "go talk to Sakura" is the
        // standing recommendation, unconditionally. A real "all caught up"
        // state can return if a genuine has-conversed signal is added later
        // — it must not be re-added as a tautological guard.
        return NextStep(stage: .converseWithSakura, current: 0, required: 0)
    }
}
