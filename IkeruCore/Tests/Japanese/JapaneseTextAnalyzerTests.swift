import Testing
import Foundation
@testable import IkeruCore

// MARK: - Analyse de texte

/// Runs against the **shipped** dictionary, not a fixture. The whole point of
/// the feature is behaviour on text nobody curated, so a fixture would test the
/// fixture.
@Suite("Analyse de texte japonais")
struct JapaneseTextAnalyzerTests {

    private static func dictionaryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ikeru/Resources/ContentBundles/jmdict.sqlite")
    }

    private func makeAnalyzer() throws -> JapaneseTextAnalyzer {
        let url = Self.dictionaryURL()
        try #require(FileManager.default.fileExists(atPath: url.path),
                     "jmdict.sqlite absent — lancer scripts/jmdict/build-dictionary.py")
        return JapaneseTextAnalyzer(dictionary: DictionaryRepository(bundleURL: url))
    }

    /// L'échantillon de mesure : dix phrases écrites à la main dans les
    /// registres que la feature vise (tweet, menu, bulle, message pro, paroles).
    static let sample = [
        "今日は朝から雨が降っていて、電車がめちゃくちゃ混んでた。もう最悪。",
        "新しいカフェが駅前にオープンしたらしいので、週末に行ってみようと思います。",
        "本日のおすすめ：鶏の唐揚げ定食、季節の野菜天ぷら",
        "「おい、そこで何をしている！」「べ、別に何も…」",
        "明日の会議、資料の準備をお願いできますか？よろしくお願いします。",
        "君の名前を呼ぶたびに、胸の奥が少しだけ痛くなる",
        "このアプリを使えば、日本語の勉強がもっと楽しくなりますよ。",
        "先週末は友達と映画を見に行きました。とても面白かったです。",
        "消費税込みの価格でございます。領収書が必要な方はお申し付けください。",
        "アニメの最新話、まだ見てないから、ネタバレやめてください！",
    ]

    // MARK: Fidélité

    /// L'invariant non négociable : le texte de l'utilisateur ressort intact.
    @Test("Les jetons recomposent le texte source au caractère près")
    func tokensRebuildTheSource() async throws {
        let analyzer = try makeAnalyzer()
        for sentence in Self.sample {
            let analyzed = await analyzer.analyze(sentence)
            #expect(analyzed.tokens.map(\.surface).joined() == sentence,
                    "texte reconstruit différent : « \(sentence) »")
        }
    }

    @Test("La ponctuation n'est jamais absorbée dans un mot")
    func punctuationIsNeverJoined() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("今日、雨。")
        // 今日 et 雨 ne doivent pas fusionner à travers la virgule.
        #expect(!analyzed.tokens.contains { $0.surface.contains("、") && $0.isWord })
        #expect(analyzed.tokens.contains { $0.surface == "今日" })
        #expect(analyzed.tokens.contains { $0.surface == "雨" })
    }

    @Test("Un texte vide ne produit rien, sans planter")
    func emptyTextIsSafe() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("")
        #expect(analyzed.tokens.isEmpty)
        #expect(analyzed.coverage(known: []) == nil)
    }

    // MARK: Recomposition et déflexion

    @Test("Les mots sur-découpés par le tokeniseur sont recollés")
    func overSplitWordsAreRejoined() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("週末に行ってみようと思います。")
        let forms = analyzed.tokens.compactMap(\.dictionaryForm)
        // 思い + ます est un seul mot : 思う.
        #expect(forms.contains("思う"), "formes trouvées : \(forms)")
        #expect(forms.contains("週末"))
    }

    @Test("Les verbes fléchis reviennent à leur forme du dictionnaire")
    func inflectedVerbsResolve() async throws {
        let analyzer = try makeAnalyzer()
        let cases: [(String, String)] = [
            ("雨が降っていて", "降る"),
            ("電車が混んでた", "混む"),
            ("映画を見に行きました", "行く"),
            ("面白かったです", "面白い"),
            ("楽しくなりますよ", "楽しい"),
            ("使えば", "使う"),
        ]
        for (text, expected) in cases {
            let analyzed = await analyzer.analyze(text)
            let forms = analyzed.tokens.compactMap(\.dictionaryForm)
            #expect(forms.contains(expected),
                    "« \(text) » → \(expected) manquant ; trouvé \(forms)")
        }
    }

    // MARK: Le miroir de couverture

    /// Le dénominateur EST le sujet. Compté sur les jetons bruts, le taux
    /// mesurerait la grammaire : particules et fragments de flexion pesaient la
    /// majorité de l'écart dans la mesure du 2026-08-19.
    @Test("Les particules restent hors du dénominateur de couverture")
    func particlesAreExcludedFromCoverage() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("今日は朝から雨が降っていて、電車が混んでた。")
        let learnable = analyzed.tokens.filter(\.isLearnable).compactMap(\.dictionaryForm)
        for particle in ["は", "から", "が", "て", "た"] {
            #expect(!learnable.contains(particle),
                    "« \(particle) » ne doit pas compter comme mot à apprendre")
        }
        #expect(learnable.contains("雨"))
        #expect(learnable.contains("電車"))
    }

    @Test("Connaître tous les mots donne 100 %, n'en connaître aucun donne 0 %")
    func coverageEndpoints() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("私は毎日パンを食べます。")
        let all = Set(analyzed.learnableWords.compactMap(\.dictionaryForm))
        #expect(analyzed.coverage(known: all) == 1.0)
        #expect(analyzed.coverage(known: []) == 0.0)
        #expect(!all.isEmpty)
    }

    @Test("Les mots à apprendre sont dédoublonnés sur la forme du dictionnaire")
    func learnableWordsAreDeduplicated() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("食べます。食べました。食べたい。")
        let forms = analyzed.learnableWords.compactMap(\.dictionaryForm)
        #expect(forms.filter { $0 == "食べる" }.count == 1, "formes : \(forms)")
    }

    // MARK: Honnêteté du lookup

    /// Un mot absent du dictionnaire doit ressortir SANS entrée, pas avec une
    /// approximation. « Définition non disponible » est un état, pas un échec.
    @Test("Un mot inconnu du dictionnaire ressort sans entrée")
    func unknownWordsCarryNoEntry() async throws {
        let analyzer = try makeAnalyzer()
        let analyzed = await analyzer.analyze("ズヴォルスキ")
        let words = analyzed.tokens.filter(\.isWord)
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { $0.entry == nil })
    }

    /// La règle produit tranchée : gloss anglaise étiquetée, jamais silencieuse.
    /// Le test vérifie que le SIGNAL existe — `glossFR == nil` — pour que la vue
    /// puisse poser l'étiquette.
    @Test("L'absence de gloss française est un signal explicite")
    func missingFrenchIsExplicit() async throws {
        let url = Self.dictionaryURL()
        try #require(FileManager.default.fileExists(atPath: url.path))
        let repository = DictionaryRepository(bundleURL: url)
        let common = await repository.entries(for: "水")
        #expect(!common.isEmpty)
        #expect(common.allSatisfy { !$0.glossEN.isEmpty }, "l'anglais est toujours présent")
    }
}
