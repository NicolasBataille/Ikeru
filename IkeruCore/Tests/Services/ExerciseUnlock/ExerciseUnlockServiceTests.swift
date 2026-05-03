import Testing
import Foundation
@testable import IkeruCore

@Suite("ExerciseUnlockService — research-grounded thresholds")
struct ExerciseUnlockServiceTests {

    private let service = DefaultExerciseUnlockService()

    @Test("kanaStudy is unlocked on a fresh profile")
    func dayOneKana() {
        #expect(service.state(for: .kanaStudy, profile: .empty) == .unlocked)
    }

    @Test("kanjiStudy / vocabularyStudy / listeningSubtitled are day-1 unlocked")
    func dayOneSet() {
        for type in [ExerciseType.kanjiStudy, .vocabularyStudy, .listeningSubtitled] {
            #expect(service.state(for: type, profile: .empty) == .unlocked, "type=\(type)")
        }
    }

    @Test("fillInBlank requires 50 vocab familiar+")
    func fillInBlankThreshold() {
        let below = LearnerSnapshot.empty.with(\.vocabularyMasteredFamiliarPlus, 49)
        let at = LearnerSnapshot.empty.with(\.vocabularyMasteredFamiliarPlus, 50)
        #expect(service.state(for: .fillInBlank, profile: below)
            == .locked(reason: .vocabularyMastered(required: 50, current: 49)))
        #expect(service.state(for: .fillInBlank, profile: at) == .unlocked)
    }

    @Test("grammarExercise locks until hiragana fully mastered")
    func grammarBlockedByKana() {
        var p = LearnerSnapshot.empty.with(\.hiraganaMastered, false)
        #expect(service.state(for: .grammarExercise, profile: p)
            == .locked(reason: .kanaMastered(syllabary: .hiragana)))
        p = p.with(\.hiraganaMastered, true)
        #expect(service.state(for: .grammarExercise, profile: p) == .unlocked)
    }

    @Test("sentenceConstruction requires 5 grammar points familiar+")
    func sentenceConstructionThreshold() {
        let below = LearnerSnapshot.empty.with(\.grammarPointsFamiliarPlus, 4)
        let at = LearnerSnapshot.empty.with(\.grammarPointsFamiliarPlus, 5)
        #expect(service.state(for: .sentenceConstruction, profile: below)
            == .locked(reason: .grammarPointsMastered(required: 5, current: 4)))
        #expect(service.state(for: .sentenceConstruction, profile: at) == .unlocked)
    }

    @Test("readingPassage requires 100 vocab + 50 kanji (vocab check first)")
    func readingPassageCompound() {
        // Both unmet: lock reason names vocab (the first guard).
        let neither = LearnerSnapshot.empty
        #expect(service.state(for: .readingPassage, profile: neither)
            == .locked(reason: .vocabularyMastered(required: 100, current: 0)))
        // Vocab met, kanji short: lock reason names kanji.
        var p = LearnerSnapshot.empty
            .with(\.vocabularyMasteredFamiliarPlus, 100)
            .with(\.kanjiMasteredFamiliarPlus, 49)
        #expect(service.state(for: .readingPassage, profile: p)
            == .locked(reason: .kanjiMastered(required: 50, current: 49)))
        p = p.with(\.kanjiMasteredFamiliarPlus, 50)
        #expect(service.state(for: .readingPassage, profile: p) == .unlocked)
    }

    @Test("writingPractice requires both kana scripts + 50 vocab (hiragana checked first)")
    func writingPracticeCompound() {
        // No kana at all: lock reason names hiragana (the first guard).
        let noKana = LearnerSnapshot.empty
        #expect(service.state(for: .writingPractice, profile: noKana)
            == .locked(reason: .kanaMastered(syllabary: .hiragana)))
        // Hiragana mastered, katakana not: lock reason names katakana.
        var p = LearnerSnapshot.empty
            .with(\.hiraganaMastered, true)
            .with(\.katakanaMastered, false)
            .with(\.vocabularyMasteredFamiliarPlus, 50)
        #expect(service.state(for: .writingPractice, profile: p)
            == .locked(reason: .kanaMastered(syllabary: .katakana)))
        p = p.with(\.katakanaMastered, true)
        #expect(service.state(for: .writingPractice, profile: p) == .unlocked)
    }

    @Test("listeningUnsubtitled requires 60 % accuracy over 30-window")
    func listeningUnsubtitled() {
        var p = LearnerSnapshot.empty.with(\.listeningAccuracyLast30, 0.59)
        #expect(service.state(for: .listeningUnsubtitled, profile: p)
            == .locked(reason: .listeningAccuracyOver(required: 0.6, current: 0.59, window: 30)))
        p = p.with(\.listeningAccuracyLast30, 0.6)
        #expect(service.state(for: .listeningUnsubtitled, profile: p) == .unlocked)
    }

    @Test("speakingPractice requires 60 % listening recall over 30 days")
    func speakingPractice() {
        var p = LearnerSnapshot.empty.with(\.listeningRecallLast30Days, 0.45)
        #expect(service.state(for: .speakingPractice, profile: p)
            == .locked(reason: .listeningRecallOver(required: 0.6, current: 0.45, days: 30)))
        p = p.with(\.listeningRecallLast30Days, 0.65)
        #expect(service.state(for: .speakingPractice, profile: p) == .unlocked)
    }

    @Test("sakuraConversation requires JLPT estimate ≥ N4")
    func sakuraConversation() {
        let n5 = LearnerSnapshot.empty.with(\.jlptLevel, .n5)
        #expect(service.state(for: .sakuraConversation, profile: n5)
            == .locked(reason: .jlptLevelReached(required: .n4, current: .n5)))
        let n4 = LearnerSnapshot.empty.with(\.jlptLevel, .n4)
        #expect(service.state(for: .sakuraConversation, profile: n4) == .unlocked)
    }

    @Test("newlyUnlocked returns only types crossed since `previous`")
    func deltaDetection() {
        let before = Set<ExerciseType>([.kanaStudy, .kanjiStudy, .vocabularyStudy, .listeningSubtitled])
        let p = LearnerSnapshot.empty
            .with(\.hiraganaMastered, true)
            .with(\.vocabularyMasteredFamiliarPlus, 50)
        let delta = service.newlyUnlocked(profile: p, previous: before)
        #expect(delta == [.fillInBlank, .grammarExercise])
    }

    @Test("unlockedTypes returns the full set on a maxed profile")
    func fullySet() {
        let p = LearnerSnapshot.empty
            .with(\.jlptLevel, .n1)
            .with(\.vocabularyMasteredFamiliarPlus, 1000)
            .with(\.kanjiMasteredFamiliarPlus, 1000)
            .with(\.hiraganaMastered, true)
            .with(\.katakanaMastered, true)
            .with(\.grammarPointsFamiliarPlus, 100)
            .with(\.listeningAccuracyLast30, 0.95)
            .with(\.listeningRecallLast30Days, 0.95)
        #expect(service.unlockedTypes(profile: p) == Set(ExerciseType.allCases))
    }
}

// Test-only mutation helper.
extension LearnerSnapshot {
    fileprivate func with<V>(_ keyPath: WritableKeyPath<MutableSnapshot, V>, _ value: V) -> LearnerSnapshot {
        var m = MutableSnapshot(self)
        m[keyPath: keyPath] = value
        return m.snapshot
    }

    fileprivate struct MutableSnapshot {
        var jlptLevel: JLPTLevel
        var vocabularyMasteredFamiliarPlus: Int
        var kanjiMasteredFamiliarPlus: Int
        var hiraganaMastered: Bool
        var katakanaMastered: Bool
        var grammarPointsFamiliarPlus: Int
        var listeningAccuracyLast30: Double
        var listeningRecallLast30Days: Double
        var skillBalances: [SkillType: Double]
        var dueCardCount: Int
        var hasNewContentQueued: Bool
        var lastSessionAt: Date?

        init(_ s: LearnerSnapshot) {
            jlptLevel = s.jlptLevel
            vocabularyMasteredFamiliarPlus = s.vocabularyMasteredFamiliarPlus
            kanjiMasteredFamiliarPlus = s.kanjiMasteredFamiliarPlus
            hiraganaMastered = s.hiraganaMastered
            katakanaMastered = s.katakanaMastered
            grammarPointsFamiliarPlus = s.grammarPointsFamiliarPlus
            listeningAccuracyLast30 = s.listeningAccuracyLast30
            listeningRecallLast30Days = s.listeningRecallLast30Days
            skillBalances = s.skillBalances
            dueCardCount = s.dueCardCount
            hasNewContentQueued = s.hasNewContentQueued
            lastSessionAt = s.lastSessionAt
        }

        var snapshot: LearnerSnapshot {
            LearnerSnapshot(
                jlptLevel: jlptLevel,
                vocabularyMasteredFamiliarPlus: vocabularyMasteredFamiliarPlus,
                kanjiMasteredFamiliarPlus: kanjiMasteredFamiliarPlus,
                hiraganaMastered: hiraganaMastered,
                katakanaMastered: katakanaMastered,
                grammarPointsFamiliarPlus: grammarPointsFamiliarPlus,
                listeningAccuracyLast30: listeningAccuracyLast30,
                listeningRecallLast30Days: listeningRecallLast30Days,
                skillBalances: skillBalances,
                dueCardCount: dueCardCount,
                hasNewContentQueued: hasNewContentQueued,
                lastSessionAt: lastSessionAt
            )
        }
    }
}
