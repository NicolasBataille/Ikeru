import Foundation
import IkeruCore

// MARK: - SessionExerciseSupport
//
// Pure, stateless mapping helpers used by `SessionViewModel` to attribute XP
// and display labels for exercises. Extracted from `SessionViewModel`
// (remediation 8.4) — no behavior change, these are the same functions with
// the same bodies, just namespaced as static members instead of private
// instance methods.
enum SessionExerciseSupport {

    /// Maps the SRS card currently being graded to the matching
    /// `ExerciseType` Spec A enumerated. The session queue is built from
    /// FSRS cards, so we route by `CardType`. Kana cards live in a
    /// separate drill surface, so they are never observed here — the
    /// fallback returns `.kanaStudy` defensively to keep XP attribution
    /// reading-aligned in any unexpected case.
    static func exerciseTypeForCurrentReview(card: CardDTO) -> ExerciseType {
        switch card.type {
        case .kanji:      return .kanjiStudy
        case .vocabulary: return .vocabularyStudy
        case .grammar:    return .fillInBlank
        case .listening:  return .listeningSubtitled
        }
    }

    /// Maps ANY `ExerciseItem` kind to the matching `ExerciseType` for XP
    /// attribution via `ExerciseXP.award`. `.srsReview` routes by its card's
    /// `CardType` (same rule as `exerciseTypeForCurrentReview`); the non-SRS
    /// kinds map to their capability identifier. Used by
    /// `completeCurrentExercise` so drill exercises award XP for the right skill.
    static func exerciseType(for exercise: ExerciseItem) -> ExerciseType {
        switch exercise {
        case .srsReview(let card):  return exerciseTypeForCurrentReview(card: card)
        case .kanjiStudy:           return .kanjiStudy
        case .grammarExercise:      return .grammarExercise
        case .vocabularyStudy:      return .vocabularyStudy
        case .fillInBlank:          return .fillInBlank
        case .readingPassage:       return .readingPassage
        case .writingPractice:      return .writingPractice
        case .listeningExercise:    return .listeningSubtitled
        case .speakingExercise:     return .speakingPractice
        case .sentenceConstruction: return .sentenceConstruction
        }
    }

    /// Returns a user-facing label for the given exercise type.
    static func exerciseDisplayName(_ exercise: ExerciseItem) -> String {
        switch exercise {
        case .srsReview: "Review"
        case .kanjiStudy: "Kanji"
        case .grammarExercise: "Grammar"
        case .vocabularyStudy: "Vocabulary"
        case .fillInBlank: "Fill in Blank"
        case .readingPassage: "Reading"
        case .writingPractice: "Writing"
        case .listeningExercise: "Listening"
        case .speakingExercise: "Speaking"
        case .sentenceConstruction: "Sentence"
        }
    }

    /// Formats a time interval as "M:SS".
    static func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
