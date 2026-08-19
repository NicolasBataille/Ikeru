import Testing
import Foundation
@testable import IkeruCore

// MARK: - Grammar cloze

/// Couvre l'exercice de grammaire a trou : le constructeur d'options, et la
/// lecture depuis le bundle expedie.
///
/// Le test qui compte est `aDistractorNeverAlsoFits` : un distracteur qui
/// remplit le trou aussi bien que la reponse rend la question fausse, pas
/// difficile. C'est la meme lecon que les homophones dans les drills d'ecoute,
/// ou le filtre etait sur par accident jusqu'a ce que le vocabulaire triple.
@Suite("Grammar cloze")
struct GrammarClozeTests {

    /// Generateur deterministe, pour que « melange » reste assertable.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test("Les options contiennent la reponse exactement une fois")
    func answerAppearsExactlyOnce() {
        var generator = SeededGenerator(state: 42)
        let options = GrammarClozeOptionsBuilder.build(
            answer: "てもいい",
            pool: ["てはいけません", "ください", "から", "ましょう"],
            using: &generator
        )
        #expect(options.options.count == 4)
        #expect(options.options.filter { $0 == "てもいい" }.count == 1)
        #expect(options.correctAnswer == "てもいい")
        #expect(options.options[options.correctIndex] == "てもいい")
    }

    /// Le test qui protege la question elle-meme.
    ///
    /// `もいい` est un SUFFIXE de `てもいい` : propose comme distracteur, il
    /// remplirait `写真を撮っ____ですか。` de facon defendable, et l'apprenant
    /// serait note faux pour une reponse juste. Idem dans l'autre sens.
    @Test("Un distracteur qui remplit aussi le trou est refuse")
    func aDistractorNeverAlsoFits() {
        var generator = SeededGenerator(state: 7)
        let options = GrammarClozeOptionsBuilder.build(
            answer: "てもいい",
            pool: ["もいい", "てもいいです", "てもいい", "から"],
            using: &generator
        )
        // Seul `から` survit : les trois autres sont soit identiques, soit
        // contenus dans la reponse, soit la contenant.
        #expect(options.options.count == 2)
        #expect(Set(options.options) == ["てもいい", "から"])
    }

    @Test("Les doublons du pool ne produisent pas deux fois la meme option")
    func duplicatesAreCollapsed() {
        var generator = SeededGenerator(state: 99)
        let options = GrammarClozeOptionsBuilder.build(
            answer: "ました",
            pool: ["ません", "ません", "ください", "ください"],
            using: &generator
        )
        #expect(Set(options.options).count == options.options.count)
    }

    @Test("Un pool vide rend la seule bonne reponse, sans planter")
    func emptyPoolDegradesGracefully() {
        var generator = SeededGenerator(state: 1)
        let options = GrammarClozeOptionsBuilder.build(
            answer: "ました", pool: [], using: &generator)
        #expect(options.options == ["ました"])
        #expect(options.correctIndex == 0)
    }

    /// Contre le bundle EXPEDIE, pas une fixture : chaque exercice doit porter
    /// le marqueur de trou, une reponse non vide, et sa reponse ne doit PAS
    /// apparaitre dans la phrase trouee — sinon le trou n'en est pas un.
    @Test("Le bundle expedie porte des exercices coherents")
    func shippedClozesAreConsistent() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = root
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")
        try #require(FileManager.default.fileExists(atPath: bundleURL.path))

        let repo = ContentRepository(bundleURL: bundleURL, language: .french)
        let clozes = await repo.grammarClozes(for: .n5)

        #expect(clozes.count >= 40, "trop peu d'exercices : \(clozes.count)")
        for cloze in clozes {
            #expect(cloze.sentence.contains(GrammarCloze.blank),
                    "pas de trou dans « \(cloze.sentence) »")
            #expect(!cloze.answer.isEmpty)
            #expect(!cloze.sentence.contains(cloze.answer),
                    "la reponse « \(cloze.answer) » est encore visible dans « \(cloze.sentence) »")
            // Le japonais SEUL : plus de traduction collee dedans.
            #expect(!cloze.sentence.contains(" — "),
                    "la phrase porte encore une traduction figee : « \(cloze.sentence) »")
        }
    }

    /// L'invariant qui empeche l'exercice d'etre gagnable a l'oreille.
    ///
    /// L'exercice joue la phrase completee par l'option SELECTIONNEE. Si une
    /// completion n'a pas de clip bundle, elle sort en synthese on-device —
    /// une autre voix — et l'apprenant reconnait la bonne reponse au timbre,
    /// sans rien connaitre a la grammaire. Mesure le 2026-08-19 avant
    /// correction : la bonne completion avait un clip 12 fois sur 12, une
    /// mauvaise 1 fois sur 12.
    ///
    /// Ce test ne verifie pas les fichiers (ils vivent dans la cible app) mais
    /// la condition qui les rend generables : des distracteurs FIXES, donc un
    /// nombre fini de completions.
    @Test("Chaque question porte trois distracteurs fixes")
    func distractorsAreFixedAndSafe() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = root
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")
        try #require(FileManager.default.fileExists(atPath: bundleURL.path))

        let clozes = await ContentRepository(bundleURL: bundleURL, language: .french)
            .grammarClozes(for: .n5)
        #expect(!clozes.isEmpty)

        for cloze in clozes {
            #expect(cloze.distractors.count == 3,
                    "« \(cloze.answer) » a \(cloze.distractors.count) distracteurs")
            // Aucun distracteur ne doit remplir le trou aussi bien que la reponse.
            for distractor in cloze.distractors {
                #expect(distractor != cloze.answer)
                #expect(!distractor.contains(cloze.answer))
                #expect(!cloze.answer.contains(distractor))
            }
            #expect(Set(cloze.distractors).count == cloze.distractors.count,
                    "distracteurs en double pour « \(cloze.answer) »")
            // La completion doit reellement remplir le trou.
            #expect(!cloze.completed(with: cloze.answer).contains(GrammarCloze.blank))
        }
    }

    /// Le defaut constate sur device : la traduction etait figee en anglais a la
    /// generation, donc un apprenant en francais lisait « Please do not come in
    /// here. ». Elle vient desormais de la colonne localisee.
    @Test("La traduction suit la langue de l'apprenant")
    func translationFollowsLanguage() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = root
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")
        try #require(FileManager.default.fileExists(atPath: bundleURL.path))

        let french = await ContentRepository(bundleURL: bundleURL, language: .french)
            .grammarClozes(for: .n5)
        let english = await ContentRepository(bundleURL: bundleURL, language: .english)
            .grammarClozes(for: .n5)

        #expect(french.count == english.count)
        #expect(french.allSatisfy { !$0.translation.isEmpty })

        // Le japonais est le meme des deux cotes ; les traductions different.
        let sameJapanese = zip(french, english).allSatisfy { $0.sentence == $1.sentence }
        #expect(sameJapanese, "le japonais ne doit pas dependre de la langue")
        let differing = zip(french, english).filter { $0.translation != $1.translation }
        #expect(differing.count >= 40,
                "seulement \(differing.count) traductions different — la localisation ne prend pas")
    }

    @Test("Les reponses du bundle forment un pool de distracteurs utilisable")
    func shippedAnswersMakeAPool() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = root
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")
        try #require(FileManager.default.fileExists(atPath: bundleURL.path))

        let repo = ContentRepository(bundleURL: bundleURL, language: .english)
        let clozes = await repo.grammarClozes(for: .n5)
        let pool = clozes.map(\.answer)

        // Chaque exercice doit pouvoir presenter au moins deux choix, sinon la
        // question n'en est pas une.
        for cloze in clozes {
            let options = GrammarClozeOptionsBuilder.build(
                answer: cloze.answer,
                pool: pool.filter { $0 != cloze.answer }
            )
            #expect(options.options.count >= 2,
                    "« \(cloze.answer) » n'a pas trouve de distracteur")
        }
    }
}

// MARK: - Grammar card seeding

@Suite("Grammar card seeding")
struct GrammarCardSeederTests {

    private func point(_ id: Int, _ title: String) -> GrammarPoint {
        GrammarPoint(id: id, jlptLevel: .n5, title: title,
                     explanation: "explication", examples: ["例。 — ex."])
    }

    @Test("Un point sans carte est retenu, un point deja seme est ignore")
    func onlyMissingPointsAreSeeded() {
        let points = [point(1, "は (Topic)"), point(2, "を (Object)"), point(3, "に (Direction)")]
        let missing = GrammarCardSeeder.pointsNeedingCards(
            points, existingFronts: ["を (Object)"])
        #expect(missing.map(\.id) == [1, 3])
    }

    /// L'invariant qui protege contre un double semis — un lancement qui
    /// course, ou un re-semis apres effacement de profil.
    @Test("Un second passage ne retient plus rien")
    func secondPassIsEmpty() {
        let points = [point(1, "は (Topic)"), point(2, "を (Object)")]
        let fronts = Set(points.map(\.title))
        #expect(GrammarCardSeeder.pointsNeedingCards(points, existingFronts: fronts).isEmpty)
    }

    @Test("Un titre vide n'est jamais seme")
    func emptyTitlesAreSkipped() {
        let missing = GrammarCardSeeder.pointsNeedingCards(
            [point(1, ""), point(2, "は (Topic)")], existingFronts: [])
        #expect(missing.map(\.id) == [2])
    }
}
