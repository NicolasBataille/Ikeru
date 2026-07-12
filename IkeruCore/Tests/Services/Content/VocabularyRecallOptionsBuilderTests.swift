import Testing
import Foundation
@testable import IkeruCore

/// Unit coverage for the pure, seedable multiple-choice recall option builder
/// (Phase 4.1 Tier-2 part 2). Every case injects a deterministic RNG so the
/// shuffled order and distractor selection are reproducible.
@Suite("VocabularyRecallOptionsBuilder")
struct VocabularyRecallOptionsBuilderTests {

    // MARK: - Deterministic RNG

    /// SplitMix64 — a tiny, fully deterministic `RandomNumberGenerator` for
    /// reproducible shuffles. Not cryptographic; test-only.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Fixtures

    private func item(_ meaning: String, japanese: String? = nil) -> VocabularyItem {
        VocabularyItem(
            japanese: japanese ?? meaning,
            reading: "reading-\(meaning)",
            meaning: meaning,
            jlptLevel: .n5
        )
    }

    /// A pool of 6 distinct-meaning items (target + 5 candidates).
    private func richPool(target: VocabularyItem) -> [VocabularyItem] {
        [target] + ["two", "three", "four", "five", "six"].map { item($0) }
    }

    // MARK: - Tests

    @Test("Correct answer is always present and correctIndex points at it")
    func correctAnswerPresent() {
        let target = item("one")
        var rng = SeededGenerator(seed: 1)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: richPool(target: target),
            using: &rng
        )
        #expect(result.options.contains { $0.id == target.id })
        #expect(result.options[result.correctIndex].id == target.id)
        #expect(result.correctMeaning == "one")
    }

    @Test("No duplicate meanings among the options")
    func noDuplicateMeanings() {
        let target = item("one")
        // Pool intentionally seeds duplicate meanings ("two" twice) to prove
        // the de-dupe: only one "two" may survive.
        let pool = [target, item("two"), item("two"), item("three"), item("four")]
        var rng = SeededGenerator(seed: 7)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: pool,
            using: &rng
        )
        let meanings = result.options.map(\.meaning)
        #expect(Set(meanings).count == meanings.count, "meanings must be unique: \(meanings)")
    }

    @Test("Distractor count is respected (target + N distractors)")
    func distractorCountRespected() {
        let target = item("one")
        var rng = SeededGenerator(seed: 3)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: richPool(target: target),
            distractorCount: 3,
            using: &rng
        )
        // 1 target + 3 distractors = 4 options.
        #expect(result.options.count == 4)

        var rng2 = SeededGenerator(seed: 3)
        let two = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: richPool(target: target),
            distractorCount: 2,
            using: &rng2
        )
        #expect(two.options.count == 3)
    }

    @Test("Target's meaning appears exactly once, even if the pool repeats it")
    func targetMeaningAppearsExactlyOnce() {
        let target = item("one")
        // Pool contains the target itself AND another item with the same meaning.
        let pool = [target, item("one", japanese: "壱"), item("two"), item("three"), item("four")]
        var rng = SeededGenerator(seed: 11)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: pool,
            using: &rng
        )
        let oneCount = result.options.filter { $0.meaning == "one" }.count
        #expect(oneCount == 1)
    }

    @Test("Order and selection are deterministic under a fixed seed")
    func deterministicUnderFixedSeed() {
        let target = item("one")
        let pool = richPool(target: target)

        var rngA = SeededGenerator(seed: 42)
        let a = VocabularyRecallOptionsBuilder.build(target: target, pool: pool, using: &rngA)

        var rngB = SeededGenerator(seed: 42)
        let b = VocabularyRecallOptionsBuilder.build(target: target, pool: pool, using: &rngB)

        #expect(a.options.map(\.meaning) == b.options.map(\.meaning))
        #expect(a.correctIndex == b.correctIndex)

        // A different seed should be free to produce a different arrangement;
        // regardless, the correct answer must still resolve correctly.
        var rngC = SeededGenerator(seed: 99)
        let c = VocabularyRecallOptionsBuilder.build(target: target, pool: pool, using: &rngC)
        #expect(c.options[c.correctIndex].id == target.id)
    }

    @Test("Tiny pool degrades gracefully: returns as many distractors as exist")
    func tinyPoolDegradesGracefully() {
        let target = item("one")
        // Only one usable distractor available.
        let pool = [target, item("two")]
        var rng = SeededGenerator(seed: 5)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: pool,
            using: &rng
        )
        // Fewer than the requested 3 distractors, but still valid + target present.
        #expect(result.options.count == 2)
        #expect(result.options[result.correctIndex].id == target.id)
        #expect(Set(result.options.map(\.meaning)).count == 2)
    }

    @Test("Empty pool yields the target alone (host will skip the question)")
    func emptyPoolYieldsTargetOnly() {
        let target = item("one")
        var rng = SeededGenerator(seed: 1)
        let result = VocabularyRecallOptionsBuilder.build(
            target: target,
            pool: [],
            using: &rng
        )
        #expect(result.options.count == 1)
        #expect(result.correctIndex == 0)
        #expect(result.options[0].id == target.id)
    }
}
