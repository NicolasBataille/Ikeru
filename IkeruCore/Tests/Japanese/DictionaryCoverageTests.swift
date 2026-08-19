import Testing
import Foundation
@testable import IkeruCore

// MARK: - Couverture du dictionnaire

/// The measurement that justified shipping a 27 Mo dictionary, kept as a
/// regression guard.
///
/// Before JMdict, the curated N5 bundle resolved **18 % of the occurrences** of
/// the ten hand-written sentences below — and most of the gap was particles and
/// inflection fragments rather than vocabulary. Any change to the deinflection
/// table, the ranking, or the bundle that pushes these numbers back down is a
/// regression in the only thing this feature sells: reading text nobody curated.
@Suite("Couverture du dictionnaire")
struct DictionaryCoverageTests {

    private func makeAnalyzer() throws -> JapaneseTextAnalyzer {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ikeru/Resources/ContentBundles/jmdict.sqlite")
        try #require(FileManager.default.fileExists(atPath: url.path),
                     "jmdict.sqlite absent — lancer scripts/jmdict/build-dictionary.py")
        return JapaneseTextAnalyzer(dictionary: DictionaryRepository(bundleURL: url))
    }

    @Test("Le dictionnaire expédié résout l'essentiel d'un texte réel")
    func shippedDictionaryResolvesRealText() async throws {
        let analyzer = try makeAnalyzer()
        var words = 0
        var resolved = 0
        var unresolved: [String] = []

        for sentence in JapaneseTextAnalyzerTests.sample {
            let analyzed = await analyzer.analyze(sentence)
            for token in analyzed.tokens where token.isWord {
                words += 1
                if token.entry != nil {
                    resolved += 1
                } else {
                    unresolved.append(token.surface)
                }
            }
        }

        let rate = Double(resolved) / Double(words)
        #expect(rate >= 0.90,
                "\(resolved)/\(words) résolus (\(Int(rate * 100)) %) — non résolus : \(unresolved)")
    }

    /// Le miroir mesure le vocabulaire, pas la grammaire : les mots de contenu
    /// doivent être nettement moins nombreux que les jetons bruts.
    @Test("Les mots à apprendre sont une minorité des jetons")
    func contentWordsAreAMinorityOfTokens() async throws {
        let analyzer = try makeAnalyzer()
        var tokens = 0
        var learnable = 0
        for sentence in JapaneseTextAnalyzerTests.sample {
            let analyzed = await analyzer.analyze(sentence)
            tokens += analyzed.tokens.filter(\.isWord).count
            learnable += analyzed.tokens.filter(\.isLearnable).count
        }
        #expect(learnable < tokens, "\(learnable) mots de contenu pour \(tokens) jetons")
        #expect(Double(learnable) / Double(tokens) > 0.3,
                "trop peu de mots de contenu : \(learnable)/\(tokens)")
    }

    /// Le critère de réussite de la feature est un chronomètre : « moins d'une
    /// minute » entre la phrase croisée et la mini-séance proposée. L'analyse
    /// est le seul maillon qui puisse le manger, et c'est pour ça que les
    /// candidats sont résolus en UNE requête par texte et pas une par jeton.
    /// Ce test épingle la décision : un paragraphe doit s'analyser en bien
    /// moins d'une seconde.
    @Test("Un paragraphe s'analyse instantanément")
    func aParagraphAnalysesInstantly() async throws {
        let analyzer = try makeAnalyzer()
        let paragraph = JapaneseTextAnalyzerTests.sample.joined(separator: "\n")
        // Un texte cinq fois plus long qu'un tweet, soit le haut de la
        // fourchette que la vision vise (« des textes courts à moyens »).
        let long = Array(repeating: paragraph, count: 5).joined(separator: "\n")

        let started = Date()
        let analyzed = await analyzer.analyze(long)
        let elapsed = Date().timeIntervalSince(started)

        #expect(!analyzed.tokens.isEmpty)
        #expect(elapsed < 2.0, "analyse en \(Int(elapsed * 1000)) ms — le lot de requêtes a-t-il sauté ?")
    }

    /// Chaque cas ci-dessous est une mauvaise réponse RÉELLEMENT observée sur
    /// l'échantillon, pas un cas de laboratoire. Ils épinglent le classement
    /// des candidats, qui est la partie la plus facile à casser en croyant
    /// l'améliorer : chaque marche du score a été posée par l'une de ces
    /// lignes, et l'enlever en refait tomber une.
    @Test("Les ambiguïtés déjà tranchées le restent")
    func settledAmbiguitiesStaySettled() async throws {
        let analyzer = try makeAnalyzer()
        // (texte, surface attendue, forme du dictionnaire attendue)
        let cases: [(String, String, String)] = [
            // Un joint gourmand avalait la particule : 今日 + は donnait
            // こんにちは « bonjour ».
            ("今日は朝から", "今日", "今日"),
            // 何 + を donnait なにを (adv int), そこ + で donnait そこで (conj).
            ("そこで何をしている", "何", "何"),
            ("そこで何をしている", "そこ", "そこ"),
            // 行く et 行う partagent 行って ; les journaux préfèrent 行う, pas
            // l'apprenant.
            ("週末に行ってみよう", "行って", "行く"),
            ("映画を見に行きました", "行きました", "行く"),
            // La particule で ressortait en 出る parce que 出る est au N5.
            ("駅前にオープンしたので", "で", "で"),
            // Un nom en -する juste avant : した est する, pas 下.
            ("駅前にオープンした", "した", "する"),
            // この était lu « 九 » (この est une vieille lecture de 9), だけ
            // « 岳 » : la lecture principale d'une entrée est principale.
            ("このアプリ", "この", "この"),
            ("少しだけ", "だけ", "だけ"),
            // やめる contre « le potentiel de やむ », qui demande une règle de
            // plus.
            ("ネタバレやめてください", "やめて", "やめる"),
            // お願い est `n vs vt int` : accessoirement interjection, donc il a
            // le droit de coller ses voisins.
            ("お願いします", "お願い", "お願い"),
            // 降って est aussi 下って (conj, « humblement ») : être écrit tel
            // quel ne prouve rien.
            ("雨が降っていて", "降っていて", "降る"),
        ]
        for (text, surface, expected) in cases {
            let analyzed = await analyzer.analyze(text)
            let token = analyzed.tokens.first { $0.surface == surface }
            #expect(token != nil,
                    "« \(surface) » n'est pas un jeton de « \(text) » ; jetons : \(analyzed.tokens.filter(\.isWord).map(\.surface))")
            #expect(token?.dictionaryForm == expected,
                    "« \(text) » : \(surface) → \(token?.dictionaryForm ?? "rien") au lieu de \(expected)")
        }
    }

    /// Le français est minoritaire dans JMdict (7 % des entrées, 43 % des
    /// courantes). La règle produit est donc : gloss anglaise ÉTIQUETÉE, jamais
    /// silencieuse. Ce test épingle que le signal existe et qu'il est fréquent —
    /// une vue qui l'ignorerait mentirait souvent, pas rarement.
    @Test("L'absence de français est fréquente, donc l'étiquette est obligatoire")
    func frenchIsOftenAbsent() async throws {
        let analyzer = try makeAnalyzer()
        var withFrench = 0
        var total = 0
        for sentence in JapaneseTextAnalyzerTests.sample {
            let analyzed = await analyzer.analyze(sentence)
            for token in analyzed.tokens {
                guard let entry = token.entry else { continue }
                total += 1
                if entry.glossFR != nil { withFrench += 1 }
            }
        }
        #expect(total > 0)
        #expect(withFrench < total,
                "toutes les entrées ont du français — l'étiquette EN serait morte, vérifier")
    }
}
