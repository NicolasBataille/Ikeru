import Testing
import SwiftData
import Foundation
@testable import IkeruCore

/// Tests the post-Spec-C JLPT estimation pipeline. The legacy
/// `computeJLPTEstimate(allCards:)` counted any card with `reps > 0`,
/// which spiked the estimate after kana onboarding (kana cards are
/// `.vocabulary` with `jlptLevel == nil`). The new pipeline runs the
/// learner snapshot through `JLPTReadinessFormula` so untagged kana never
/// contributes to the per-level pool.
@Suite("ProgressService JLPT estimate rebuild")
@MainActor
struct ProgressServiceJLPTRebuildTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func familiarFSRS(now: Date = Date()) -> FSRSState {
        FSRSState(
            difficulty: 5.0,
            stability: 8.0,
            reps: 4,
            lapses: 0,
            lastReview: now.addingTimeInterval(-86400)
        )
    }

    /// Seeds a UserProfile so `CardRepository.activeProfileCards()` resolves
    /// the inserted cards. Without this the model actor's
    /// `fetchActiveProfile()` falls back to nil and returns an empty pool.
    private func seedActiveProfile(in context: ModelContext) -> UserProfile {
        let profile = UserProfile(displayName: "Test")
        context.insert(profile)
        return profile
    }

    @Test("Hiragana-only profile returns level == 'N5' with very low fraction (no kana spike)")
    func kanaOnlyDoesNotSpike() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let profile = seedActiveProfile(in: context)

        // Seed all 46 base hiragana as familiar+ vocab cards (jlptLevel: nil).
        let allHiragana = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
        for ch in allHiragana {
            let card = Card(
                front: String(ch),
                back: String(ch),
                type: .vocabulary,
                fsrsState: familiarFSRS(now: now),
                dueDate: now.addingTimeInterval(86_400)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData()

        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteryFraction <= 0.05)
        #expect(data.jlptEstimate.masteredCount == 0)
    }

    @Test("Untagged vocab cards (no JLPT level) do not contribute to estimate")
    func untaggedVocabExcluded() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let profile = seedActiveProfile(in: context)

        // 200 untagged vocab cards, all familiar+ — should NOT spike
        // because they have no jlptLevel.
        for i in 0..<200 {
            let card = Card(
                front: "untagged-\(i)",
                back: "meaning-\(i)",
                type: .vocabulary,
                fsrsState: familiarFSRS(now: now),
                dueDate: now.addingTimeInterval(86_400)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData()

        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteredCount == 0)
        #expect(data.jlptEstimate.masteryFraction == 0)
    }

    @Test("N5-tagged vocab + kana mastery yields N5 estimate reflecting mastered N5 vocab")
    func n5TaggedVocabCounts() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let profile = seedActiveProfile(in: context)

        // 50 N5-tagged vocab cards familiar+.
        for i in 0..<50 {
            let card = Card(
                front: "n5vocab-\(i)",
                back: "meaning-\(i)",
                type: .vocabulary,
                fsrsState: familiarFSRS(now: now),
                dueDate: now.addingTimeInterval(86_400),
                jlptLevel: .n5
            )
            card.profile = profile
            context.insert(card)
        }
        // Hiragana mastered.
        let allHiragana = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
        for ch in allHiragana {
            let card = Card(
                front: String(ch),
                back: String(ch),
                type: .vocabulary,
                fsrsState: familiarFSRS(now: now),
                dueDate: now.addingTimeInterval(86_400)
            )
            card.profile = profile
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData()

        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteredCount == 50)
        #expect(data.jlptEstimate.totalRequired == 100)
        // The fraction reported is the bestFit confidence — i.e. the min
        // across all axes (vocab 50/100, kanji 0/50, grammar 0/5,
        // listenAccuracy 0/0.6). The min is 0 (no kanji or grammar).
        #expect(data.jlptEstimate.masteryFraction <= 0.5)
    }

    @Test("Empty card pool yields N5 fallback at 0.0")
    func emptyPool() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let service = ProgressService(cardRepository: repo)
        let data = await service.loadDashboardData()

        #expect(data.jlptEstimate.level == "N5")
        #expect(data.jlptEstimate.masteryFraction == 0)
        #expect(data.jlptEstimate.masteredCount == 0)
        #expect(data.jlptEstimate.totalRequired == 100)
    }
}
