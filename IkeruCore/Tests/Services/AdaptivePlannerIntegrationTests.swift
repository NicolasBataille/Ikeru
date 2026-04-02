import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("Adaptive Planner Integration Tests")
struct AdaptivePlannerIntegrationTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedRealisticDistribution(container: ModelContainer) throws {
        let context = container.mainContext

        // 100 kanji cards (due)
        for i in 0..<100 {
            let card = Card(
                front: "Kanji \(i)",
                back: "Meaning \(i)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double.random(in: 1...30),
                    reps: Int.random(in: 1...10),
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: Date().addingTimeInterval(Double.random(in: -7200...(-60)))
            )
            context.insert(card)
        }

        // 200 vocabulary cards (mix of due and future)
        for i in 0..<200 {
            let isDue = i < 80
            let card = Card(
                front: "Vocab \(i)",
                back: "Translation \(i)",
                type: .vocabulary,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double.random(in: 1...30),
                    reps: Int.random(in: 1...10),
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: isDue
                    ? Date().addingTimeInterval(Double.random(in: -7200...(-60)))
                    : Date().addingTimeInterval(Double.random(in: 3600...86400 * 7))
            )
            context.insert(card)
        }

        // 50 grammar cards (some due)
        for i in 0..<50 {
            let isDue = i < 20
            let card = Card(
                front: "Grammar \(i)",
                back: "Rule \(i)",
                type: .grammar,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double.random(in: 1...20),
                    reps: Int.random(in: 1...5),
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: isDue
                    ? Date().addingTimeInterval(Double.random(in: -7200...(-60)))
                    : Date().addingTimeInterval(Double.random(in: 3600...86400 * 7))
            )
            context.insert(card)
        }

        // 30 listening cards (some due)
        for i in 0..<30 {
            let isDue = i < 10
            let card = Card(
                front: "Listening \(i)",
                back: "Transcript \(i)",
                type: .listening,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double.random(in: 1...15),
                    reps: Int.random(in: 1...5),
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: isDue
                    ? Date().addingTimeInterval(Double.random(in: -7200...(-60)))
                    : Date().addingTimeInterval(Double.random(in: 3600...86400 * 7))
            )
            context.insert(card)
        }

        try context.save()
    }

    // MARK: - Realistic Distribution Tests

    @Test("Adaptive composition with realistic card distribution")
    func realisticDistribution() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)
        let plan = await planner.composeAdaptiveSession(config: config)

        #expect(!plan.exercises.isEmpty)
        #expect(plan.estimatedDurationMinutes > 0)
        #expect(plan.estimatedDurationMinutes <= 20)
        #expect(plan.srsReviewCount > 0)
    }

    @Test("Time adaptation: micro session contains only SRS")
    func microSessionOnlySRS() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 3)
        let plan = await planner.composeAdaptiveSession(config: config)

        // All exercises should be SRS
        for exercise in plan.exercises {
            if case .srsReview = exercise {
                // OK
            } else {
                Issue.record("Micro session should only have SRS reviews")
            }
        }
        #expect(plan.exercises.count <= 10, "Micro session max 10 cards")
    }

    @Test("Time adaptation: focused session has all skills")
    func focusedSessionAllSkills() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 35, isSilentMode: false)
        let plan = await planner.composeAdaptiveSession(config: config)

        let skills = Set(plan.exercises.map(\.skill))
        #expect(skills.count == 4, "Focused session should have all 4 skills, got \(skills)")
    }

    @Test("Silent mode: no audio exercises in plan")
    func silentModeNoAudio() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 30, isSilentMode: true)
        let plan = await planner.composeAdaptiveSession(config: config)

        for exercise in plan.exercises {
            #expect(!exercise.requiresAudio, "Silent mode should exclude audio exercises")
        }
    }

    @Test("Skill balancing: skewed skill compensates in next session")
    func skewedSkillCompensation() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        // Simulate heavily skewed reading balance
        let skewedBalances: [SkillType: Double] = [
            .reading: 0.80,
            .writing: 0.05,
            .listening: 0.10,
            .speaking: 0.05
        ]

        let config = SessionConfig(
            availableTimeMinutes: 30,
            isSilentMode: false,
            currentSkillBalances: skewedBalances
        )
        let plan = await planner.composeAdaptiveSession(config: config)

        // Non-SRS exercises should favor writing and speaking
        let supplementary = plan.exercises.filter {
            if case .srsReview = $0 { return false }
            return true
        }

        if !supplementary.isEmpty {
            let writingCount = supplementary.filter { $0.skill == .writing }.count
            let speakingCount = supplementary.filter { $0.skill == .speaking }.count
            let compensationCount = writingCount + speakingCount

            #expect(
                compensationCount > 0,
                "Skewed reading should produce writing/speaking exercises to compensate"
            )
        }
    }

    @Test("Forecast accuracy: cards with known due dates produce correct daily counts")
    func forecastAccuracy() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Seed cards with specific due dates
        let dueDates = [
            today.addingTimeInterval(86400 + 100),    // Day 2: 1 card
            today.addingTimeInterval(86400 + 200),    // Day 2: 1 card
            today.addingTimeInterval(86400 * 2 + 100), // Day 3: 1 card
            today.addingTimeInterval(86400 * 4 + 100), // Day 5: 1 card
        ]

        for (i, dueDate) in dueDates.enumerated() {
            let card = Card(
                front: "Forecast \(i)",
                back: "Back \(i)",
                type: .kanji,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: 10.0,
                    reps: 1,
                    lapses: 0,
                    lastReview: Date().addingTimeInterval(-86400)
                ),
                dueDate: dueDate
            )
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let service = ReviewForecastService(cardRepository: repo)

        let forecast = await service.forecast(days: 7)

        #expect(forecast.count == 7)
        #expect(forecast[0].dueCount == 0, "Day 1 (today): no cards due")
        #expect(forecast[1].dueCount == 2, "Day 2: 2 cards due")
        #expect(forecast[2].dueCount == 1, "Day 3: 1 card due")
        #expect(forecast[3].dueCount == 0, "Day 4: no cards due")
        #expect(forecast[4].dueCount == 1, "Day 5: 1 card due")
    }

    @Test("Session preview matches actual session composition")
    func previewMatchesComposition() async throws {
        let container = try makeContainer()
        try seedRealisticDistribution(container: container)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)

        // Compose twice — deterministic algorithm should produce same results
        let plan1 = await planner.composeAdaptiveSession(config: config)
        let plan2 = await planner.composeAdaptiveSession(config: config)

        #expect(plan1.exercises.count == plan2.exercises.count)
        #expect(plan1.estimatedDurationMinutes == plan2.estimatedDurationMinutes)
        #expect(plan1.exerciseBreakdown == plan2.exerciseBreakdown)
    }

    @Test("Performance: sub-500ms composition with large card sets")
    func performanceLargeCardSet() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed 500+ cards across all types
        for i in 0..<550 {
            let types: [CardType] = [.kanji, .vocabulary, .grammar, .listening]
            let cardType = types[i % types.count]
            let isDue = i < 300

            let card = Card(
                front: "Perf \(i)",
                back: "Back \(i)",
                type: cardType,
                fsrsState: FSRSState(
                    difficulty: 5.0,
                    stability: Double(i % 30 + 1),
                    reps: isDue ? 1 : 0,
                    lapses: 0,
                    lastReview: isDue ? Date().addingTimeInterval(-86400) : nil
                ),
                dueDate: isDue
                    ? Date().addingTimeInterval(Double(-i * 60))
                    : Date().addingTimeInterval(Double(i * 3600))
            )
            context.insert(card)
        }
        try context.save()

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 30)

        let start = CFAbsoluteTimeGetCurrent()
        _ = await planner.composeAdaptiveSession(config: config)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 500, "Adaptive composition took \(elapsed)ms, exceeding 500ms limit")
    }
}
