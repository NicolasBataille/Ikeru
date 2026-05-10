import SwiftUI
import IkeruCore

/// Visual metadata per `ExerciseType` for the Étude → Browse grid.
/// Maps each capability to a single Japanese glyph (used as the tile's
/// hero mark) and a localized display label.
enum ExerciseTileTokens {

    static func glyph(for type: ExerciseType) -> String {
        switch type {
        case .kanaStudy:            return "\u{30A2}" // ア
        case .kanjiStudy:           return "\u{6F22}" // 漢
        case .vocabularyStudy:      return "\u{8A9E}" // 語
        case .listeningSubtitled:   return "\u{8033}" // 耳
        case .fillInBlank:          return "\u{7A7A}" // 空
        case .grammarExercise:      return "\u{6587}" // 文
        case .sentenceConstruction: return "\u{7D44}" // 組
        case .readingPassage:       return "\u{8AAD}" // 読
        case .writingPractice:      return "\u{66F8}" // 書
        case .listeningUnsubtitled: return "\u{97F3}" // 音
        case .speakingPractice:     return "\u{53E3}" // 口
        case .sakuraConversation:   return "\u{6843}" // 桜
        }
    }

    static func label(for type: ExerciseType) -> LocalizedStringKey {
        switch type {
        case .kanaStudy:            return "Etude.Type.Kana"
        case .kanjiStudy:           return "Etude.Type.Kanji"
        case .vocabularyStudy:      return "Etude.Type.Vocabulary"
        case .listeningSubtitled:   return "Etude.Type.ListeningSub"
        case .fillInBlank:          return "Etude.Type.FillInBlank"
        case .grammarExercise:      return "Etude.Type.Grammar"
        case .sentenceConstruction: return "Etude.Type.Sentence"
        case .readingPassage:       return "Etude.Type.Reading"
        case .writingPractice:      return "Etude.Type.Writing"
        case .listeningUnsubtitled: return "Etude.Type.ListeningUnsub"
        case .speakingPractice:     return "Etude.Type.Speaking"
        case .sakuraConversation:   return "Etude.Type.Sakura"
        }
    }
}
