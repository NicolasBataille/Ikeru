import Foundation

public struct SkillSplit: Sendable, Equatable {
    public let reading: Double
    public let writing: Double
    public let listening: Double
    public let speaking: Double

    public init(reading: Double, writing: Double, listening: Double, speaking: Double) {
        self.reading = reading
        self.writing = writing
        self.listening = listening
        self.speaking = speaking
    }

    public func sum() -> Double { reading + writing + listening + speaking }
}

public enum SkillAttribution {
    public static func split(for type: ExerciseType) -> SkillSplit {
        switch type {
        case .kanaStudy, .kanjiStudy, .vocabularyStudy, .fillInBlank,
             .grammarExercise, .readingPassage:
            return SkillSplit(reading: 1.0, writing: 0.0, listening: 0.0, speaking: 0.0)
        case .sentenceConstruction:
            return SkillSplit(reading: 0.6, writing: 0.4, listening: 0.0, speaking: 0.0)
        case .writingPractice:
            return SkillSplit(reading: 0.2, writing: 0.8, listening: 0.0, speaking: 0.0)
        case .listeningSubtitled:
            return SkillSplit(reading: 0.3, writing: 0.0, listening: 0.7, speaking: 0.0)
        case .listeningUnsubtitled:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 1.0, speaking: 0.0)
        case .speakingPractice:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 0.3, speaking: 0.7)
        case .sakuraConversation:
            return SkillSplit(reading: 0.0, writing: 0.0, listening: 0.5, speaking: 0.5)
        }
    }
}
