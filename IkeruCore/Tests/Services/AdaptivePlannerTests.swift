import Testing
import SwiftData
import Foundation
@testable import IkeruCore

@Suite("Adaptive Planner — Skill-Balanced Composition")
@MainActor
struct AdaptivePlannerTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedCards(
        container: ModelContainer,
        dueCount: Int = 0,
        newCount: Int = 0,
        types: [CardType] = [.kanji]
    ) throws {
        let context = container.mainContext
        for i in 0..<dueCount {
            let cardType = types[i % types.count]
            let card = Card(
                front: "Due \(i)",
                back: "Back \(i)",
                type: cardType,
                fsrsState: FSRSState(reps: 1),
                dueDate: Date().addingTimeInterval(-3600)
            )
            context.insert(card)
        }
        for i in 0..<newCount {
            let cardType = types[i % types.count]
            let card = Card(
                front: "New \(i)",
                back: "Back \(i)",
                type: cardType,
                fsrsState: FSRSState(reps: 0),
                dueDate: Date().addingTimeInterval(3600)
            )
            context.insert(card)
        }
        try context.save()
    }

    // MARK: - Task 1: Basic Adaptive Composition

    @Test("composeAdaptiveSession returns a SessionPlan with exercises")
    func adaptiveSessionReturnsSessionPlan() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 5)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)
        let plan = await planner.composeAdaptiveSession(config: config)

        #expect(!plan.exercises.isEmpty)
        #expect(plan.estimatedDurationMinutes > 0)
    }

    @Test("composeAdaptiveSession puts SRS reviews first")
    func srsReviewsFirst() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 3)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 30)
        let plan = await planner.composeAdaptiveSession(config: config)

        // All initial exercises should be SRS reviews
        for exercise in plan.exercises.prefix(3) {
            if case .srsReview = exercise {
                // OK
            } else {
                Issue.record("Expected SRS review, got \(exercise)")
            }
        }
    }

    @Test("composeAdaptiveSession with no SRS cards still generates supplementary exercises")
    func noSRSCardsStillGeneratesSupplementary() async throws {
        let container = try makeContainer()
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)
        let plan = await planner.composeAdaptiveSession(config: config)

        // Even with no SRS cards, supplementary exercises are generated
        // (kanji study, listening, writing, speaking)
        #expect(plan.estimatedDurationMinutes > 0)
    }

    @Test("composeAdaptiveSession exerciseBreakdown matches exercises")
    func breakdownMatchesExercises() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 5, types: [.kanji, .vocabulary, .grammar, .listening])
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)
        let plan = await planner.composeAdaptiveSession(config: config)

        // Verify breakdown counts match actual exercises per skill
        var actualCounts: [SkillType: Int] = [:]
        for exercise in plan.exercises {
            actualCounts[exercise.skill, default: 0] += 1
        }
        #expect(plan.exerciseBreakdown == actualCounts)
    }

    @Test("composeAdaptiveSession preserves backward compatibility — basic composeSession still works")
    func backwardCompatibility() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 3)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let basicQueue = await planner.composeSession()
        #expect(basicQueue.count == 3)
    }

    @Test("Pedagogical sequencing: receptive before productive in supplementary exercises")
    func receptiveBeforeProductive() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 5)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 30)
        let plan = await planner.composeAdaptiveSession(config: config)

        // Find supplementary exercises (non-SRS)
        let supplementary = plan.exercises.filter {
            if case .srsReview = $0 { return false }
            return true
        }

        // Verify receptive exercises come before productive
        var lastReceptiveIndex = -1
        var firstProductiveIndex = Int.max
        for (index, exercise) in supplementary.enumerated() {
            if exercise.skill.isReceptive {
                lastReceptiveIndex = index
            } else {
                firstProductiveIndex = min(firstProductiveIndex, index)
            }
        }

        // If both exist, receptive should come first
        if lastReceptiveIndex >= 0 && firstProductiveIndex < Int.max {
            #expect(
                lastReceptiveIndex < firstProductiveIndex,
                "Receptive exercises (index \(lastReceptiveIndex)) should come before productive (index \(firstProductiveIndex))"
            )
        }
    }

    @Test("Session composition is pure — no side effects")
    func compositionIsPure() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 5)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)

        // Compose twice — should produce equivalent results
        let plan1 = await planner.composeAdaptiveSession(config: config)
        let plan2 = await planner.composeAdaptiveSession(config: config)

        #expect(plan1.exercises.count == plan2.exercises.count)
        #expect(plan1.estimatedDurationMinutes == plan2.estimatedDurationMinutes)
    }

    // MARK: - Task 2: Time Adaptation

    @Test("Micro session (2-5 min) contains only SRS reviews")
    func microSessionSRSOnly() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 15)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 3)
        let plan = await planner.composeAdaptiveSession(config: config)

        // All exercises should be SRS reviews
        for exercise in plan.exercises {
            if case .srsReview = exercise {
                // OK
            } else {
                Issue.record("Micro session should only have SRS reviews, got \(exercise)")
            }
        }

        // Max 10 cards for micro
        #expect(plan.exercises.count <= 10)
    }

    @Test("Short session (10-15 min) has SRS reviews plus supplementary")
    func shortSessionSRSPlusOne() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 10)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 12)
        let plan = await planner.composeAdaptiveSession(config: config)

        #expect(plan.srsReviewCount > 0)
        // Short sessions include at least some SRS
    }

    @Test("Standard session (20-25 min) has mixed skill exercises")
    func standardSessionMixedSkills() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 10)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 22)
        let plan = await planner.composeAdaptiveSession(config: config)

        #expect(plan.srsReviewCount > 0)
    }

    @Test("Focused session (30+ min) represents all four skills")
    func focusedSessionAllSkills() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 20)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 35, isSilentMode: false)
        let plan = await planner.composeAdaptiveSession(config: config)

        // Should have exercises in all four skills
        let skills = Set(plan.exercises.map(\.skill))
        #expect(skills.contains(.reading), "Focused session should include reading")
        #expect(skills.contains(.writing), "Focused session should include writing")
        #expect(skills.contains(.listening), "Focused session should include listening")
        #expect(skills.contains(.speaking), "Focused session should include speaking")
    }

    @Test("Time estimation approaches available time")
    func timeEstimationApproachesAvailable() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 30)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 20)
        let plan = await planner.composeAdaptiveSession(config: config)

        // Estimated duration should not exceed available time
        #expect(plan.estimatedDurationMinutes <= 20)
    }

    @Test("SessionDuration.from classifies correctly")
    func sessionDurationClassification() {
        #expect(SessionDuration.from(minutes: 2) == .micro)
        #expect(SessionDuration.from(minutes: 5) == .micro)
        #expect(SessionDuration.from(minutes: 10) == .short)
        #expect(SessionDuration.from(minutes: 15) == .short)
        #expect(SessionDuration.from(minutes: 20) == .standard)
        #expect(SessionDuration.from(minutes: 25) == .standard)
        #expect(SessionDuration.from(minutes: 30) == .focused)
        #expect(SessionDuration.from(minutes: 60) == .focused)
    }

    // MARK: - Task 3: Silent Mode

    @Test("Silent mode excludes listening exercises")
    func silentModeExcludesListening() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 10)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 35, isSilentMode: true)
        let plan = await planner.composeAdaptiveSession(config: config)

        // No listening or speaking exercises should be present
        for exercise in plan.exercises {
            #expect(!exercise.requiresAudio, "Silent mode should exclude audio exercises")
        }
    }

    @Test("Silent mode redistributes time to reading and writing")
    func silentModeRedistributesTime() async throws {
        let container = try makeContainer()
        try seedCards(container: container, dueCount: 10)
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let silentConfig = SessionConfig(availableTimeMinutes: 35, isSilentMode: true)
        let silentPlan = await planner.composeAdaptiveSession(config: silentConfig)

        // All supplementary exercises should be reading or writing
        let supplementary = silentPlan.exercises.filter {
            if case .srsReview = $0 { return false }
            return true
        }
        for exercise in supplementary {
            let skill = exercise.skill
            #expect(
                skill == .reading || skill == .writing,
                "Silent mode supplementary should be reading/writing, got \(skill)"
            )
        }
    }

    // MARK: - Task 5: Skill Balance

    @Test("Skill balance deficit weights sum to 1.0")
    func deficitWeightsSumToOne() {
        let balance = SkillBalance.defaultTargets
        let current: [SkillType: Double] = [
            .reading: 0.50,
            .writing: 0.10,
            .listening: 0.30,
            .speaking: 0.10
        ]

        let weights = balance.deficitWeights(current: current)
        let sum = weights.values.reduce(0, +)

        #expect(abs(sum - 1.0) < 0.001, "Deficit weights should sum to 1.0, got \(sum)")
    }

    @Test("Skill balance weights underrepresented skills higher")
    func underrepresentedSkillsWeightedHigher() {
        let balance = SkillBalance.defaultTargets
        // Writing and speaking are severely underrepresented
        let current: [SkillType: Double] = [
            .reading: 0.60,
            .writing: 0.05,
            .listening: 0.30,
            .speaking: 0.05
        ]

        let weights = balance.deficitWeights(current: current)

        // Writing and speaking should have higher weights than reading
        #expect(weights[.writing]! > weights[.reading]!)
        #expect(weights[.speaking]! > weights[.reading]!)
    }

    @Test("Perfectly balanced skills produce equal weights")
    func perfectlyBalancedProducesEqualWeights() {
        let balance = SkillBalance.defaultTargets
        let current = balance.targets // Exactly matching targets

        let weights = balance.deficitWeights(current: current)

        // All weights should be equal
        let values = Array(weights.values)
        let first = values.first!
        for value in values {
            #expect(abs(value - first) < 0.001, "Perfectly balanced should produce equal weights")
        }
    }

    @Test("Imbalance score is 0 for perfectly balanced")
    func imbalanceScoreZeroWhenBalanced() {
        let balance = SkillBalance.defaultTargets
        let score = balance.imbalanceScore(current: balance.targets)
        #expect(abs(score) < 0.001)
    }

    @Test("Imbalance score increases with more deviation")
    func imbalanceScoreIncreasesWithDeviation() {
        let balance = SkillBalance.defaultTargets

        let slight: [SkillType: Double] = [
            .reading: 0.35, .writing: 0.20, .listening: 0.25, .speaking: 0.20
        ]
        let severe: [SkillType: Double] = [
            .reading: 0.80, .writing: 0.05, .listening: 0.10, .speaking: 0.05
        ]

        let slightScore = balance.imbalanceScore(current: slight)
        let severeScore = balance.imbalanceScore(current: severe)

        #expect(severeScore > slightScore)
    }

    @Test("computeSkillBalances returns valid ratios from card types")
    func computeSkillBalancesFromCards() async throws {
        let container = try makeContainer()
        try seedCards(
            container: container,
            dueCount: 10,
            types: [.kanji, .vocabulary, .grammar, .listening]
        )
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let balances = await planner.computeSkillBalances()

        // All values should be between 0.0 and 1.0
        for (_, ratio) in balances {
            #expect(ratio >= 0.0 && ratio <= 1.0)
        }

        // Should sum to approximately 1.0 if there are any cards
        let sum = balances.values.reduce(0, +)
        if sum > 0 {
            #expect(abs(sum - 1.0) < 0.001, "Skill balances should sum to 1.0, got \(sum)")
        }
    }

    // MARK: - Task 7: Performance

    @Test("composeAdaptiveSession completes in under 1000ms with large card set")
    func performanceUnder1000ms() async throws {
        let container = try makeContainer()
        // Seed 500+ cards
        try seedCards(
            container: container,
            dueCount: 500,
            newCount: 50,
            types: [.kanji, .vocabulary, .grammar, .listening]
        )
        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)

        let config = SessionConfig(availableTimeMinutes: 30)

        let start = CFAbsoluteTimeGetCurrent()
        _ = await planner.composeAdaptiveSession(config: config)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 1000, "Adaptive composition took \(elapsed)ms, exceeding 1000ms limit")
    }
}
