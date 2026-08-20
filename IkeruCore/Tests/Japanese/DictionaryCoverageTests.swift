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

    /// Ce que le test précédent ne dit PAS : à quoi le temps est proportionnel.
    ///
    /// Décomposition mesurée le 2026-08-19 (release, 6 079 caractères) :
    /// segmentation 8 ms, requête dictionnaire 5 ms, **déflexion 1 485 ms**. Le
    /// lot de requêtes n'était pas le coût dominant ; `deinflect` appelé une
    /// fois par joint l'était, et les joints se répètent — 10 620 appels pour
    /// 479 chaînes distinctes. D'où le mémo dans `analyze`, et d'où ce test :
    /// **seize fois le même texte ne doit pas coûter seize fois**.
    ///
    /// Un RAPPORT, pas un chronomètre absolu : il se recalibre tout seul sur la
    /// machine et sur le mode de compilation (un `swift test` est en debug), là
    /// où un seuil en millisecondes clignote au premier runner chargé. Mesuré
    /// après correction : rapport ≈ 1,4. Avant : ≈ 8. Le seuil à 4 laisse donc
    /// deux fois la marge d'un côté comme de l'autre.
    @Test("Répéter le même texte ne répète pas le travail")
    func repeatedTextDoesNotRepeatTheWork() async throws {
        let analyzer = try makeAnalyzer()
        let paragraph = JapaneseTextAnalyzerTests.sample.joined(separator: "\n")
        func time(_ multiple: Int) async -> TimeInterval {
            let text = Array(repeating: paragraph, count: multiple).joined(separator: "\n")
            var best = TimeInterval.infinity
            for _ in 0..<3 {
                let started = Date()
                _ = await analyzer.analyze(text)
                best = min(best, Date().timeIntervalSince(started))
            }
            return best
        }
        let reference = await time(2)
        let sixteen = await time(16)
        let ratio = sixteen / max(reference, 0.001)
        #expect(ratio < 4,
                "×16 coûte ×\(String(format: "%.1f", ratio)) le ×2 (\(Int(sixteen * 1000)) ms contre \(Int(reference * 1000)) ms) — le mémo de déflexion de `analyze` a-t-il sauté ?")
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
            //
            // ⚠️ Cette ligne attendait la surface « 行って » seule. Depuis que
            // les auxiliaires d'aspect s'enchaînent, le joint va jusqu'à
            // 行ってみよう — même convention que 降っていて plus bas, et c'est
            // un GAIN : découpé, le みよう de 〜てみる ressortait en 見様
            // (« point de vue », mesuré), un nom proposé à l'apprentissage là
            // où le texte ne porte qu'un auxiliaire. La forme du dictionnaire,
            // qui est ce que la ligne épingle vraiment, n'a pas bougé.
            ("週末に行ってみよう", "行ってみよう", "行く"),
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

            // — Registre familier, honorifique, copule. Chaque ligne ci-dessous
            // rendait AVANT un mot de contenu faux, c'est-à-dire pire qu'un
            // « définition non disponible » : l'apprenant se voyait proposer
            // d'apprendre un mot qui n'est pas dans son texte.
            ("宿題を忘れちゃった。", "忘れちゃった", "忘れる"),
            ("ビールを全部飲んじゃった。", "飲んじゃった", "飲む"),
            ("先に買っとくね。", "買っとく", "買う"),
            ("もう行かなきゃ。", "行かなきゃ", "行く"),
            // ました seul ressortait en 真下, « juste en dessous ».
            ("先生がいらっしゃいました。", "いらっしゃいました", "いらっしゃる"),
            ("手伝ってくださいました。", "くださいました", "くださる"),
            ("本日はありがとうございます。", "ございます", "ござる"),
            // でし seul ressortait en 弟子, « disciple ».
            ("静かな部屋でした。", "でした", "です"),
            // あり seul ressortait en 蟻, « fourmi ».
            ("学生ではありません。", "ありません", "ある"),
            // おいて ressortait en 追手 (« poursuivant »), きます en 着る.
            ("書いておいてください。", "書いておいて", "書く"),
            ("行ってきます。", "行ってきます", "行く"),
            // 待たす existe, mais l'apprenant réutilise 待つ.
            ("一時間も待たされました。", "待たされました", "待つ"),
            // Le radical en い : 聴き « l'ouïe », 寝 « le sommeil », 難し
            // (adjectif classique) — trois noms pour trois verbes et un
            // adjectif ordinaires.
            ("音楽を聴きながら歩いた。", "聴きながら", "聴く"),
            ("早く寝なさい。", "寝なさい", "寝る"),
            ("この本は難しすぎる。", "難しすぎる", "難しい"),

            // — Joints gourmands : ces quatre lignes vérifient qu'un mot
            // ORDINAIRE ressort là où le joint avalait une particule pour
            // fabriquer un nom rare. そう + だ donnait 操舵 (« gouverne d'un
            // bateau »), が + そう 画僧 (« moine-peintre »), に + お 鳰
            // (« grèbe castagneux »), そこ + に 底荷 (« lest »).
            ("そうだ、明日は休みだ。", "そう", "そう"),
            ("社長がそうおっしゃいました。", "が", "が"),
            ("先輩にお酒を飲まされた。", "お酒", "お酒"),
            ("そこに立っているのは誰ですか。", "そこ", "そこ"),
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
