import Testing
import Foundation
import SwiftData
@testable import IkeruCore

/// Helper to create an in-memory ModelContainer for vocabulary testing.
private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, VocabularyEntry.self, VocabularyEncounter.self, TextImport.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    UserDefaults.standard.removeObject(forKey: UserProfile.activeProfileIDDefaultsKey)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Points the actor's active-profile key at the profile with this id.
private func setActive(_ profileID: UUID) {
    UserDefaults.standard.set(profileID.uuidString, forKey: UserProfile.activeProfileIDDefaultsKey)
}

// MARK: - Un propriétaire par entrée (IkeruSchemaV6, P1-1 / OBS2-022)

/// Avant V6 le dictionnaire était UN magasin pour tout l'appareil : un profil
/// neuf héritait des mots d'un autre, et le mélange partait au serveur. Chaque
/// test ici a été vu ROUGE avec le prédicat de scoping neutralisé.
@Suite("VocabularyRepository — propriétaire", .serialized)
struct VocabularyRepositoryOwnershipTests {

    /// Returns the two profile ids (models are not Sendable across the actor hop).
    @MainActor
    private func seedTwoProfiles(in container: ModelContainer) throws -> (zed: UUID, neo: UUID) {
        let context = container.mainContext
        let zed = UserProfile(displayName: "Zed")
        let neo = UserProfile(displayName: "Neo")
        context.insert(zed)
        context.insert(neo)
        try context.save()
        return (zed.id, neo.id)
    }

    @Test("Un mot ajouté sous un profil est invisible à l'autre, sur chaque lecture")
    func entriesAreScopedToTheActiveProfile() async throws {
        let container = try makeTestContainer()
        let (zed, neo) = try await seedTwoProfiles(in: container)
        let repository = VocabularyRepository(modelContainer: container)

        setActive(zed)
        let zedWord = await repository.addEntry(word: "犬", reading: "いぬ", meaning: "chien", jlptLevel: .n5)
        await repository.logEncounterByWord(word: "猫", reading: "ねこ", meaning: "chat",
                                            source: .sakuraChat, contextSnippet: "猫がいる。")

        setActive(neo)
        #expect(await repository.allEntries().isEmpty, "Neo sees Zed's dictionary")
        #expect(await repository.entry(by: zedWord.id) == nil)
        #expect(await repository.entry(byWord: "犬") == nil)
        #expect(await repository.hasEntry(forWord: "犬") == false)
        #expect(await repository.dueEntries(before: .distantFuture).isEmpty)
        #expect(await repository.encounters(for: zedWord.id).isEmpty)
        // Neither can Neo edit, grade or delete it.
        #expect(await repository.updateEntry(id: zedWord.id, word: "犬", reading: "いぬ", meaning: "dog") == nil)
        await repository.gradeEntry(entryId: zedWord.id, grade: .good, responseTimeMs: 100)
        await repository.deleteEntry(by: zedWord.id)

        setActive(zed)
        let stillThere = try #require(await repository.entry(by: zedWord.id))
        #expect(stillThere.meaning == "chien")
        #expect(stillThere.fsrsState.reps == 0, "Neo's grade must not have reached Zed's card")
        #expect(await repository.allEntries().map(\.word) == ["犬"])
        // The pre-tracked (encounter-only) word is Zed's too.
        #expect(await repository.entry(byWord: "猫")?.isInDictionary == false)
    }

    @Test("Le même mot peut vivre dans deux profils, chacun avec sa propre carte")
    func sameWordIsTwoEntriesUnderTwoProfiles() async throws {
        let container = try makeTestContainer()
        let (zed, neo) = try await seedTwoProfiles(in: container)
        let repository = VocabularyRepository(modelContainer: container)

        setActive(zed)
        let zedWord = await repository.addEntry(word: "犬", reading: "いぬ", meaning: "chien", jlptLevel: nil)
        setActive(neo)
        let neoWord = await repository.addEntry(word: "犬", reading: "いぬ", meaning: "dog", jlptLevel: nil)

        #expect(zedWord.id != neoWord.id, "addEntry promoted Zed's entry instead of minting Neo's")
        #expect(await repository.entry(byWord: "犬")?.meaning == "dog")
        setActive(zed)
        #expect(await repository.entry(byWord: "犬")?.meaning == "chien")
    }

    @Test("Une ligne sans propriétaire est adoptée par le profil actif, et devient sale pour le push")
    func unownedRowsAreAdoptedByTheActiveProfile() async throws {
        let container = try makeTestContainer()
        let (zed, neo) = try await seedTwoProfiles(in: container)
        let context = ModelContext(container)

        // The shape a V5 store leaves after the lightweight migration, or a
        // pull from a pre-V6 device: no owner, already synced.
        let orphan = VocabularyEntry(word: "傘", reading: "かさ", meaning: "parapluie")
        orphan.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        orphan.syncedAt = orphan.updatedAt
        context.insert(orphan)
        let owned = VocabularyEntry(word: "本", reading: "ほん", meaning: "livre", profileID: neo)
        context.insert(owned)
        let record = TextImport(content: "傘を持っていこう。", entryIDs: [orphan.id])
        context.insert(record)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_800_001_000)
        let result = try OwnershipAdoption.adoptUnownedRows(into: zed, in: context, at: now)
        try context.save()

        #expect(result == OwnershipAdoption.Result(entries: 1, imports: 1))
        #expect(orphan.profileID == zed)
        #expect(orphan.updatedAt == now, "an adoption that stays clean never reaches the server")
        #expect(owned.profileID == neo, "a row that has an owner is never re-attributed")
        #expect(record.profileID == zed)

        // And the scoped repository now serves it to Zed only.
        let repository = VocabularyRepository(modelContainer: container)
        setActive(zed)
        #expect(await repository.entry(byWord: "傘") != nil)
        setActive(neo)
        #expect(await repository.entry(byWord: "傘") == nil)
    }
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
