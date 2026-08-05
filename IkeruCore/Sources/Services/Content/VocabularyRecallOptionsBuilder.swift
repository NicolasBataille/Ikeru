import Foundation

// MARK: - VocabularyRecallOptions

/// The answer options for one multiple-choice vocabulary-recall question:
/// the target item plus its distractors, pre-shuffled, with the index of the
/// correct (target) option recorded so the view never has to re-derive it.
///
/// `options` always contains the target exactly once; every entry has a
/// DISTINCT `meaning` (distractors are de-duplicated by meaning and the
/// target's own meaning is excluded from the distractor pool). When the pool
/// is too small to supply the full complement of distractors, `options` holds
/// only as many as could be built — callers inspect `options.count` to decide
/// whether the question is presentable (see `ExerciseTransitionContainer`'s
/// `VocabularyRecallDrillHost`, which falls back to a skip affordance).
public struct VocabularyRecallOptions: Sendable, Equatable {

    /// The shuffled answer options (target + distractors), each with a
    /// distinct meaning. The target appears exactly once.
    public let options: [VocabularyItem]

    /// Index into `options` of the correct (target) answer.
    public let correctIndex: Int

    public init(options: [VocabularyItem], correctIndex: Int) {
        self.options = options
        self.correctIndex = correctIndex
    }

    /// The correct answer's English meaning (convenience for view code).
    public var correctMeaning: String {
        guard options.indices.contains(correctIndex) else { return "" }
        return options[correctIndex].meaning
    }
}

// MARK: - VocabularyRecallOptionsBuilder

/// Pure, seedable builder for multiple-choice vocabulary-recall questions.
///
/// Given a target `VocabularyItem` and a `pool`, it returns the target plus up
/// to `distractorCount` distractors drawn from OTHER pool items, then shuffles
/// them into `VocabularyRecallOptions`. Distractors are de-duplicated by
/// meaning and never share the target's meaning, so the four (by default)
/// choices always read as distinct answers.
///
/// The RNG is injected (`inout G: RandomNumberGenerator`) so tests can pass a
/// seeded generator for deterministic assertions; the convenience overload
/// defaults to `SystemRandomNumberGenerator` for production call sites.
///
/// Stateless / `Sendable`, no I/O — Swift 6 strict-concurrency clean.
public enum VocabularyRecallOptionsBuilder {

    /// Default number of distractors (→ a 4-option question).
    public static let defaultDistractorCount = 3

    /// Builds the shuffled answer options for a recall question.
    ///
    /// - Parameters:
    ///   - target: The vocabulary item being tested (the correct answer).
    ///   - pool: Candidate items to draw distractors from. May contain the
    ///     target and/or items that share meanings — both are handled: the
    ///     target's meaning is excluded and distractor meanings are de-duped.
    ///   - distractorCount: How many distractors to include (default 3).
    ///   - generator: Injected RNG for deterministic shuffling in tests.
    /// - Returns: `VocabularyRecallOptions` with the target + as many distinct
    ///   distractors as the pool allows (fewer than `distractorCount` when the
    ///   pool is too small), and the recorded index of the correct answer.
    public static func build<G: RandomNumberGenerator>(
        target: VocabularyItem,
        pool: [VocabularyItem],
        distractorCount: Int = defaultDistractorCount,
        using generator: inout G
    ) -> VocabularyRecallOptions {
        // Exclude the target's own meaning up front so a pool item that shares
        // it (including the target itself) can never become a distractor —
        // guarantees the correct meaning appears exactly once in `options`.
        var seenMeanings: Set<String> = [target.meaning]
        var distractors: [VocabularyItem] = []

        let cap = max(0, distractorCount)
        for item in pool.shuffled(using: &generator) {
            guard distractors.count < cap else { break }
            guard !seenMeanings.contains(item.meaning) else { continue }
            seenMeanings.insert(item.meaning)
            distractors.append(item)
        }

        let options = ([target] + distractors).shuffled(using: &generator)
        // Locate the target by identity — robust even if a distractor happens
        // to be `==` the target by value (ids differ, so this is unambiguous).
        // `options` always contains `target`, so this lookup can't miss today.
        // Guard it loudly anyway: in a learning app, silently marking the wrong
        // option "correct" (teaching a wrong answer) is worse than a debug crash
        // if a future change ever breaks that invariant — release degrades safely.
        guard let correctIndex = options.firstIndex(where: { $0.id == target.id }) else {
            assertionFailure("VocabularyRecallOptions built without the target present in options")
            return VocabularyRecallOptions(options: options, correctIndex: 0)
        }
        return VocabularyRecallOptions(options: options, correctIndex: correctIndex)
    }

    /// Convenience overload using a fresh `SystemRandomNumberGenerator`.
    /// Production call sites use this; tests use the `using:` overload with a
    /// seeded generator.
    public static func build(
        target: VocabularyItem,
        pool: [VocabularyItem],
        distractorCount: Int = defaultDistractorCount
    ) -> VocabularyRecallOptions {
        var generator = SystemRandomNumberGenerator()
        return build(
            target: target,
            pool: pool,
            distractorCount: distractorCount,
            using: &generator
        )
    }
}
