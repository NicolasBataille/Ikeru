import Foundation

/// Pure: maps a learner's JLPT estimate to the eligible variety pool.
/// JLPT ordering is N5 < N4 < N3 < N2 < N1 (lower number = harder).
/// Higher levels stack onto lower levels — N4 includes N5; N3 adds more.
/// One entry, `.sakuraConversation`, does not stack on a hardcoded rung: it
/// tracks `DefaultExerciseUnlockService.sakuraConversationMinJLPT` instead
/// (see below), so at least *this pool's* threshold can't silently
/// re-diverge from the unlock gate. That does not mean Sakura conversation
/// is actually scheduled for HOME sessions today — see the note below.
public enum VarietyPoolResolver {

    /// Raw pool by JLPT level (before unlocking constraints).
    public static func pool(for level: JLPTLevel) -> Set<ExerciseType> {
        var result: Set<ExerciseType> = [.listeningSubtitled, .fillInBlank]
        if level >= .n4 {
            result.formUnion([.grammarExercise, .sentenceConstruction])
        }
        if level >= .n3 {
            result.formUnion([.readingPassage, .writingPractice, .listeningUnsubtitled])
        }
        if level >= .n2 {
            result.insert(.speakingPractice)
        }
        // Previously hardcoded to the same `.n2` rung as `.speakingPractice`
        // above, which was stricter than — and independent of — the actual
        // Sakura unlock gate: `DefaultExerciseUnlockService` opened Sakura at
        // N5, but this pool still withheld it from the planner until N2.
        // Reading the real gate here instead of duplicating a threshold at
        // least keeps the *eligibility rung* in sync with the unlock
        // service if its bar ever moves — but that only fixes this pool's
        // own threshold, not the end-to-end HOME scheduling gap: the
        // threshold is currently N5 (the floor), so this branch is
        // unconditionally true, yet `DefaultSessionPlanner.composeHome`
        // still subtracts `untaughtContentTypes` (which lists
        // `.sakuraConversation`) from both the booster and variety pools it
        // builds from this method's output. So HOME sessions still never
        // schedule Sakura conversation, at any JLPT level, until that
        // separate exclusion is revisited. `composeStudy` custom sessions
        // don't go through this resolver at all — they intersect the
        // user's chosen types directly with `unlockedTypes` — so Sakura
        // conversation IS reachable there once unlocked.
        if level >= DefaultExerciseUnlockService.sakuraConversationMinJLPT {
            result.insert(.sakuraConversation)
        }
        return result
    }

    /// Pool intersected with the unlocked set the learner can actually use.
    public static func effectivePool(
        for level: JLPTLevel,
        unlockedTypes: Set<ExerciseType>
    ) -> Set<ExerciseType> {
        pool(for: level).intersection(unlockedTypes)
    }
}
