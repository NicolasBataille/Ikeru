import Foundation

public protocol ExerciseUnlockService: Sendable {
    func state(for type: ExerciseType, profile: LearnerSnapshot) -> ExerciseUnlockState
    func unlockedTypes(profile: LearnerSnapshot) -> Set<ExerciseType>
    func newlyUnlocked(profile: LearnerSnapshot, previous: Set<ExerciseType>) -> Set<ExerciseType>
}

/// Default implementation. Pure: no I/O, no state, fully deterministic.
public struct DefaultExerciseUnlockService: ExerciseUnlockService {

    public static let fillInBlankVocabRequired = 50
    public static let sentenceConstructionGrammarRequired = 5
    public static let readingPassageVocabRequired = 100
    public static let readingPassageKanjiRequired = 50
    public static let writingPracticeVocabRequired = 50
    public static let listeningUnsubtitledAccuracyRequired = 0.6
    public static let listeningUnsubtitledWindow = 30
    public static let speakingRecallRequired = 0.6
    public static let speakingRecallWindowDays = 30
    public static let sakuraConversationMinJLPT: JLPTLevel = .n4

    public init() {}

    public func state(for type: ExerciseType, profile p: LearnerSnapshot) -> ExerciseUnlockState {
        switch type {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy, .listeningSubtitled:
            return .unlocked

        case .fillInBlank:
            return p.vocabularyMasteredFamiliarPlus >= Self.fillInBlankVocabRequired
                ? .unlocked
                : .locked(reason: .vocabularyMastered(
                    required: Self.fillInBlankVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))

        case .grammarExercise:
            return p.hiraganaMastered
                ? .unlocked
                : .locked(reason: .kanaMastered(syllabary: .hiragana))

        case .sentenceConstruction:
            return p.grammarPointsFamiliarPlus >= Self.sentenceConstructionGrammarRequired
                ? .unlocked
                : .locked(reason: .grammarPointsMastered(
                    required: Self.sentenceConstructionGrammarRequired,
                    current: p.grammarPointsFamiliarPlus))

        case .readingPassage:
            if p.vocabularyMasteredFamiliarPlus < Self.readingPassageVocabRequired {
                return .locked(reason: .vocabularyMastered(
                    required: Self.readingPassageVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))
            }
            if p.kanjiMasteredFamiliarPlus < Self.readingPassageKanjiRequired {
                return .locked(reason: .kanjiMastered(
                    required: Self.readingPassageKanjiRequired,
                    current: p.kanjiMasteredFamiliarPlus))
            }
            return .unlocked

        case .writingPractice:
            if !p.hiraganaMastered {
                return .locked(reason: .kanaMastered(syllabary: .hiragana))
            }
            if !p.katakanaMastered {
                return .locked(reason: .kanaMastered(syllabary: .katakana))
            }
            if p.vocabularyMasteredFamiliarPlus < Self.writingPracticeVocabRequired {
                return .locked(reason: .vocabularyMastered(
                    required: Self.writingPracticeVocabRequired,
                    current: p.vocabularyMasteredFamiliarPlus))
            }
            return .unlocked

        case .listeningUnsubtitled:
            return p.listeningAccuracyLast30 >= Self.listeningUnsubtitledAccuracyRequired
                ? .unlocked
                : .locked(reason: .listeningAccuracyOver(
                    required: Self.listeningUnsubtitledAccuracyRequired,
                    current: p.listeningAccuracyLast30,
                    window: Self.listeningUnsubtitledWindow))

        case .speakingPractice:
            return p.listeningRecallLast30Days >= Self.speakingRecallRequired
                ? .unlocked
                : .locked(reason: .listeningRecallOver(
                    required: Self.speakingRecallRequired,
                    current: p.listeningRecallLast30Days,
                    days: Self.speakingRecallWindowDays))

        case .sakuraConversation:
            return p.jlptLevel >= Self.sakuraConversationMinJLPT
                ? .unlocked
                : .locked(reason: .jlptLevelReached(
                    required: Self.sakuraConversationMinJLPT,
                    current: p.jlptLevel))
        }
    }

    public func unlockedTypes(profile p: LearnerSnapshot) -> Set<ExerciseType> {
        Set(ExerciseType.allCases.filter { state(for: $0, profile: p).isUnlocked })
    }

    public func newlyUnlocked(profile p: LearnerSnapshot, previous: Set<ExerciseType>) -> Set<ExerciseType> {
        unlockedTypes(profile: p).subtracting(previous)
    }
}
