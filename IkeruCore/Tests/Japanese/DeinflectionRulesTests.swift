import Testing
import Foundation
@testable import IkeruCore

// MARK: - Deinflection

/// Walks the hand-authored rule table back against known conjugations.
///
/// This suite is the reason the godan rules are generated from a conjugation
/// row rather than typed out ninety times: a transcription slip (う taking あ
/// instead of わ) produces a table that still compiles, still returns
/// candidates, and quietly teaches the wrong stem. Only a table of real
/// conjugations catches that.
@Suite("Déflexion japonaise")
struct DeinflectionRulesTests {

    /// Asserts `surface` can be walked back to `dictionary` under `pos`.
    private func expect(_ surface: String, _ dictionary: String, _ pos: String,
                        _ comment: Comment? = nil,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        let found = JapaneseDeinflector.deinflect(surface).contains {
            $0.term == dictionary && ($0.requiredPOS.isEmpty || $0.requiredPOS.contains(pos))
        }
        #expect(found, comment ?? "\(surface) → \(dictionary) (\(pos)) introuvable",
                sourceLocation: sourceLocation)
    }

    // MARK: Godan

    @Test("Les neuf classes godan reviennent à leur forme du dictionnaire")
    func godanClasses() {
        // une ligne par classe : poli, passé, forme en te, négatif
        let cases: [(String, String, String)] = [
            ("買います", "買う", "v5u"), ("買った", "買う", "v5u"),
            ("買って", "買う", "v5u"), ("買わない", "買う", "v5u"),
            ("書きます", "書く", "v5k"), ("書いた", "書く", "v5k"),
            ("書いて", "書く", "v5k"), ("書かない", "書く", "v5k"),
            ("泳ぎます", "泳ぐ", "v5g"), ("泳いだ", "泳ぐ", "v5g"),
            ("泳いで", "泳ぐ", "v5g"), ("泳がない", "泳ぐ", "v5g"),
            ("話します", "話す", "v5s"), ("話した", "話す", "v5s"),
            ("話して", "話す", "v5s"), ("話さない", "話す", "v5s"),
            ("待ちます", "待つ", "v5t"), ("待った", "待つ", "v5t"),
            ("待って", "待つ", "v5t"), ("待たない", "待つ", "v5t"),
            ("死にます", "死ぬ", "v5n"), ("死んだ", "死ぬ", "v5n"),
            ("死んで", "死ぬ", "v5n"), ("死なない", "死ぬ", "v5n"),
            ("遊びます", "遊ぶ", "v5b"), ("遊んだ", "遊ぶ", "v5b"),
            ("遊んで", "遊ぶ", "v5b"), ("遊ばない", "遊ぶ", "v5b"),
            ("読みます", "読む", "v5m"), ("読んだ", "読む", "v5m"),
            ("読んで", "読む", "v5m"), ("読まない", "読む", "v5m"),
            ("降ります", "降る", "v5r"), ("降った", "降る", "v5r"),
            ("降って", "降る", "v5r"), ("降らない", "降る", "v5r"),
        ]
        for (surface, dictionary, pos) in cases { expect(surface, dictionary, pos) }
    }

    /// La cellule la plus recopiée de travers : 買う prend わ, pas あ.
    @Test("La rangée en う prend わ au négatif, jamais あ")
    func uRowTakesWa() {
        expect("買わない", "買う", "v5u")
        let wrong = JapaneseDeinflector.deinflect("買あない").contains { $0.term == "買う" }
        #expect(!wrong, "×買あない ne doit mener à rien")
    }

    @Test("Les formes composées s'enchaînent")
    func chainedForms() {
        expect("書きました", "書く", "v5k", "poli passé")
        expect("書きませんでした", "書く", "v5k", "poli négatif passé")
        expect("読んでいる", "読む", "v5m", "progressif")
        expect("読んでいました", "読む", "v5m", "progressif poli passé")
        expect("買いたい", "買う", "v5u", "désidératif")
        expect("買いたかった", "買う", "v5u", "désidératif passé")
        expect("行かなかった", "行く", "v5k", "négatif passé")
        expect("待ったら", "待つ", "v5t", "conditionnel たら")
        expect("話せば", "話す", "v5s", "conditionnel ば")
        expect("泳ごう", "泳ぐ", "v5g", "volitif")
        expect("読める", "読む", "v5m", "potentiel")
        expect("読めます", "読む", "v5m", "potentiel poli")
        expect("読まれる", "読む", "v5m", "passif")
        expect("読ませる", "読む", "v5m", "causatif")
    }

    // MARK: Ichidan

    @Test("Les ichidan reviennent en -る")
    func ichidan() {
        expect("食べます", "食べる", "v1")
        expect("食べた", "食べる", "v1")
        expect("食べて", "食べる", "v1")
        expect("食べない", "食べる", "v1")
        expect("食べました", "食べる", "v1")
        expect("食べられる", "食べる", "v1")
        expect("食べさせる", "食べる", "v1")
        expect("食べたい", "食べる", "v1")
        expect("見ている", "見る", "v1")
        expect("食べれば", "食べる", "v1")
    }

    // MARK: Irréguliers

    @Test("する et 来る, en kana comme en kanji")
    func irregulars() {
        expect("します", "する", "vs-i")
        expect("した", "する", "vs-i")
        expect("して", "する", "vs-i")
        expect("しない", "する", "vs-i")
        expect("しました", "する", "vs-i")
        expect("勉強します", "勉強する", "vs")
        expect("できる", "する", "vs-i")
        expect("きます", "くる", "vk")
        expect("こない", "くる", "vk")
        expect("来ました", "来る", "vk")
        expect("来て", "来る", "vk")
        // 行く : passé en った tout en finissant par く.
        expect("行った", "行く", "v5k-s")
        expect("行って", "行く", "v5k-s")
    }

    // MARK: Registre familier, honorifique et littéraire

    /// Les contractions ne sont pas un ornement : dans un tweet ou une bulle de
    /// manga elles sont la forme NORMALE. Mesuré avant ces règles, 飲んじゃった
    /// laissait 飲ん sans entrée, 買っとく laissait 買っ et 行かなきゃ laissait
    /// 行か — c'est-à-dire « définition non disponible » sur le verbe principal
    /// de la phrase.
    @Test("Les contractions familières reviennent au verbe")
    func casualContractions() {
        expect("忘れちゃった", "忘れる", "v1", "ちゃう = てしまう")
        expect("飲んじゃった", "飲む", "v5m", "じゃう = でしまう")
        expect("食べちゃいました", "食べる", "v1")
        expect("買っとく", "買う", "v5u", "とく = ておく")
        expect("やっといて", "やる", "v5r", "とく à la forme en te")
        expect("読んどく", "読む", "v5m", "どく = でおく")
        expect("行かなきゃ", "行く", "v5k-s", "なきゃ = なければ")
        expect("食べなくちゃ", "食べる", "v1", "なくちゃ = なくては")
        expect("行かねば", "行く", "v5k-s", "littéraire, courant dans les titres")
    }

    /// Les cinq verbes en -aru prennent い là où un v5r prendrait り. Sans eux,
    /// いらっしゃいました se cassait en いらっしゃい + ました, et ました seul
    /// ressortait en 真下 (« juste en dessous ») : un nom faux proposé à
    /// l'apprentissage dans toute phrase polie au passé.
    @Test("Les honorifiques en -aru et ござる")
    func honorifics() {
        expect("いらっしゃいます", "いらっしゃる", "v5aru")
        expect("いらっしゃいました", "いらっしゃる", "v5aru")
        expect("おっしゃいました", "おっしゃる", "v5aru")
        expect("くださいました", "くださる", "v5aru")
        expect("なさいました", "なさる", "v5aru")
        expect("ございます", "ござる", "v5r")
        expect("でした", "です", "cop", "copule polie au passé")
    }

    /// ある est `v5r-i`, comme 行く est `v5k-s` : un irrégulier que la rangée
    /// doit accepter explicitement. Mesuré avant : 学生ではありません rendait
    /// あり → 蟻 (« fourmi »).
    @Test("ある est un v5r irrégulier, pas un inconnu")
    func aruIsIrregular() {
        expect("ありません", "ある", "v5r-i")
        expect("あります", "ある", "v5r-i")
        expect("ありました", "ある", "v5r-i")
    }

    /// Ce qui s'accroche au radical en い se ramène à ます, exactement comme
    /// たい. Chacun de ces cas rendait auparavant un NOM homographe du radical.
    @Test("Ce qui s'accroche au radical en い")
    func stemAuxiliaries() {
        expect("聴きながら", "聴く", "v5k", "sinon le nom 聴き, « l'ouïe »")
        expect("寝なさい", "寝る", "v1", "sinon le nom 寝, « le sommeil »")
        expect("降りそう", "降る", "v5r", "sinon le nom 降り, « la chute de pluie »")
        expect("飲みすぎた", "飲む", "v5m")
        expect("難しすぎる", "難しい", "adj-i", "sinon 難し, adjectif classique en -く")
    }

    /// Les auxiliaires d'aspect doivent pouvoir s'enchaîner : ils se conjuguent
    /// eux-mêmes. Sans `posOut`, 書いておいて laissait おいて → 追手
    /// (« poursuivant ») et 行ってきます laissait きます → 着る (« s'habiller »).
    @Test("Les auxiliaires d'aspect se conjuguent aussi")
    func chainedAuxiliaries() {
        expect("書いておいて", "書く", "v5k")
        expect("休んでおきます", "休む", "v5m")
        expect("行ってきます", "行く", "v5k-s")
        expect("食べてみました", "食べる", "v1")
        expect("読んでみた", "読む", "v5m", "la colonne で avait perdu でみる")
        expect("言わないでおこう", "言う", "v5u", "ないで est une forme en te")
        expect("待たされました", "待つ", "v5t", "causatif-passif contracté")
        expect("飲まされた", "飲む", "v5m")
    }

    // MARK: Adjectifs

    @Test("Les adjectifs en -い")
    func adjectives() {
        expect("高かった", "高い", "adj-i")
        expect("高くない", "高い", "adj-i")
        expect("高くなかった", "高い", "adj-i")
        expect("高くて", "高い", "adj-i")
        expect("高く", "高い", "adj-i")
        expect("面白かった", "面白い", "adj-i")
        expect("よかった", "いい", "adj-ix")
        expect("よくない", "いい", "adj-ix")
    }

    // MARK: Garde-fous

    @Test("La forme de surface est toujours rendue, sans contrainte")
    func surfaceIsAlwaysReturned() {
        let results = JapaneseDeinflector.deinflect("犬")
        #expect(results.first?.term == "犬")
        #expect(results.first?.requiredPOS.isEmpty == true)
    }

    @Test("Une chaîne vide ne produit rien, sans planter")
    func emptyIsSafe() {
        #expect(JapaneseDeinflector.deinflect("").isEmpty)
    }

    @Test("La recherche reste bornée")
    func searchStaysBounded() {
        // Une forme longue et très fléchie : le pire cas réaliste.
        let results = JapaneseDeinflector.deinflect("食べさせられたくなかった")
        #expect(results.count < 4000, "explosion combinatoire : \(results.count) candidats")
        #expect(results.contains { $0.term == "食べる" }, "le verbe doit rester atteignable")
    }

    @Test("Aucune règle ne produit une forme vide")
    func noRuleProducesEmpty() {
        for surface in ["ます", "た", "て", "ない", "い", "る", "く", "し"] {
            #expect(JapaneseDeinflector.deinflect(surface).allSatisfy { !$0.term.isEmpty })
        }
    }
}
