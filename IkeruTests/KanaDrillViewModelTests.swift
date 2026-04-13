import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// MARK: - KanaDrillViewModelTests
//
// Exercises the shared KanaDrillViewModel used by both the flashcard and
// 4-choice quiz views. Uses an in-memory SwiftData container so the real
// CardRepository is exercised without touching disk.

@MainActor
@Suite("KanaDrillViewModel")
struct KanaDrillViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeRepoAndCards(group: KanaGroup) async throws -> (CardRepository, [CardDTO]) {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        var cards: [CardDTO] = []
        for character in group.characters {
            let card = await repo.createCard(
                front: character.character,
                back: character.romaji,
                type: .vocabulary
            )
            cards.append(card)
        }
        return (repo, cards)
    }

    // MARK: - Init

    @Test("init seeds first card and zero index")
    func initSetsUpFirstCard() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        #expect(vm.currentIndex == 0)
        #expect(vm.currentCard != nil)
        #expect(vm.isRevealed == false)
        #expect(vm.isAnswered == false)
        #expect(vm.sessionEnded == false)
        #expect(vm.queue.count == cards.count)
    }

    // MARK: - Reveal & predicted intervals

    @Test("reveal populates predicted intervals for all four grades")
    func revealComputesPredictedIntervals() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        vm.reveal()
        #expect(vm.isRevealed == true)
        #expect(vm.predictedIntervals.count == 4)
        for grade in Grade.allCases {
            let interval = vm.predictedIntervals[grade] ?? ""
            #expect(!interval.isEmpty, "interval for \(grade) should not be empty")
        }
    }

    // MARK: - Grade

    @Test("grade(.good) increments correctCount and advances")
    func gradeGoodIncrementsCorrect() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        vm.reveal()
        await vm.grade(.good)
        #expect(vm.correctCount == 1)
        #expect(vm.wrongCount == 0)
        #expect(vm.currentIndex == 1)
        #expect(vm.isRevealed == false)
    }

    @Test("grade(.again) increments wrongCount")
    func gradeAgainIncrementsWrong() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        vm.reveal()
        await vm.grade(.again)
        #expect(vm.wrongCount == 1)
        #expect(vm.correctCount == 0)
    }

    // MARK: - Quiz answer mapping

    @Test("submitQuizAnswer correct + fast time maps to easy")
    func quizFastCorrectMapsEasy() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        #expect(mapQuizResultToGrade(correct: true, responseTimeMs: 1_000) == .easy)
        vm.selectOption(vm.correctOption)
        await vm.submitQuizAnswer()
        #expect(vm.correctCount == 1)
        #expect(vm.isAnswered == true)
    }

    @Test("submitQuizAnswer correct + slow time maps to good")
    func quizSlowCorrectMapsGood() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        #expect(mapQuizResultToGrade(correct: true, responseTimeMs: 3_500) == .good)
        #expect(mapQuizResultToGrade(correct: true, responseTimeMs: 8_000) == .hard)
    }

    @Test("submitQuizAnswer wrong maps to again and increments wrong")
    func quizWrongMapsAgain() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        #expect(mapQuizResultToGrade(correct: false, responseTimeMs: 500) == .again)
        let wrongOption = vm.quizOptions.first { $0 != vm.correctOption }
        try #require(wrongOption != nil)
        vm.selectOption(wrongOption!)
        await vm.submitQuizAnswer()
        #expect(vm.wrongCount == 1)
        #expect(vm.correctCount == 0)
        #expect(vm.selectedOptionCharacter != nil)
    }

    // MARK: - Distractors

    @Test("quiz options are 4 unique values containing the correct answer")
    func quizOptionsValid() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        #expect(vm.quizOptions.count == 4)
        #expect(Set(vm.quizOptions).count == 4)
        #expect(vm.quizOptions.contains(vm.correctOption))
    }

    // MARK: - Advance & session end

    @Test("advance moves to next card and resets per-card state")
    func advanceResetsState() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        vm.reveal()
        vm.advance()
        #expect(vm.currentIndex == 1)
        #expect(vm.isRevealed == false)
        #expect(vm.selectedOption == nil)
        #expect(vm.predictedIntervals.isEmpty)
    }

    @Test("session ends after grading the last card")
    func sessionEnds() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        for _ in 0..<cards.count {
            vm.reveal()
            await vm.grade(.good)
        }
        #expect(vm.sessionEnded == true)
        #expect(vm.currentCard == nil)
        #expect(vm.correctCount == cards.count)
    }

    // MARK: - Restart

    @Test("restart resets stats and queue")
    func restartResets() async throws {
        let (repo, cards) = try await makeRepoAndCards(group: .hVowels)
        let vm = KanaDrillViewModel(mode: .freePractice, queue: cards, cardRepository: repo)
        vm.reveal()
        await vm.grade(.again)
        vm.restart()
        #expect(vm.currentIndex == 0)
        #expect(vm.correctCount == 0)
        #expect(vm.wrongCount == 0)
        #expect(vm.sessionEnded == false)
        #expect(vm.currentCard != nil)
    }
}
