import Foundation

// MARK: - LootBoxQuizQuestion

/// One question in a lootbox challenge quiz: a prompt (typically a card's
/// front) plus a set of answer choices, one of which — `correctAnswer` — is
/// correct. `choices` always contains `correctAnswer` exactly once and is
/// pre-shuffled, so the view layer can render every choice identically
/// without knowing which one is correct until the user taps.
public struct LootBoxQuizQuestion: Sendable, Equatable {
    public let prompt: String
    public let correctAnswer: String
    public let choices: [String]

    public init(prompt: String, correctAnswer: String, choices: [String]) {
        self.prompt = prompt
        self.correctAnswer = correctAnswer
        self.choices = choices
    }
}

// MARK: - LootBoxQuizService

/// Builds lootbox-challenge quiz questions from the user's own SRS cards, so
/// the challenge quizzes real learned/due content instead of a fixed static
/// pool. Pure functions — no I/O, fully unit-testable, deterministic given an
/// injected `RandomNumberGenerator`.
public enum LootBoxQuizService {

    /// Builds one question by picking a random card as the target and
    /// drawing up to 3 distractors from the remaining cards' answers.
    ///
    /// - Parameters:
    ///   - cards: The candidate pool — typically the user's due and/or
    ///     learned cards. Cards with an empty `front` or `back` are skipped
    ///     so the quiz never shows a blank prompt or choice.
    ///   - rng: Source of randomness for target selection, distractor
    ///     sampling, and shuffling. Inject a seeded generator for
    ///     reproducible tests; the app uses `SystemRandomNumberGenerator`.
    /// - Returns: A question drawn from `cards`, or `nil` if `cards` has
    ///   fewer than 2 usable entries — callers should fall back to a generic
    ///   question pool (e.g. kana) in that case, per the "no cards yet"
    ///   requirement.
    public static func makeQuestion(
        from cards: [CardDTO],
        rng: inout some RandomNumberGenerator
    ) -> LootBoxQuizQuestion? {
        let usable = cards.filter {
            !$0.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Need at least a target and one distinct-answer distractor to make
        // a meaningful multiple-choice question.
        guard usable.count >= 2, let target = usable.randomElement(using: &rng) else {
            return nil
        }

        let correctKey = target.back.lowercased()
        var seenAnswers: Set<String> = [correctKey]
        var distractors: [String] = []

        for card in usable.shuffled(using: &rng) where card.id != target.id {
            let key = card.back.lowercased()
            guard !seenAnswers.contains(key) else { continue }
            seenAnswers.insert(key)
            distractors.append(card.back)
            if distractors.count == 3 { break }
        }

        guard !distractors.isEmpty else {
            // Every other card shares the same answer as the target (e.g. a
            // deck of near-duplicates) — no distinct distractor exists.
            return nil
        }

        let choices = ([target.back] + distractors).shuffled(using: &rng)
        return LootBoxQuizQuestion(prompt: target.front, correctAnswer: target.back, choices: choices)
    }
}
