import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Helper to create an in-memory ModelContainer for vocabulary testing.
private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, VocabularyEntry.self, VocabularyEncounter.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@Suite("VocabularyRepository")
struct VocabularyRepositoryTests {

    /// Seeds a UserProfile whose settings carry a specific desiredRetention —
    /// the target read by `VocabularyModelActor.gradeEntry`. No UserDefaults
    /// key is written: with a missing/stale active-profile id the actor falls
    /// back to the oldest profile in the store, so each in-memory container
    /// resolves its own seeded profile (same pattern as CardRepositoryTests).
    @MainActor
    private func seedActiveProfileWithRetention(in container: ModelContainer, desiredRetention: Double) throws {
        let context = container.mainContext
        context.insert(UserProfile(
            displayName: "Test",
            settings: ProfileSettings(desiredRetention: desiredRetention)
        ))
        try context.save()
    }

    @Test("gradeEntry reads the active profile's desiredRetention: 0.95 due date is sooner than 0.8's")
    func gradeEntryUsesActiveProfileDesiredRetention() async throws {
        let lowRetentionContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: lowRetentionContainer, desiredRetention: 0.8)
        let lowRetentionRepository = VocabularyRepository(modelContainer: lowRetentionContainer)

        let highRetentionContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: highRetentionContainer, desiredRetention: 0.95)
        let highRetentionRepository = VocabularyRepository(modelContainer: highRetentionContainer)

        // Same word, same grade, same (approximate) instant — the only
        // difference between the two containers is the active profile's
        // desiredRetention. Mirrors CardRepositoryTests' plumbing test so
        // both FSRS surfaces are held to the same contract.
        let lowEntry = await lowRetentionRepository.addEntry(
            word: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5
        )
        let highEntry = await highRetentionRepository.addEntry(
            word: "犬", reading: "いぬ", meaning: "dog", jlptLevel: .n5
        )

        await lowRetentionRepository.gradeEntry(entryId: lowEntry.id, grade: .good, responseTimeMs: 1000)
        await highRetentionRepository.gradeEntry(entryId: highEntry.id, grade: .good, responseTimeMs: 1000)

        let lowResult = await lowRetentionRepository.entry(by: lowEntry.id)
        let highResult = await highRetentionRepository.entry(by: highEntry.id)

        // Higher desired retention => shorter interval => sooner due date.
        #expect(lowResult?.dueDate != nil)
        #expect(highResult?.dueDate != nil)
        #expect(highResult!.dueDate < lowResult!.dueDate)
    }

    @Test("gradeEntry clamps an out-of-band desiredRetention to the 0.8...0.95 range")
    func gradeEntryClampsDesiredRetention() async throws {
        let extremeContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: extremeContainer, desiredRetention: 0.5)
        let extremeRepository = VocabularyRepository(modelContainer: extremeContainer)

        let clampedContainer = try makeTestContainer()
        try await seedActiveProfileWithRetention(in: clampedContainer, desiredRetention: 0.8)
        let clampedRepository = VocabularyRepository(modelContainer: clampedContainer)

        let extremeEntry = await extremeRepository.addEntry(
            word: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5
        )
        let clampedEntry = await clampedRepository.addEntry(
            word: "猫", reading: "ねこ", meaning: "cat", jlptLevel: .n5
        )

        let now = Date()
        await extremeRepository.gradeEntry(entryId: extremeEntry.id, grade: .good, responseTimeMs: 1000)
        await clampedRepository.gradeEntry(entryId: clampedEntry.id, grade: .good, responseTimeMs: 1000)

        let extremeResult = await extremeRepository.entry(by: extremeEntry.id)
        let clampedResult = await clampedRepository.entry(by: clampedEntry.id)

        // 0.5 clamps to the 0.8 floor => both schedules land within a second
        // of each other (they run microseconds apart on the same formula).
        let extremeDue = try #require(extremeResult?.dueDate)
        let clampedDue = try #require(clampedResult?.dueDate)
        #expect(abs(extremeDue.timeIntervalSince(now) - clampedDue.timeIntervalSince(now)) < 1.0)
    }
}
