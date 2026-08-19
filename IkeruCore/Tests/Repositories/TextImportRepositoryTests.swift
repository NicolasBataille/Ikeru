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

    @Test("Un mot qu'un autre import garde perd quand même la rencontre du texte effacé")
    func survivorLosesThisTextsEncounter() async throws {
        // La boîte de confirmation promet « seuls les mots que ce texte a été le
        // seul à apporter sont retirés » — pas que l'historique continue de
        // citer un texte qui n'existe plus. Le doc de `delete(_:)` le dit
        // aussi : « an entry that survives still loses THIS text's encounter ».
        // La branche « un autre import le revendique » sautait l'entrée entière
        // et laissait donc une rencontre pointant sur un texte effacé, alors
        // que la branche « rencontré ailleurs » la retirait : deux issues
        // différentes pour la même situation, selon la seule raison de survie.
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "野菜", encounters: [
            (.importedText, "季節の野菜天ぷら"),
            (.importedText, "野菜を買いに行く"),
        ])
        let first = await repository.create(content: "季節の野菜天ぷらが美味しい", source: .paste,
                                            coverage: nil, entryIDs: [entryID])
        _ = await repository.create(content: "野菜を買いに行く", source: .paste,
                                    coverage: nil, entryIDs: [entryID])

        #expect(await repository.delete(id: first.id).isEmpty)
        #expect(isLive(container, entryID))

        let context = ModelContext(container)
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryID }
        let entry = try #require((try? context.fetch(FetchDescriptor(predicate: predicate)))?.first)
        let live = (entry.encounters ?? []).filter { $0.deletedAt == nil }
        #expect(live.map(\.contextSnippet) == ["野菜を買いに行く"],
                "la rencontre du texte effacé s'en va, celle du texte encore là reste")
    }

    @Test("Une rencontre sans extrait ne se fait pas emporter par un texte au hasard")
    func emptySnippetIsNotMatchedByEveryText() async throws {
        // Mesuré, pas supposé : `"…".contains("")` rend `false` en Swift, donc
        // une rencontre à l'extrait vide — il en arrive par la synchronisation,
        // écrites par un autre appareil — n'est PAS emportée par n'importe quel
        // import. Ce test épingle ce comportement, parce qu'il tient à une
        // subtilité de la bibliothèque standard et non à une intention écrite :
        // le jour où l'appartenance change de critère, il le dira.
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "空", encounters: [
            (.importedText, ""),
            (.sakuraChat, "空が青い"),
        ])
        let created = await repository.create(content: "全く関係のない文章です", source: .paste,
                                              coverage: nil, entryIDs: [entryID])
        #expect(await repository.delete(id: created.id).isEmpty)

        let context = ModelContext(container)
        let predicate = #Predicate<VocabularyEntry> { $0.id == entryID }
        let entry = try #require((try? context.fetch(FetchDescriptor(predicate: predicate)))?.first)
        let live = (entry.encounters ?? []).filter { $0.deletedAt == nil }
        #expect(live.count == 2, "aucune des deux rencontres ne vient de ce texte")
    }

    @Test("Un import ne compte plus comme provenance une fois lui-même supprimé")
    func tombstonedImportsAreNotProvenance() async throws {
        // Deux imports revendiquent le mot ; on supprime le second, puis le
        // premier. Au second passage il ne reste aucune provenance vivante,
        // donc le mot part — un import effacé ne doit pas garder un mot en vie
        // pour toujours.
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let entryID = seedEntry(container, word: "天ぷら",
                                encounters: [(.importedText, "野菜天ぷら")])
        let first = await repository.create(content: "野菜天ぷら定食", source: .paste,
                                            coverage: nil, entryIDs: [entryID])
        let second = await repository.create(content: "天ぷらを揚げる", source: .paste,
                                             coverage: nil, entryIDs: [entryID])

        #expect(await repository.delete(id: second.id).isEmpty, "le premier import le garde")
        #expect(isLive(container, entryID))
        #expect(await repository.delete(id: first.id) == [entryID], "plus aucune provenance vivante")
        #expect(!isLive(container, entryID))
    }

    @Test("Un identifiant qui ne pointe plus sur rien ne fait ni planter ni gonfler le compte")
    func danglingEntryIDsAreSkipped() async throws {
        // L'apprenant a supprimé le mot depuis son dictionnaire ; l'import le
        // liste encore. Supprimer l'import ne doit rien casser et ne doit pas
        // annoncer un mot retiré qui l'était déjà.
        let container = try makeTestContainer()
        let repository = TextImportRepository(modelContainer: container)
        let vocabulary = VocabularyRepository(modelContainer: container)
        let alive = seedEntry(container, word: "揚げる", encounters: [(.importedText, "天ぷらを揚げる")])
        let gone = seedEntry(container, word: "鍋", encounters: [(.importedText, "鍋を出す")])
        await vocabulary.deleteEntry(by: gone)

        let created = await repository.create(content: "天ぷらを揚げる。鍋を出す。", source: .paste,
                                              coverage: nil, entryIDs: [gone, alive, UUID()])
        #expect(await repository.delete(id: created.id) == [alive])
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
