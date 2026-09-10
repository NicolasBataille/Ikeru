import Foundation

// MARK: - GrammarCloze

/// One fill-in-the-blank grammar question: a sentence with the grammar element
/// removed, the element itself, and the point it teaches.
///
/// The translation is carried beside the sentence, not inside it — the learner
/// needs the meaning to aim at, otherwise several answers fit the hole equally
/// well. `写真を撮っ____ですか。` alone admits three defensible answers; with
/// « Puis-je prendre une photo ? » it admits one.
///
/// Built offline by `scripts/grammar-cloze/generate-cloze.py`, which **refuses
/// to guess**: a point whose element cannot be located verbatim in its example
/// ships without a cloze and is skipped, rather than blanking the wrong span.
/// Measured 2026-08-19: 51 of 51 points produced one.
public struct GrammarCloze: Sendable, Equatable, Identifiable {

    /// The grammar point this question drills.
    public let pointID: Int

    /// The point's title, e.g. `てもいい (Permission)` — shown after answering.
    public let title: String

    /// The JAPANESE sentence with the element replaced by `____`.
    public let sentence: String

    /// The translation in the learner's language, read from the localised
    /// `examples` column at query time — never frozen alongside the sentence.
    /// Freezing it shipped an English gloss under a French UI (device,
    /// 2026-08-19). Empty when the bundle has no translation for that example;
    /// the view then omits the line.
    public let translation: String

    /// The removed element, e.g. `てもいい`. This is the correct answer.
    public let answer: String

    /// The three FIXED wrong answers, stored with the question.
    ///
    /// Fixed, not drawn at random, and that is a correctness requirement rather
    /// than an optimisation. The exercise plays the sentence completed with
    /// whichever option the learner selects, so they can judge it by ear — and
    /// only bundled clips sound like the app's voice. Measured 2026-08-19: with
    /// random distractors the correct completion had a clip 12 times out of 12
    /// and a wrong one 1 time out of 12, so the right answer was audible from
    /// the VOICE alone. Fixing them makes the completions finite (51 x 4) and
    /// therefore generatable.
    public let distractors: [String]

    public var id: Int { pointID }

    public init(pointID: Int, title: String, sentence: String,
                answer: String, translation: String = "",
                distractors: [String] = []) {
        self.pointID = pointID
        self.title = title
        self.sentence = sentence
        self.answer = answer
        self.translation = translation
        self.distractors = distractors
    }

    /// The sentence with `option` in the blank — what the learner hears when
    /// they select it, and what the correction shows once validated.
    public func completed(with option: String) -> String {
        sentence.replacingOccurrences(of: Self.blank, with: option)
    }

    /// The blank marker the generator writes. Views split on it to lay the
    /// sentence out around the hole.
    public static let blank = "____"
}

// MARK: - GrammarClozeOptions

/// The answer options for one cloze question: the correct element plus
/// distractors, pre-shuffled, with the correct index recorded so the view never
/// re-derives it.
public struct GrammarClozeOptions: Sendable, Equatable {

    /// Shuffled answers. The correct one appears exactly once.
    public let options: [String]

    /// Index into `options` of the correct answer.
    public let correctIndex: Int

    public init(options: [String], correctIndex: Int) {
        self.options = options
        self.correctIndex = correctIndex
    }

    public var correctAnswer: String {
        guard options.indices.contains(correctIndex) else { return "" }
        return options[correctIndex]
    }
}

// MARK: - GrammarClozeOptionsBuilder

/// Pure, seedable builder for cloze answer options.
///
/// Mirrors `VocabularyRecallOptionsBuilder`, including the lesson that one cost
/// real money there: **a distractor that is also correct is a broken question.**
/// For vocabulary that meant homophones; here it means two grammar points whose
/// element is the same string, or one whose element is a SUFFIX of another —
/// `てもいい` and `もいい` would both complete `写真を撮っ____ですか。`.
///
/// So distractors are rejected when they equal the answer, when either contains
/// the other, or when they duplicate a distractor already chosen.
public enum GrammarClozeOptionsBuilder {

    public static func build<G: RandomNumberGenerator>(
        answer: String,
        pool: [String],
        distractorCount: Int = 3,
        using generator: inout G
    ) -> GrammarClozeOptions {
        var chosen: [String] = []
        let candidates = pool.shuffled(using: &generator)

        for candidate in candidates where chosen.count < distractorCount {
            guard !candidate.isEmpty else { continue }
            // Ni identique, ni contenu dans la reponse, ni la contenant : sinon
            // le distracteur remplit le trou aussi bien que la reponse.
            guard candidate != answer,
                  !candidate.contains(answer),
                  !answer.contains(candidate) else { continue }
            guard !chosen.contains(candidate) else { continue }
            chosen.append(candidate)
        }

        var options = chosen + [answer]
        options.shuffle(using: &generator)
        let index = options.firstIndex(of: answer) ?? 0
        return GrammarClozeOptions(options: options, correctIndex: index)
    }

    public static func build(
        answer: String,
        pool: [String],
        distractorCount: Int = 3
    ) -> GrammarClozeOptions {
        var generator = SystemRandomNumberGenerator()
        return build(answer: answer, pool: pool,
                     distractorCount: distractorCount, using: &generator)
    }
}
