import Testing
import Foundation
import SwiftData
@testable import IkeruCore

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([TextImport.self, VocabularyEntry.self, VocabularyEncounter.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Imports de texte

@Suite("Imports de texte")
struct TextImportRepositoryTests {

    @Test("Un import garde son texte tel quel et se titre tout seul")
    func createDerivesATitle() async throws {
        let repository = TextImportRepository(modelContainer: try makeTestContainer())
        let created = await repository.create(
            content: "今日は雨が降っている。\n傘を持っていこう。",
            source: .paste, coverage: 0.75, entryIDs: [])
        #expect(created.title == "今日は雨が降っている。")
        #expect(created.content.contains("傘"))
        #expect(created.coverage == 0.75)
        #expect(created.source == .paste)
    }

    @Test("Un titre trop long est coupé, jamais le contenu")
    func longTitlesAreTruncated() {
        let long = String(repeating: "あ", count: 80)
        let title = TextImport.derivedTitle(from: long)
        #expect(title.count == 41, "40 caractères plus le signe de coupure")
        #expect(title.hasSuffix("…"))
    }

    @Test("Le journal de lecture rend les imports du plus récent au plus ancien")
    func journalIsNewestFirst() async throws {
        let repository = TextImportRepository(modelContainer: try makeTestContainer())
        _ = await repository.create(content: "一つ目", source: .paste, coverage: nil, entryIDs: [])
        _ = await repository.create(content: "二つ目", source: .photo, coverage: nil, entryIDs: [])
        let all = await repository.all()
        #expect(all.count == 2)
        #expect(all.first?.title == "二つ目")
    }
}

// MARK: - Suppression d'un import

/// La règle produit : supprimer un import retire les entrées dont c'était la
/// SEULE provenance, et laisse celles que l'apprenant a rencontrées ailleurs.
/// Les deux moitiés sont testées — une règle dont on ne teste que le cas
/// destructeur est une règle dont on ne connaît que la moitié.
@Suite("Suppression d'un import")
struct TextImportDeletionTests {

    /// Crée une entrée avec ses rencontres et rend son identifiant.
    private func seedEntry(
        _ container: ModelContainer, word: String,
        encounters: [(EncounterSource, String)]
    ) -> UUID {
        let context = ModelContext(container)
        let entry = VocabularyEntry(word: word, reading: word, meaning: "test",
                                    isInDictionary: true)
        context.insert(entry)
        for (source, snippet) in encounters {
            let encounter = VocabularyEncounter(source: source, contextSnippet: snippet,
                                                entry: entry)
            context.insert(encounter)
        }
        try? context.save()
        return entry.id
    }

    private func isLive(_ container: ModelContainer, _ id: UUID) -> Bool {
        let context = ModelContext(container)
        let predicate = #Predicate<VocabularyEntry> { $0.id == id && $0.deletedAt == nil }
        return ((try? context.fetch(FetchDescriptor(predicate: predicate)))?.isEmpty == false)
    }

    @Test("Un mot dont l'import était la seule provenance part avec lui")
    func soleProvenanceIsRemoved() async throws {
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "唐揚げ",
                                encounters: [(.importedText, "鶏の唐揚げ定食")])
        let created = await repository.create(content: "本日のおすすめ：鶏の唐揚げ定食",
                                              source: .photo, coverage: nil,
                                              entryIDs: [entryID])
        let removed = await repository.delete(id: created.id)
        #expect(removed == [entryID])
        #expect(!isLive(container, entryID))
        #expect(await repository.all().isEmpty)
    }

    @Test("Un mot rencontré ailleurs survit et ne perd que la rencontre du texte")
    func wordsMetElsewhereSurvive() async throws {
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "定食", encounters: [
            (.importedText, "鶏の唐揚げ定食"),
            (.sakuraChat, "定食を食べました"),
        ])
        let created = await repository.create(content: "本日のおすすめ：鶏の唐揚げ定食",
                                              source: .photo, coverage: nil,
                                              entryIDs: [entryID])
        let removed = await repository.delete(id: created.id)
        #expect(removed.isEmpty, "le mot ne doit pas partir")
        #expect(isLive(container, entryID))

        // La rencontre du texte supprimé s'en va ; celle de Sakura reste.
        let context = ModelContext(container)
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryID }
        let entry = try #require((try? context.fetch(FetchDescriptor(predicate: predicate)))?.first)
        let live = (entry.encounters ?? []).filter { $0.deletedAt == nil }
        #expect(live.count == 1)
        #expect(live.first?.source == .sakuraChat)
    }

    @Test("Un mot qu'un AUTRE import revendique encore reste en place")
    func wordsClaimedByAnotherImportSurvive() async throws {
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "季節",
                                encounters: [(.importedText, "季節の野菜")])
        let first = await repository.create(content: "季節の野菜天ぷら", source: .paste,
                                            coverage: nil, entryIDs: [entryID])
        _ = await repository.create(content: "季節の変わり目", source: .paste,
                                    coverage: nil, entryIDs: [entryID])

        let removed = await repository.delete(id: first.id)
        #expect(removed.isEmpty)
        #expect(isLive(container, entryID))
    }

    @Test("La provenance d'un mot se retrouve depuis l'import")
    func provenanceIsResolvable() async throws {
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = UUID()
        let created = await repository.create(content: "君の名前を呼ぶたびに", source: .paste,
                                              coverage: 0.5, entryIDs: [entryID])
        let found = await repository.imports(containing: entryID)
        #expect(found.map(\.id) == [created.id])
        #expect(await repository.imports(containing: UUID()).isEmpty)
    }

    @Test("Supprimer deux fois ne casse rien et ne retire rien de plus")
    func deletingTwiceIsSafe() async throws {
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "胸", encounters: [(.importedText, "胸の奥")])
        let created = await repository.create(content: "胸の奥が痛い", source: .paste,
                                              coverage: nil, entryIDs: [entryID])
        #expect(await repository.delete(id: created.id) == [entryID])
        #expect(await repository.delete(id: created.id).isEmpty)
    }
}
