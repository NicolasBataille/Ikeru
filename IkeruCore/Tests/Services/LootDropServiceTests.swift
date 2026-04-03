import Testing
@testable import IkeruCore

@Suite("LootDropService")
struct LootDropServiceTests {

    // MARK: - Drop Probability

    @Test("Failed review (again) never drops loot")
    func againGradeNeverDrops() {
        let prob = LootDropService.dropProbability(grade: .again, consecutiveCorrect: 100)
        #expect(prob == 0.0)
    }

    @Test("Easy grade has highest drop probability")
    func easyGradeHighestProb() {
        let easy = LootDropService.dropProbability(grade: .easy, consecutiveCorrect: 0)
        let good = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 0)
        let hard = LootDropService.dropProbability(grade: .hard, consecutiveCorrect: 0)
        #expect(easy > good)
        #expect(good > hard)
    }

    @Test("Streak bonus increases probability")
    func streakBonusIncreasesProb() {
        let noStreak = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 0)
        let streak5 = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 5)
        let streak10 = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 10)
        #expect(streak5 > noStreak)
        #expect(streak10 > streak5)
    }

    @Test("Streak bonus is capped at 20%")
    func streakBonusCapped() {
        let streak50 = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 50)
        let streak100 = LootDropService.dropProbability(grade: .good, consecutiveCorrect: 100)
        #expect(streak50 == streak100) // Both hit the cap
    }

    @Test("shouldDropLoot returns true when roll is below probability")
    func shouldDropLootDeterministic() {
        // Easy with 0 streak = 0.25 probability
        let dropped = LootDropService.shouldDropLoot(
            grade: .easy, consecutiveCorrect: 0, randomValue: 0.1
        )
        #expect(dropped)

        let notDropped = LootDropService.shouldDropLoot(
            grade: .easy, consecutiveCorrect: 0, randomValue: 0.9
        )
        #expect(!notDropped)
    }

    // MARK: - Drop Generation

    @Test("Generated drop has valid properties")
    func generateDropValid() {
        let drop = LootDropService.generateDrop(level: 5)
        #expect(!drop.name.isEmpty)
        #expect(!drop.iconName.isEmpty)
        #expect(LootRarity.allCases.contains(drop.rarity))
        #expect(LootItem.Category.allCases.contains(drop.category))
    }

    @Test("Drop generation at different levels produces items")
    func generateDropAtVariousLevels() {
        for level in [1, 5, 10, 20, 50] {
            let drop = LootDropService.generateDrop(level: level)
            #expect(!drop.name.isEmpty)
        }
    }
}
