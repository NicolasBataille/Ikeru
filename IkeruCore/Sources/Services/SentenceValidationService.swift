import Foundation
import os

// MARK: - SentenceValidator Protocol

/// Validates sentence construction exercises and generates new exercises.
public protocol SentenceValidator: Sendable {
    /// Validate the learner's arranged tokens against the target sentence.
    func validate(
        arranged: [SentenceToken],
        against target: String
    ) -> SentenceValidationResult

    /// Generate exercises from a given difficulty level.
    func generateExercises(
        from vocabulary: [String],
        level: SentenceDifficulty
    ) -> [SentenceExercise]
}

// MARK: - SentenceValidationService

/// Default implementation of `SentenceValidator`.
/// Validates token arrangements and generates exercises from built-in N5 templates.
public struct SentenceValidationService: SentenceValidator {

    public init() {}

    // MARK: - Validation

    public func validate(
        arranged: [SentenceToken],
        against target: String
    ) -> SentenceValidationResult {
        let arrangedText = arranged.map(\.text).joined()
        let isCorrect = arrangedText == target

        var incorrectPositions: [Int] = []
        if !isCorrect {
            let targetTokenTexts = tokenize(sentence: target).map(\.text)
            let arrangedTexts = arranged.map(\.text)

            for (index, text) in arrangedTexts.enumerated() {
                if index < targetTokenTexts.count {
                    if text != targetTokenTexts[index] {
                        incorrectPositions.append(index)
                    }
                } else {
                    incorrectPositions.append(index)
                }
            }
        }

        return SentenceValidationResult(
            isCorrect: isCorrect,
            correctAnswer: target,
            incorrectPositions: incorrectPositions
        )
    }

    // MARK: - Exercise Generation

    public func generateExercises(
        from vocabulary: [String],
        level: SentenceDifficulty
    ) -> [SentenceExercise] {
        let templates = filteredTemplates(for: level)

        return templates.map { template in
            let tokens = tokenize(sentence: template.sentence)
            let shuffled = shuffleTokens(tokens, original: template.sentence)

            return SentenceExercise(
                targetSentence: template.sentence,
                translation: template.translation,
                reading: template.reading,
                shuffledTokens: shuffled,
                difficulty: level
            )
        }
    }

    // MARK: - Tokenization

    /// Split a sentence string into `SentenceToken` values.
    /// Recognizes common Japanese particles.
    private func tokenize(sentence: String) -> [SentenceToken] {
        let particles: Set<String> = ["は", "が", "を", "に", "で", "と", "も", "の", "へ", "から", "まで", "より", "か"]

        var tokens: [SentenceToken] = []
        var remaining = sentence

        while !remaining.isEmpty {
            var matched = false

            // Try matching a multi-character particle first
            for particle in particles.sorted(by: { $0.count > $1.count }) {
                if remaining.hasPrefix(particle) {
                    tokens.append(SentenceToken(text: particle, isParticle: true))
                    remaining = String(remaining.dropFirst(particle.count))
                    matched = true
                    break
                }
            }

            if !matched {
                // Collect non-particle characters until the next particle or end
                var word = ""
                while !remaining.isEmpty {
                    let foundParticle = particles.sorted(by: { $0.count > $1.count }).first {
                        remaining.hasPrefix($0)
                    }
                    if foundParticle != nil, !word.isEmpty {
                        break
                    } else if foundParticle != nil, word.isEmpty {
                        // This shouldn't happen given the outer check, but safety
                        break
                    }
                    word.append(remaining.removeFirst())
                }
                if !word.isEmpty {
                    tokens.append(SentenceToken(text: word))
                }
            }
        }

        return tokens
    }

    /// Shuffle tokens ensuring they differ from the original order.
    private func shuffleTokens(
        _ tokens: [SentenceToken],
        original: String
    ) -> [SentenceToken] {
        guard tokens.count > 1 else { return tokens }

        var shuffled = tokens
        // Attempt up to 20 times to get a different order
        for _ in 0..<20 {
            shuffled = tokens.shuffled()
            let shuffledText = shuffled.map(\.text).joined()
            if shuffledText != original {
                return shuffled
            }
        }
        // Fallback: reverse if shuffling keeps producing original
        return tokens.reversed()
    }

    // MARK: - Built-in N5 Templates

    /// Filter templates by difficulty level.
    private func filteredTemplates(for level: SentenceDifficulty) -> [SentenceTemplate] {
        Self.n5Templates.filter { $0.difficulty == level }
    }

    /// A template for generating a sentence exercise.
    private struct SentenceTemplate {
        let sentence: String
        let translation: String
        let reading: String
        let difficulty: SentenceDifficulty
    }

    /// Built-in N5 sentence templates covering core particles.
    private static let n5Templates: [SentenceTemplate] = [
        // Beginner (3-4 tokens): は, が, を
        SentenceTemplate(
            sentence: "私は学生です",
            translation: "I am a student.",
            reading: "わたしはがくせいです",
            difficulty: .beginner
        ),
        SentenceTemplate(
            sentence: "猫がいます",
            translation: "There is a cat.",
            reading: "ねこがいます",
            difficulty: .beginner
        ),
        SentenceTemplate(
            sentence: "水を飲みます",
            translation: "I drink water.",
            reading: "みずをのみます",
            difficulty: .beginner
        ),
        SentenceTemplate(
            sentence: "犬が好きです",
            translation: "I like dogs.",
            reading: "いぬがすきです",
            difficulty: .beginner
        ),

        // Intermediate (5-6 tokens): に, で, と, も
        SentenceTemplate(
            sentence: "学校に行きます",
            translation: "I go to school.",
            reading: "がっこうにいきます",
            difficulty: .intermediate
        ),
        SentenceTemplate(
            sentence: "公園で遊びます",
            translation: "I play in the park.",
            reading: "こうえんであそびます",
            difficulty: .intermediate
        ),
        SentenceTemplate(
            sentence: "友達と話します",
            translation: "I talk with a friend.",
            reading: "ともだちとはなします",
            difficulty: .intermediate
        ),
        SentenceTemplate(
            sentence: "私も日本語を勉強します",
            translation: "I also study Japanese.",
            reading: "わたしもにほんごをべんきょうします",
            difficulty: .intermediate
        ),

        // Advanced (7+ tokens): longer sentences with multiple particles
        SentenceTemplate(
            sentence: "毎朝七時に起きます",
            translation: "I wake up at seven every morning.",
            reading: "まいあさしちじにおきます",
            difficulty: .advanced
        ),
        SentenceTemplate(
            sentence: "友達と一緒にレストランで食べます",
            translation: "I eat at a restaurant with a friend.",
            reading: "ともだちといっしょにれすとらんでたべます",
            difficulty: .advanced
        ),
        SentenceTemplate(
            sentence: "日曜日に家族と公園で遊びます",
            translation: "I play in the park with my family on Sunday.",
            reading: "にちようびにかぞくとこうえんであそびます",
            difficulty: .advanced
        ),
        SentenceTemplate(
            sentence: "電車で学校に行きます",
            translation: "I go to school by train.",
            reading: "でんしゃでがっこうにいきます",
            difficulty: .advanced
        ),
    ]
}
