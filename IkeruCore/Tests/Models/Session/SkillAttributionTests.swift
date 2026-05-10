import Testing
@testable import IkeruCore

@Suite("SkillAttribution.split")
struct SkillAttributionTests {

    @Test("kanaStudy is 100% reading")
    func kana() {
        let s = SkillAttribution.split(for: .kanaStudy)
        #expect(s.reading == 1.0)
        #expect(s.writing == 0.0)
        #expect(s.listening == 0.0)
        #expect(s.speaking == 0.0)
    }

    @Test("listeningSubtitled is 30/70 reading/listening")
    func listeningSubtitled() {
        let s = SkillAttribution.split(for: .listeningSubtitled)
        #expect(s.reading == 0.3)
        #expect(s.listening == 0.7)
    }

    @Test("writingPractice is 20/80 reading/writing")
    func writing() {
        let s = SkillAttribution.split(for: .writingPractice)
        #expect(s.reading == 0.2)
        #expect(s.writing == 0.8)
    }

    @Test("sakuraConversation is 50/50 listening/speaking")
    func sakura() {
        let s = SkillAttribution.split(for: .sakuraConversation)
        #expect(s.listening == 0.5)
        #expect(s.speaking == 0.5)
    }

    @Test("speakingPractice is 30/70 listening/speaking")
    func speaking() {
        let s = SkillAttribution.split(for: .speakingPractice)
        #expect(s.listening == 0.3)
        #expect(s.speaking == 0.7)
    }

    @Test("Every ExerciseType has a split that sums to 1.0")
    func everyTypeSumsToOne() {
        for type in ExerciseType.allCases {
            let s = SkillAttribution.split(for: type)
            #expect(abs(s.sum() - 1.0) < 1e-9, "\(type) split sums to \(s.sum())")
        }
    }
}
