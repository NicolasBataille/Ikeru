import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let schema = Schema([TextImport.self, VocabularyEntry.self, VocabularyEncounter.self,
                         UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    return try ModelContainer(for: schema,
                              configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
}

/// The shipped dictionary, so the view model is exercised against the same data
/// the app reads rather than a fixture that cannot disagree with it.
private func dictionaryURL() throws -> URL {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ikeru/Resources/ContentBundles/jmdict.sqlite")
    try #require(FileManager.default.fileExists(atPath: url.path))
    return url
}

@MainActor
private func makeViewModel(_ container: ModelContainer) throws -> TextImportViewModel {
    let dictionary = DictionaryRepository(bundleURL: try dictionaryURL())
    return TextImportViewModel(
        analyzer: JapaneseTextAnalyzer(dictionary: dictionary),
        dictionary: dictionary,
        vocabulary: VocabularyRepository(modelContainer: container),
        imports: TextImportRepository(modelContainer: container)
    )
}

private func token(_ id: Int, _ surface: String, word: Bool = true,
                   form: String? = nil, learnable: Bool = false) -> AnalyzedToken {
    let entry = learnable
        ? DictionaryEntry(id: id, reading: surface, partsOfSpeech: ["n"],
                          glossFR: "test", glossEN: "test", isCommon: true)
        : nil
    return AnalyzedToken(id: id, surface: surface, isWord: word,
                         dictionaryForm: form ?? surface, entry: entry)
}

// MARK: - Découpage en phrases

/// The sentence a word sits in is what the SRS card keeps — « le contexte est la
/// moitié de la valeur ». Getting the boundaries wrong ships cards with half a
/// sentence or with three.
@Suite("Phrase d'origine d'un mot")
struct TextImportSentenceTests {

    private func analysis(_ tokens: [AnalyzedToken]) -> AnalyzedText {
        AnalyzedText(source: tokens.map(\.surface).joined(), tokens: tokens)
    }

    @Test("La phrase s'arrête au point japonais, des deux côtés")
    func stopsAtFullStop() {
        let text = analysis([
            token(0, "雨"), token(1, "。", word: false),
            token(2, "電車"), token(3, "が"), token(4, "混む"),
            token(5, "。", word: false), token(6, "最悪"),
        ])
        // La ponctuation FINALE reste dans la phrase — une carte qui garde
        // « 電車が混む。 » est plus lisible qu'une phrase amputée de son point.
        let sentence = TextImportViewModel.sentence(containing: text.tokens[3], in: text)
        #expect(sentence == "電車が混む。")
    }

    @Test("Un retour à la ligne coupe aussi")
    func stopsAtNewline() {
        let text = analysis([
            token(0, "一行目"), token(1, "\n", word: false), token(2, "二行目"),
        ])
        #expect(TextImportViewModel.sentence(containing: text.tokens[2], in: text) == "二行目")
    }

    /// Un guillemet fermant n'est PAS une frontière : 「おい、そこで何をしている！」
    /// est un seul énoncé, et le couper en deux donnerait une carte au contexte
    /// amputé.
    @Test("La virgule et les guillemets ne coupent pas")
    func commasAndQuotesDoNotBreak() {
        let text = analysis([
            token(0, "「", word: false), token(1, "おい"), token(2, "、", word: false),
            token(3, "そこ"), token(4, "で"), token(5, "何"),
            token(6, "！」", word: false),
        ])
        let sentence = TextImportViewModel.sentence(containing: text.tokens[3], in: text)
        #expect(sentence.contains("おい"))
        #expect(sentence.contains("そこ"))
    }

    @Test("Un texte d'une seule phrase rend la phrase entière")
    func singleSentence() {
        let text = analysis([token(0, "犬"), token(1, "が"), token(2, "いる")])
        #expect(TextImportViewModel.sentence(containing: text.tokens[0], in: text) == "犬がいる")
    }
}

// MARK: - Parcours

@Suite("Parcours d'import de texte")
@MainActor
struct TextImportViewModelTests {

    @Test("Analyser un texte le met en lecture avec une couverture mesurée")
    func analyzeMovesToReading() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "今日は雨が降っている。", source: .paste)
        await viewModel.analyzeDraft()

        #expect(viewModel.stage == .reading)
        #expect(viewModel.analysis != nil)
        // Rien de connu au départ : la couverture existe et vaut zéro. Elle ne
        // doit pas être `nil` — « nil » veut dire « rien à mesurer », ce qui est
        // un autre message.
        #expect(viewModel.coverage == 0)
        #expect(!viewModel.unknownWords.isEmpty)
    }

    @Test("Un texte vide ne lance rien")
    func emptyDraftDoesNothing() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "   \n  ", source: .paste)
        await viewModel.analyzeDraft()
        #expect(viewModel.stage == .capture)
        #expect(viewModel.analysis == nil)
    }

    /// Le plafond PRÉ-COCHE, il n'interdit rien. C'est la différence entre
    /// « on plafonne la charge » et « on limite l'apprenant », et la vision
    /// tient beaucoup à celle-là.
    @Test("Le plafond de suggestion pré-coche sans rien retirer de la liste")
    func capPreselectsWithoutTruncating() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: """
            今日は朝から雨が降っていて、電車がめちゃくちゃ混んでた。
            新しいカフェが駅前にオープンしたらしいので、週末に行ってみようと思います。
            """, source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()

        #expect(viewModel.unknownWords.count > TextImportViewModel.suggestionCap,
                "l'échantillon doit dépasser le plafond pour que le test dise quelque chose")
        #expect(viewModel.selectedCount == TextImportViewModel.suggestionCap)
        // Tout le reste est accessible, simplement décoché.
        let unselected = viewModel.unknownWords.filter { !viewModel.isSelected($0) }
        #expect(!unselected.isEmpty)
    }

    @Test("Cocher et décocher un mot est symétrique")
    func togglingIsSymmetric() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "季節の野菜天ぷら", source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()

        let word = try #require(viewModel.unknownWords.first)
        let wasSelected = viewModel.isSelected(word)
        viewModel.toggle(word)
        #expect(viewModel.isSelected(word) == !wasSelected)
        viewModel.toggle(word)
        #expect(viewModel.isSelected(word) == wasSelected)
    }

    /// Les mots retenus naissent DUS, et c'est correct : l'apprenant les a
    /// choisis un par un. C'est l'inverse du semis de grammaire retiré le
    /// 2026-08-19, qui remplissait la file de 51 cartes que personne n'avait
    /// demandées. C'est le consentement qui fait la différence, pas le compte.
    @Test("Enregistrer crée une carte par mot, avec sa phrase d'origine")
    func saveCreatesContextualCards() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)
        let vocabulary = VocabularyRepository(modelContainer: container)

        viewModel.begin(with: "本日のおすすめは鶏の唐揚げ定食です。", source: .photo)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        let kept = viewModel.selectedCount
        #expect(kept > 0)
        await viewModel.save()

        #expect(viewModel.stage == .saved(wordsKept: kept))
        let entries = await vocabulary.allEntries()
        #expect(entries.count == kept)

        // Chaque carte garde la phrase où le mot a été rencontré.
        for entry in entries {
            let encounters = await vocabulary.encounters(for: entry.id)
            let imported = encounters.filter { $0.source == .importedText }
            #expect(!imported.isEmpty, "\(entry.word) n'a pas de rencontre d'import")
            #expect(imported.allSatisfy { $0.contextSnippet.contains("唐揚げ") },
                    "la phrase d'origine est perdue pour \(entry.word)")
        }

        // Et l'import lui-même est au journal, avec ce qu'il a produit.
        let imports = await TextImportRepository(modelContainer: container).all()
        #expect(imports.count == 1)
        #expect(imports.first?.source == .photo)
        #expect(imports.first?.entryIDs.count == kept)
    }

    @Test("Ne rien cocher enregistre l'import sans créer de carte")
    func savingNothingKeepsTheTextOnly() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)
        viewModel.begin(with: "季節の野菜天ぷら", source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        for word in viewModel.unknownWords where viewModel.isSelected(word) {
            viewModel.toggle(word)
        }
        await viewModel.save()

        #expect(viewModel.stage == .saved(wordsKept: 0))
        #expect(await VocabularyRepository(modelContainer: container).allEntries().isEmpty)
        #expect(await TextImportRepository(modelContainer: container).all().count == 1)
    }

    @Test("Réinitialiser ramène à la capture, sans rien garder")
    func resetClearsEverything() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "犬がいる。", source: .paste)
        await viewModel.analyzeDraft()
        viewModel.reset()
        #expect(viewModel.stage == .capture)
        #expect(viewModel.analysis == nil)
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.selectedCount == 0)
    }
}
