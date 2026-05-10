import Testing
@testable import IkeruCore

@Suite("LootDropService")
struct LootDropServiceTests {

    // MARK: - Drop Probability

    @Test("Failed review (again) never drops loot")
    func againGradeNeverDrops() {
        let prob = LootDropService.dropProbability(grade: .again)
        #expect(prob == 0.0)
    }

    @Test("Easy grade has highest drop probability")
    func easyGradeHighestProb() {
        let easy = LootDropService.dropProbability(grade: .easy)
        let good = LootDropService.dropProbability(grade: .good)
        let hard = LootDropService.dropProbability(grade: .hard)
        #expect(easy > good)
        #expect(good > hard)
    }

    @Test("Easy grade never drops if session cap reached")
    func easyGradeCapReached() {
        let dropped = LootDropService.shouldDropLoot(
            grade: .easy, sessionLootCount: 3, randomValue: 0.0
        )
        #expect(!dropped)
    }

    @Test("Good grade has medium drop probability")
    func goodGradeProb() {
        let prob = LootDropService.dropProbability(grade: .good)
        #expect(prob > 0.0)
        #expect(prob < 1.0)
    }

    @Test("shouldDropLoot returns true when roll is below probability")
    func shouldDropLootDeterministic() {
        // Easy grade has base prob + 0.03
        let dropped = LootDropService.shouldDropLoot(
            grade: .easy, sessionLootCount: 0, randomValue: 0.01
        )
        #expect(dropped)

        let notDropped = LootDropService.shouldDropLoot(
            grade: .easy, sessionLootCount: 0, randomValue: 0.99
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
