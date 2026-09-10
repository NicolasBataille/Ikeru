import Foundation

// MARK: - MasteryBookCounts

/// Aggregate mastery-level counts across everything the app tracks FSRS
/// state for (SRS cards — kana today, kanji/grammar/listening as those
/// pipelines grow — plus the personal vocabulary dictionary). This is the
/// "livret de compétence" (competency booklet) aggregation the 2026-08-10
/// review asked for.
///
/// It deliberately reuses `MasteryLevel` — the exact New/Learning/Familiar/
/// Mastered/Anchored scale already surfaced in the personal vocabulary
/// dictionary's filter chips — rather than inventing a second vocabulary of
/// progress terms. Per the review (OBS-026): the dictionary is "a
/// competency booklet without a cover page"; this type IS that cover page's
/// data, built from the same scale.
///
/// Pure and I/O-free: feed it DTOs already fetched by a repository. No
/// SwiftData access here.
public struct MasteryBookCounts: Equatable, Sendable, Codable {
    public let newCount: Int
    public let learningCount: Int
    public let familiarCount: Int
    public let masteredCount: Int
    public let anchoredCount: Int

    public init(
        newCount: Int = 0,
        learningCount: Int = 0,
        familiarCount: Int = 0,
        masteredCount: Int = 0,
        anchoredCount: Int = 0
    ) {
        self.newCount = newCount
        self.learningCount = learningCount
        self.familiarCount = familiarCount
        self.masteredCount = masteredCount
        self.anchoredCount = anchoredCount
    }

    public func count(_ level: MasteryLevel) -> Int {
        switch level {
        case .new: newCount
        case .learning: learningCount
        case .familiar: familiarCount
        case .mastered: masteredCount
        case .anchored: anchoredCount
        }
    }

    /// Everything currently tracked, at any level.
    public var totalCount: Int {
        newCount + learningCount + familiarCount + masteredCount + anchoredCount
    }

    /// "What I actually know now" — familiar-or-better. This is the single
    /// honest number the Home mirror leads with; it's the same threshold
    /// `KanaProgress` and the exercise-unlock gates already use, so it never
    /// contradicts those surfaces.
    public var knownCount: Int { familiarCount + masteredCount + anchoredCount }

    /// Net change in `knownCount` since a prior snapshot. Can be negative —
    /// lapses moving items back below familiar are reported honestly, not
    /// hidden, matching the product's anti-burnout stance (a quiet mirror,
    /// not a manipulated one).
    public func delta(from previous: MasteryBookCounts) -> Int {
        knownCount - previous.knownCount
    }

    public static func + (lhs: MasteryBookCounts, rhs: MasteryBookCounts) -> MasteryBookCounts {
        MasteryBookCounts(
            newCount: lhs.newCount + rhs.newCount,
            learningCount: lhs.learningCount + rhs.learningCount,
            familiarCount: lhs.familiarCount + rhs.familiarCount,
            masteredCount: lhs.masteredCount + rhs.masteredCount,
            anchoredCount: lhs.anchoredCount + rhs.anchoredCount
        )
    }

    /// Buckets an arbitrary sequence of already-derived mastery levels. Local
    /// accumulators only — no shared or passed-in value is ever mutated; the
    /// immutable `MasteryBookCounts` is built once, at the end.
    public static func from(masteryLevels: some Sequence<MasteryLevel>) -> MasteryBookCounts {
        var new = 0, learning = 0, familiar = 0, mastered = 0, anchored = 0
        for level in masteryLevels {
            switch level {
            case .new: new += 1
            case .learning: learning += 1
            case .familiar: familiar += 1
            case .mastered: mastered += 1
            case .anchored: anchored += 1
            }
        }
        return MasteryBookCounts(
            newCount: new,
            learningCount: learning,
            familiarCount: familiar,
            masteredCount: mastered,
            anchoredCount: anchored
        )
    }

    /// Buckets the SRS card pool (kana today; kanji/grammar/listening as
    /// those pipelines populate `Card` rows).
    public static func from(cards: [CardDTO], now: Date = Date()) -> MasteryBookCounts {
        from(masteryLevels: cards.map { MasteryLevel.from(fsrsState: $0.fsrsState, now: now) })
    }

    /// Buckets the personal vocabulary dictionary. `VocabularyEntryDTO` is a
    /// separate SwiftData model from `Card` (words the learner explicitly
    /// saved or encountered via Sakura/reading), so it needs its own bucket
    /// pass; callers combine the two with `+`.
    public static func from(vocabularyEntries: [VocabularyEntryDTO], now: Date = Date()) -> MasteryBookCounts {
        from(masteryLevels: vocabularyEntries.map { MasteryLevel.from(fsrsState: $0.fsrsState, now: now) })
    }
}
