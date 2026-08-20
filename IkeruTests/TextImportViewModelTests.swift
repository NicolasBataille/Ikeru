import Testing
import Foundation
import SwiftData
import UIKit
import ImageIO
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

    /// L'écran de suppression promet « seuls les mots que ce texte a été le seul
    /// à apporter sont retirés ». `entryIDs` est ce qui décide, et il est
    /// documenté comme « les entrées CRÉÉES à partir de cet import ».
    /// `VocabularyRepository.addEntry` rend l'entrée existante quand le mot est
    /// déjà là — donc revendiquer aveuglément ce qu'il rend fait entrer dans
    /// `entryIDs` un mot que l'apprenant possédait déjà, et supprimer l'import
    /// emporte alors une carte avec tout son historique FSRS.
    ///
    /// Le cas est étroit — `knownForms` écarte normalement les mots du
    /// dictionnaire — mais il est atteignable : le mot arrive entre l'analyse
    /// et l'enregistrement (ajout à la main dans un autre écran, ou une synchro
    /// qui atterrit). Étroit et destructeur vaut un garde-fou.
    @Test("Un mot déjà au dictionnaire n'est pas revendiqué par l'import qui l'a recroisé")
    func preexistingDictionaryWordsAreNotClaimed() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)
        let vocabulary = VocabularyRepository(modelContainer: container)

        viewModel.begin(with: "本日のおすすめは鶏の唐揚げ定食です。", source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        let target = try #require(viewModel.unknownWords
            .first { viewModel.isSelected($0) }?.dictionaryForm)

        // Le mot entre au dictionnaire APRÈS l'analyse : `knownForms` est un
        // instantané, il ne le voit pas.
        let handAdded = await vocabulary.addEntry(word: target, reading: "てすと",
                                                  meaning: "ajouté à la main")
        await viewModel.save()

        let imports = TextImportRepository(modelContainer: container)
        let created = try #require(await imports.all().first)
        #expect(!created.entryIDs.contains(handAdded.id),
                "l'import ne revendique pas un mot qu'il n'a pas apporté")
        #expect(!viewModel.savedEntryIDs.contains(handAdded.id),
                "la mini-séance ne repropose pas une carte déjà planifiée")

        // La rencontre, elle, est bien enregistrée : le contexte est gardé même
        // si la provenance ne l'est pas.
        let encounters = await vocabulary.encounters(for: handAdded.id)
        #expect(encounters.contains { $0.source == .importedText })

        // Et la carte n'est pas seulement gardée : elle est gardée INTACTE.
        // `addEntry` écrase `meaning` avec la gloss JMdict quand l'entrée
        // existe déjà — mesuré, le sens « ajouté à la main » devenait
        // « aujourd'hui ». Recroiser un mot dans un texte ne donne pas le droit
        // de réécrire ce que l'apprenant en a écrit, et la gloss JMdict est
        // anglaise pour une majorité des mots courants (17 059 des 30 155
        // entrées communes n'ont pas de français) : l'écrasement rendait donc
        // aussi une carte anglaise sans étiquette.
        let after = try #require(await vocabulary.entry(by: handAdded.id))
        #expect(after.meaning == "ajouté à la main",
                "le sens écrit par l'apprenant a été écrasé par la gloss du dictionnaire")
        #expect(after.reading == "てすと",
                "la lecture écrite par l'apprenant a été écrasée")

        _ = await imports.delete(id: created.id)
        #expect(await vocabulary.entry(by: handAdded.id) != nil,
                "le mot ajouté à la main survit à la suppression de l'import")
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

    /// La provenance affichée doit être celle du texte qu'on regarde.
    ///
    /// `source` n'est écrit que par `begin(with:source:)` — collage et OCR.
    /// Le champ de saisie, lui, est lié directement à `draft` : taper au
    /// clavier ne repasse jamais par là. Avant le correctif, `reset()` gardait
    /// la provenance précédente, donc « importer un autre texte » après une
    /// photo puis taper à la main donnait un import étiqueté « photographié »
    /// dans le journal de lecture — et dans la colonne `source` poussée au
    /// cloud.
    @Test("Un texte tapé après une photo n'hérite pas de « photographié »")
    func resetForgetsThePreviousSource() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)

        viewModel.begin(with: "犬がいる。", source: .photo)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        await viewModel.save()

        viewModel.reset()
        // Le clavier, pas le presse-papiers : personne n'appelle `begin`.
        viewModel.draft = "猫がいる。"
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        await viewModel.save()

        let imports = await TextImportRepository(modelContainer: container).all()
        #expect(imports.count == 2)
        let photographed = try #require(imports.first { $0.content == "犬がいる。" })
        #expect(photographed.source == .photo)
        let typed = try #require(imports.first { $0.content == "猫がいる。" })
        #expect(typed.source == .paste,
                "un texte tapé au clavier a été enregistré comme photographié")
    }
}

// MARK: - Chemin photo → texte

/// Ce que la vue fait des octets d'une photo, avant que le japonais entre en
/// jeu. Ces tests ne font pas tourner Vision : ils épinglent le câblage qui,
/// s'il casse, se présente à l'utilisateur comme « aucun texte horizontal
/// trouvé » sur une page parfaitement horizontale.
@MainActor
@Suite("TextImport — capture photo")
struct TextImportPhotoCaptureTests {

    /// `TextImportCameraPicker` encode la prise de vue en JPEG avant de la
    /// passer plus loin. Toute la chaîne d'orientation en dépend : si
    /// `jpegData(compressionQuality:)` perdait le tag EXIF, une photo cadrée en
    /// portrait arriverait couchée chez Vision, qui ne lirait rien.
    ///
    /// À noter : `pngData()`, lui, **perd** l'orientation. Ne pas remplacer
    /// l'encodage du picker sans rejouer ce test.
    @Test("Encoder en JPEG conserve l'orientation de la prise de vue")
    func jpegEncodingKeepsTheOrientation() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4))
        let landscape = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        let cgImage = try #require(landscape.cgImage)
        // Ce qu'un iPhone tenu verticalement produit : des pixels paysage plus
        // une rotation consignée à côté.
        let asShot = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let data = try #require(asShot.jpegData(compressionQuality: 0.9))
        let reloaded = try #require(UIImage(data: data))

        #expect(reloaded.imageOrientation == .right)

        // Et le tag est bien dans le fichier — c'est lui que
        // `TextRecognitionService.recognizeText(in: Data)` va lire.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = try #require(properties?[kCGImagePropertyOrientation] as? UInt32)
        #expect(CGImagePropertyOrientation(rawValue: raw) == .right)
    }

    /// Des octets qui ne sont pas une image se disent « image illisible », pas
    /// « texte vertical » : accuser le japonais vertical d'un fichier corrompu
    /// enverrait l'utilisateur retaper un texte pour rien.
    @Test("Des octets illisibles ne sont pas accusés d'être du texte vertical")
    func undecodableBytesAreNotBlamedOnVerticalText() async throws {
        await #expect(throws: TextRecognitionError.imageUnreadable) {
            _ = try await TextImportCaptureView.recognizeOnDevice(Data("pas une image".utf8))
        }
    }
}

// MARK: - Fidélité du texte affiché

/// La promesse numéro un de la feature : **le texte de l'apprenant n'est ni
/// réécrit, ni tronqué, ni réordonné**. `AnalyzedText` la tient déjà côté Core
/// (`JapaneseTextAnalyzerTests` vérifie que les jetons recomposent la source) ;
/// ce qui n'était vérifié nulle part, c'est la couche vue : `ReadingLine.build`
/// redécoupe ces jetons en lignes et en runs pour `IkeruFlowLayout`, et c'est
/// ce découpage-là qui dessine à l'écran.
///
/// Un caractère perdu ici — une ligne blanche avalée, un espace latin mangé,
/// un emoji tombé entre deux runs — ne se voit dans aucun test existant et se
/// voit tout de suite chez l'utilisateur.
@Suite("Lecture assistée — le texte redessiné est le texte source")
struct AssistedReadingTextFidelityTests {

    /// Ce que la vue dessine, remis à plat : les morceaux d'une ligne bout à
    /// bout, les lignes séparées par le saut de ligne qu'elles matérialisent.
    private func redrawn(_ tokens: [AnalyzedToken]) -> String {
        ReadingLine.build(from: tokens)
            .map { $0.segments.map(\.text).joined() }
            .joined(separator: "\n")
    }

    private func analyzer() throws -> JapaneseTextAnalyzer {
        JapaneseTextAnalyzer(dictionary: DictionaryRepository(bundleURL: try dictionaryURL()))
    }

    @Test("Le rendu recompose la source au caractère près", arguments: [
        "今日は雨。",
        "今日は朝から雨が降っていて、電車がめちゃくちゃ混んでた。",
        // Ligne blanche voulue par l'apprenant : elle doit survivre.
        "一行目\n\n三行目",
        // Saut de ligne final.
        "犬がいる。\n",
        // Latin et espaces multiples : `appendRun` recoupe après chaque espace,
        // et aucun de ces espaces n'a le droit de disparaître.
        "Hello   world, 今日は雨。",
        // Emoji, y compris avec sélecteur de variante.
        "🌧️ 今日は雨。😊",
        // Espaces en tête et en fin de ligne.
        "  今日は雨。  \n  明日は晴れ。",
        // Ponctuation pleine largeur et guillemets japonais.
        "「おい、そこで何をしている！」",
    ])
    func redrawnTextEqualsSource(_ source: String) async throws {
        let analyzed = await (try analyzer()).analyze(source)
        // Garde-fou : si le Core lui-même perdait un caractère, le test dirait
        // « la vue est fautive » alors qu'elle ne l'est pas.
        #expect(analyzed.tokens.map(\.surface).joined() == source,
                "prérequis : les jetons recomposent déjà la source")
        #expect(redrawn(analyzed.tokens) == source,
                "le découpage en lignes de la vue a modifié le texte")
    }

    /// Le même contrat sans dictionnaire ni tokeniser, pour que la panne reste
    /// diagnosticable si un jour le découpage change : ici tout est en dur.
    @Test("Un saut de ligne devient une ligne, pas un caractère avalé")
    func lineBreaksBecomeLines() {
        let tokens = [
            AnalyzedToken(id: 0, surface: "犬", isWord: true),
            AnalyzedToken(id: 1, surface: "。\n\n", isWord: false),
            AnalyzedToken(id: 2, surface: "猫", isWord: true),
        ]
        let lines = ReadingLine.build(from: tokens)
        #expect(lines.count == 3, "deux sauts consécutifs = une ligne blanche entre les deux")
        #expect(lines[1].segments.isEmpty)
        #expect(redrawn(tokens) == "犬。\n\n猫")
    }
}

// MARK: - Les deux vides de l'écran de sélection

/// `WordSelectionView` affiche « tu connais déjà tous les mots d'ici » quand la
/// liste des inconnus est vide. Mais elle est vide dans DEUX cas très
/// différents, et un seul mérite ces félicitations : celui où le dictionnaire a
/// reconnu des mots. Sur un texte qu'il n'a pas su lire — argot, noms propres,
/// photo mal reconnue — les féliciter serait inventer.
///
/// La vue tranche sur `coverage == nil`. Ces tests épinglent ce que ce `nil`
/// veut dire, des deux côtés.
@Suite("Sélection — « tout connu » n'est pas « rien reconnu »")
@MainActor
struct TextImportEmptyStatesTests {

    @Test("Un texte sans mot de contenu n'a pas de couverture mesurable")
    func noContentWordMeansNoCoverage() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "ZZZQQQ WWWW", source: .paste)
        await viewModel.analyzeDraft()

        #expect(viewModel.stage == .reading)
        #expect(viewModel.unknownWords.isEmpty)
        // C'est cette valeur qui fait dire « aucun mot reconnu » plutôt que
        // « tu connais tout ».
        #expect(viewModel.coverage == nil)
    }

    @Test("Un texte entièrement connu a une couverture de 100 %")
    func fullyKnownTextHasFullCoverage() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)
        let vocabulary = VocabularyRepository(modelContainer: container)

        // On apprend d'abord les mots, puis on relit le texte : la liste des
        // inconnus est vide, mais la couverture, elle, existe.
        viewModel.begin(with: "本日のおすすめは鶏の唐揚げ定食です。", source: .paste)
        await viewModel.analyzeDraft()
        for word in viewModel.analysis?.learnableWords ?? [] {
            guard let form = word.dictionaryForm else { continue }
            _ = await vocabulary.addEntry(word: form, reading: word.entry?.reading ?? "",
                                          meaning: "—")
        }
        await viewModel.analyzeDraft()

        #expect(viewModel.unknownWords.isEmpty)
        #expect(viewModel.coverage == 1)
    }
}

// MARK: - Ce que les sceptiques ont trouvé

/// Chaque test ici rejoue une panne trouvée par la relecture adversariale du
/// 2026-08-20 — pas un cas de laboratoire.
@Suite("Texte perso — pannes trouvées en relecture")
@MainActor
struct TextImportReviewFindingsTests {

    /// Le plafond ÉCRASAIT la sélection au lieu de la compléter.
    ///
    /// Inoffensif tant que rien ne pouvait cocher avant. Devenu une perte
    /// réelle dès que « + apprendre » existe en lecture et qu'on peut revenir
    /// de la sélection : un mot retenu à la fiche, ou huit décochages patients,
    /// disparaissaient sans un mot.
    @Test("Revenir à la sélection ne réécrit pas les choix de l'apprenant")
    func returningToSelectionKeepsChoices() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: """
            今日は朝から雨が降っていて、電車がめちゃくちゃ混んでた。
            新しいカフェが駅前にオープンしたらしいので、週末に行ってみようと思います。
            """, source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()

        // L'apprenant décoche tout, puis retourne lire.
        for word in viewModel.unknownWords where viewModel.isSelected(word) {
            viewModel.toggle(word)
        }
        #expect(viewModel.selectedCount == 0)
        viewModel.backToReading()
        #expect(viewModel.stage == .reading)

        // Et revient : ses décochages tiennent, le plafond ne repasse pas.
        viewModel.moveToSelection()
        #expect(viewModel.selectedCount == 0,
                "le plafond a réécrit la sélection de l'apprenant")
    }

    /// « + apprendre » depuis la lecture : la troisième affordance que la
    /// vision demande sur un mot tappé, et qui n'était branchée nulle part.
    @Test("Retenir un mot depuis la lecture le pré-coche, et le plafond le respecte")
    func learningFromReadingSurvivesTheCap() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "季節の野菜天ぷらと鶏の唐揚げ定食。", source: .paste)
        await viewModel.analyzeDraft()

        let chosen = try #require(viewModel.unknownWords.last)
        viewModel.learn(chosen)
        #expect(viewModel.isSelected(chosen))

        viewModel.moveToSelection()
        #expect(viewModel.isSelected(chosen),
                "le mot retenu en lecture a été effacé par le pré-cochage")
    }

    @Test("Un mot non apprenable ne se retient pas")
    func unlearnableTokensAreRefused() async throws {
        let viewModel = try makeViewModel(try makeContainer())
        viewModel.begin(with: "犬がいる。", source: .paste)
        await viewModel.analyzeDraft()
        let analysis = try #require(viewModel.analysis)
        // La particule が : reconnue, mais pas un mot à apprendre.
        if let particle = analysis.tokens.first(where: { $0.surface == "が" }) {
            viewModel.learn(particle)
            #expect(viewModel.selectedCount == 0)
        }
    }

    /// L'app étiquetait « EN » dans la lecture et la sélection, puis l'oubliait
    /// en créant la carte : « to be crowded… » partait nu au milieu d'un
    /// dictionnaire français. Environ une carte minée sur trois.
    @Test("Une gloss anglaise reste étiquetée jusque dans la carte SRS")
    func englishGlossesStayLabelledInTheCard() async throws {
        let container = try makeContainer()
        let viewModel = try makeViewModel(container)
        viewModel.begin(with: "電車がめちゃくちゃ混んでた。", source: .paste)
        await viewModel.analyzeDraft()
        viewModel.moveToSelection()
        await viewModel.save()

        let entries = await VocabularyRepository(modelContainer: container).allEntries()
        #expect(!entries.isEmpty)
        // 混む n'a pas de gloss française dans JMdict : sa carte doit le dire.
        let crowded = entries.first { $0.word == "混む" }
        let meaning = try #require(crowded?.meaning)
        #expect(meaning.hasPrefix(TextImportViewModel.englishLabelPrefix),
                "gloss anglaise non étiquetée dans la carte : « \(meaning) »")

        // Et une gloss française ne porte JAMAIS l'étiquette.
        for entry in entries where !entry.meaning.hasPrefix(TextImportViewModel.englishLabelPrefix) {
            #expect(!entry.meaning.contains("EN —"))
        }
    }
}

// MARK: - Le QCM ne doit pas se gagner à la langue

/// La mini-séance tirait ses leurres dans tout le dictionnaire. Sur un
/// dictionnaire à 97 % français, une bonne réponse anglaise était la seule
/// option anglaise ~9 fois sur 10 : l'exercice se résolvait sans lire un kanji.
/// C'est la leçon des homophones du drill d'écoute et des suffixes du texte à
/// trou, une troisième fois.
@Suite("Quiz de vocabulaire — les leurres parlent la même langue")
@MainActor
struct VocabularyQuizLanguageTests {

    private func entry(_ word: String, _ meaning: String) -> VocabularyEntryDTO {
        VocabularyEntryDTO(id: UUID(), word: word, reading: word, meaning: meaning,
                           jlptLevel: .n5, fsrsState: FSRSState(), easeFactor: 2.5,
                           interval: 1, dueDate: Date(), lapseCount: 0,
                           isInDictionary: true, createdAt: Date(), encounterCount: 0)
    }

    @Test("Reconnaître le français et l'anglais")
    func languageHeuristic() {
        #expect(VocabularyDrillViewModel.looksEnglish("to be crowded; to be packed"))
        #expect(VocabularyDrillViewModel.looksEnglish("spoiler; revealing the plot of a story"))
        #expect(!VocabularyDrillViewModel.looksEnglish("pluie"))
        #expect(!VocabularyDrillViewModel.looksEnglish("fin de semaine; week-end"))
        #expect(!VocabularyDrillViewModel.looksEnglish("être; se trouver"))
        // Sans indice, on ne devine pas : on suppose la langue de l'app.
        #expect(!VocabularyDrillViewModel.looksEnglish("train"))
    }

    @Test("Une réponse anglaise n'est pas la seule option anglaise")
    func anEnglishAnswerIsNotTheOnlyEnglishOption() throws {
        let repository = VocabularyRepository(modelContainer: try makeContainer())
        let answer = entry("混む", "EN — to be crowded; to be packed")
        let dictionary = [answer]
            + (0..<12).map { entry("mot\($0)", ["pluie", "matin", "ami", "film"][$0 % 4]) }
            + (0..<4).map { entry("en\($0)", "EN — to do something with a thing") }

        // Répété : le tirage est aléatoire, une seule passe ne prouverait rien.
        for _ in 0..<30 {
            let viewModel = VocabularyDrillViewModel(
                queue: [answer], allEntries: dictionary,
                vocabularyRepository: repository)
            let english = viewModel.quizOptions.filter {
                VocabularyDrillViewModel.looksEnglish($0)
            }
            #expect(english.count > 1,
                    "la réponse anglaise est seule de sa langue : \(viewModel.quizOptions)")
        }
    }

    /// Le repli reste possible : mieux vaut une question aux langues mêlées
    /// qu'une question à deux options.
    @Test("Sans assez de leurres de la même langue, on complète plutôt que de tronquer")
    func mixedLanguagesBeatTwoOptions() throws {
        let answer = entry("混む", "EN — to be crowded")
        let dictionary = [answer] + (0..<6).map { entry("mot\($0)", ["pluie", "matin", "ami"][$0 % 3]) }
        let viewModel = VocabularyDrillViewModel(
            queue: [answer], allEntries: dictionary,
            vocabularyRepository: VocabularyRepository(modelContainer: try makeContainer()))
        #expect(viewModel.quizOptions.count == 4)
        #expect(viewModel.quizOptions.contains("EN — to be crowded"))
    }
}
