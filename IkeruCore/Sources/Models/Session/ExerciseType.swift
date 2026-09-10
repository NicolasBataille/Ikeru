import Foundation

/// Capability identifier for an exercise. Distinct from `ExerciseItem`
/// (which carries the content payload). Used by `ExerciseUnlockService`
/// and `SessionPlanner` to gate and select exercises by category.
public enum ExerciseType: String, Codable, CaseIterable, Sendable, Hashable {
    case kanaStudy
    case kanjiStudy
    case vocabularyStudy
    case listeningSubtitled
    /// **Retired** (2026-09-09, Nico's ruling on the review-2 leftovers) —
    /// see `retired`. The case stays because `ReviewLog.exerciseType` stores
    /// raw values, and because grammar-card flashcard reviews still use it
    /// as their XP/telemetry identity (`SessionExerciseSupport`).
    case fillInBlank
    case grammarExercise
    case sentenceConstruction
    /// **Retired** (2026-09-09) — see `retired`.
    case readingPassage
    case writingPractice
    case listeningUnsubtitled
    case speakingPractice
    case sakuraConversation

    /// Exercise types withdrawn from the product. Their in-session screens
    /// were never built: both rendered a placeholder whose « Complete » button
    /// graded `.good`, so a learner tapped a button and harvested a success
    /// that entered FSRS (OBS2-023). Removed from every pool on 2026-08-28,
    /// retired outright on 2026-09-09: the grammar cloze already IS a
    /// fill-in-the-blank exercise, and reading has « apporte ton propre
    /// texte ». The one owner of « retired »: the planner never synthesises
    /// them, the unlock service never unlocks them, the pools never list
    /// them, and a Compose sheet must not offer them.
    public static let retired: Set<ExerciseType> = [.fillInBlank, .readingPassage]

    public var isRetired: Bool { Self.retired.contains(self) }

    /// Every type a learner can still be offered.
    public static var activeCases: [ExerciseType] { allCases.filter { !$0.isRetired } }

    /// What the Compose sheet (Étude → « Composer une séance ») offers, in
    /// display order — the explicit opt-in door `untaughtContentTypes`'
    /// justification always named and that never existed until 2026-09-09.
    ///
    /// Only types `DefaultSessionPlanner.synthesise` turns into a LIVE drill
    /// that is what its name says. Deliberately absent:
    /// - `.kanaStudy` — kana is not an SRS card; the planner synthesises
    ///   nothing for it (the kana drill has its own door in Explore).
    /// - `.sakuraConversation` — the planner maps it to the shadowing drill,
    ///   which is not a conversation; Sakura has her own row in Explore.
    /// - `.listeningUnsubtitled` — today it yields the very same
    ///   `.listeningExercise` as `.listeningSubtitled`; offering both would
    ///   promise a difference the drill does not make.
    /// - the retired types.
    /// Locked types ARE listed (the sheet shows them disabled with the reason):
    /// an opt-in door that hides what is locked teaches nothing.
    public static let composableInStudySession: [ExerciseType] = [
        .kanjiStudy, .vocabularyStudy, .grammarExercise, .sentenceConstruction,
        .writingPractice, .listeningSubtitled, .speakingPractice,
    ]

    /// The primary skill this exercise type targets.
    public var skill: SkillType {
        switch self {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy,
             .fillInBlank, .grammarExercise, .readingPassage:
            .reading
        case .writingPractice, .sentenceConstruction:
            .writing
        case .listeningSubtitled, .listeningUnsubtitled:
            .listening
        case .speakingPractice, .sakuraConversation:
            .speaking
        }
    }

    /// Estimated duration in seconds.
    public var estimatedDurationSeconds: Int {
        switch self {
        case .kanaStudy: 25
        case .kanjiStudy: 60
        case .vocabularyStudy: 30
        case .listeningSubtitled: 60
        case .fillInBlank: 20
        case .grammarExercise: 45
        case .sentenceConstruction: 60
        case .readingPassage: 120
        case .writingPractice: 90
        case .listeningUnsubtitled: 75
        case .speakingPractice: 90
        case .sakuraConversation: 180
        }
    }
}
