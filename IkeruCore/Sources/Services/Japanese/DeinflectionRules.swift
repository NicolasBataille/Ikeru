import Foundation

// MARK: - DeinflectionRule

/// One suffix rewrite: « a form ending in `suffixIn` may come from a word
/// ending in `suffixOut`, provided that word is a `posIn` ».
public struct DeinflectionRule: Sendable {

    /// The ending the inflected form carries.
    public let suffixIn: String

    /// What replaces it to reach the less-inflected form.
    public let suffixOut: String

    /// Parts of speech the RESULT must have. `v5u` on います → う means 買います
    /// only yields 買う if the dictionary agrees 買う is a godan-u verb.
    public let posIn: Set<String>

    /// Shapes this rule may be applied to. Empty means « terminal »: it applies
    /// to a raw surface form only. Pseudo-tags (`*masu`, `*te`, `*ta`, `*nai`,
    /// `*tai`) name intermediate forms that are not dictionary entries — the
    /// ます of 食べます is a shape, not a word.
    public let posOut: Set<String>

    /// Human-readable trace, e.g. `"poli"`. Never used for matching.
    public let name: String

    public init(_ suffixIn: String, _ suffixOut: String,
                _ posIn: Set<String>, _ posOut: Set<String> = [], _ name: String) {
        self.suffixIn = suffixIn
        self.suffixOut = suffixOut
        self.posIn = posIn
        self.posOut = posOut
        self.name = name
    }
}

// MARK: - DeinflectionRules

/// The hand-authored rule table.
///
/// Written from the grammar rather than ported: the widely-copied deinflection
/// tables descend from a copyleft lineage, and this project's rule for borrowed
/// work — set with tegaki — is to adapt, not lift.
///
/// The godan rules are **generated from their conjugation row** instead of
/// being typed out. Nine verb classes times ten inflections is ninety rules
/// where a single transcription slip (う → わ but ぶ → ま) would be invisible in
/// review and would silently teach the wrong stem. Expressed as a row, the
/// error has nowhere to hide, and `DeinflectionRulesTests` walks the table back
/// against known conjugations.
public enum DeinflectionRules {

    // MARK: Godan rows

    /// One godan class: its dictionary ending, its part of speech, and the four
    /// stem vowels plus the two euphonic (音便) past/て forms it takes.
    private struct GodanRow {
        let dictionary: String   // う
        let pos: String          // v5u
        let a: String            // わ — negative stem (irregular for う: わ, not あ)
        let i: String            // い — polite stem
        let e: String            // え — conditional / potential stem
        let o: String            // お — volitional stem
        let past: String         // った
        let te: String           // って
    }

    private static let godan: [GodanRow] = [
        // ⚠️ Row う takes わ, not あ: 買う → 買わない. This is the single most
        // copied-wrong cell in any hand-written conjugation table.
        GodanRow(dictionary: "う", pos: "v5u", a: "わ", i: "い", e: "え", o: "お", past: "った", te: "って"),
        GodanRow(dictionary: "く", pos: "v5k", a: "か", i: "き", e: "け", o: "こ", past: "いた", te: "いて"),
        GodanRow(dictionary: "ぐ", pos: "v5g", a: "が", i: "ぎ", e: "げ", o: "ご", past: "いだ", te: "いで"),
        GodanRow(dictionary: "す", pos: "v5s", a: "さ", i: "し", e: "せ", o: "そ", past: "した", te: "して"),
        GodanRow(dictionary: "つ", pos: "v5t", a: "た", i: "ち", e: "て", o: "と", past: "った", te: "って"),
        GodanRow(dictionary: "ぬ", pos: "v5n", a: "な", i: "に", e: "ね", o: "の", past: "んだ", te: "んで"),
        GodanRow(dictionary: "ぶ", pos: "v5b", a: "ば", i: "び", e: "べ", o: "ぼ", past: "んだ", te: "んで"),
        GodanRow(dictionary: "む", pos: "v5m", a: "ま", i: "み", e: "め", o: "も", past: "んだ", te: "んで"),
        GodanRow(dictionary: "る", pos: "v5r", a: "ら", i: "り", e: "れ", o: "ろ", past: "った", te: "って"),
    ]

    private static func godanRules() -> [DeinflectionRule] {
        var rules: [DeinflectionRule] = []
        for row in godan {
            // 行く est marqué `v5k-s` dans JMdict, pas `v5k`. La rangée en く
            // doit donc accepter les deux, sinon 行きました, 行かない, 行けば et
            // 行こう ne trouvent rien — mesuré : 映画を見に行きました laissait
            // 行き non résolu, et l'apprenant voyait un nom (« un aller »).
            // Même motif pour la rangée en る : ある est `v5r-i` dans JMdict
            // (irrégulier au négatif), et les quatre honorifiques いらっしゃる,
            // おっしゃる, くださる, なさる sont `v5aru`. Sans eux, ありません
            // laissait あり non résolu et l'apprenant lisait « 蟻 » (fourmi).
            // Les `v5aru` se conjuguent comme un v5r partout SAUF au radical
            // en い (いらっしゃいます, jamais ×いらっしゃります) — traité juste
            // après.
            let pos: Set<String>
            switch row.pos {
            case "v5k": pos = ["v5k", "v5k-s"]
            case "v5r": pos = ["v5r", "v5r-i", "v5aru"]
            default:    pos = [row.pos]
            }
            let out = row.dictionary
            rules += [
                DeinflectionRule(row.i + "ます", out, pos, ["*masu"], "poli"),
                DeinflectionRule(row.past, out, pos, ["*ta"], "passé"),
                DeinflectionRule(row.te, out, pos, ["*te"], "forme en te"),
                DeinflectionRule(row.a + "ない", out, pos, ["*nai"], "négatif"),
                DeinflectionRule(row.a + "ず", out, pos, [], "négatif ず"),
                DeinflectionRule(row.e + "ば", out, pos, [], "conditionnel ば"),
                // Potentiel, passif et causatif produisent des verbes en -る
                // qui se conjuguent comme des ichidan : d'où `v1` en `posOut`,
                // qui autorise 買えます → 買える → 買う.
                DeinflectionRule(row.e + "る", out, pos, ["v1"], "potentiel"),
                DeinflectionRule(row.a + "れる", out, pos, ["v1"], "passif"),
                DeinflectionRule(row.a + "せる", out, pos, ["v1"], "causatif"),
                // Causatif-passif contracté : 待たされる ← 待たせられる ← 待つ.
                // Sans lui, 一時間も待たされました rendait 待たす — un vrai mot,
                // mais pas celui que l'apprenant réutilise.
                DeinflectionRule(row.a + "される", out, pos, ["v1"], "causatif-passif"),
                DeinflectionRule(row.o + "う", out, pos, [], "volitif"),
                DeinflectionRule(row.i, out, pos, [], "radical en i"),
            ]
        }
        // 行く est le seul verbe dont le passé suit la rangée つ/る tout en
        // finissant par く. JMdict le marque `v5k-s`, ce qui suffit à le
        // distinguer sans le nommer ici.
        rules += [
            DeinflectionRule("った", "く", ["v5k-s"], ["*ta"], "passé irrégulier"),
            DeinflectionRule("って", "く", ["v5k-s"], ["*te"], "forme en te irrégulière"),
            // Les cinq verbes en -aru : radical en い là où un v5r prendrait り.
            // Mesuré avant : 先生がいらっしゃいました rendait ました → 真下
            // (« juste en dessous »), un nom parfaitement inutile proposé à
            // l'apprentissage, parce que le radical honorifique ne se
            // rattachait à rien.
            DeinflectionRule("います", "る", ["v5aru"], ["*masu"], "poli honorifique"),
            // ⚠️ Pas de règle « い → る » nue pour le radical honorifique :
            // mesuré, elle fait passer l'analyse d'un paragraphe de 0,9 s à
            // 2,8 s (elle s'applique à TOUT candidat finissant en い, donc à
            // tout adjectif et tout négatif). いらっしゃい seul reste rendu par
            // son entrée propre ; c'est ました qui posait problème, et il est
            // recollé par la règle います ci-dessus.
            // ござる est `v5r` et non `v5aru`, mais prend le même radical.
            DeinflectionRule("ございます", "ござる", ["v5r"], ["*masu"], "poli honorifique"),
        ]
        return rules
    }

    // MARK: Ichidan, irregulars, adjectives, auxiliaries

    private static let ichidan: [DeinflectionRule] = [
        DeinflectionRule("ます", "る", ["v1"], ["*masu"], "poli"),
        DeinflectionRule("た", "る", ["v1"], ["*ta"], "passé"),
        DeinflectionRule("て", "る", ["v1"], ["*te"], "forme en te"),
        DeinflectionRule("ない", "る", ["v1"], ["*nai"], "négatif"),
        DeinflectionRule("ず", "る", ["v1"], [], "négatif ず"),
        DeinflectionRule("れば", "る", ["v1"], [], "conditionnel ば"),
        DeinflectionRule("られる", "る", ["v1"], ["v1"], "potentiel / passif"),
        DeinflectionRule("させる", "る", ["v1"], ["v1"], "causatif"),
        DeinflectionRule("よう", "る", ["v1"], [], "volitif"),
        DeinflectionRule("ろ", "る", ["v1"], [], "impératif"),
        DeinflectionRule("", "る", ["v1"], [], "radical"),
    ]

    private static let irregular: [DeinflectionRule] = [
        // する — `vs-i` est する lui-même, `vs` un nom en -する (勉強する).
        DeinflectionRule("します", "する", ["vs-i", "vs"], ["*masu"], "poli"),
        DeinflectionRule("した", "する", ["vs-i", "vs"], ["*ta"], "passé"),
        DeinflectionRule("して", "する", ["vs-i", "vs"], ["*te"], "forme en te"),
        DeinflectionRule("しない", "する", ["vs-i", "vs"], ["*nai"], "négatif"),
        DeinflectionRule("すれば", "する", ["vs-i", "vs"], [], "conditionnel ば"),
        DeinflectionRule("しよう", "する", ["vs-i", "vs"], [], "volitif"),
        DeinflectionRule("される", "する", ["vs-i", "vs"], ["v1"], "passif"),
        DeinflectionRule("させる", "する", ["vs-i", "vs"], ["v1"], "causatif"),
        DeinflectionRule("できる", "する", ["vs-i", "vs"], ["v1"], "potentiel"),
        DeinflectionRule("しろ", "する", ["vs-i", "vs"], [], "impératif"),
        DeinflectionRule("し", "する", ["vs-i", "vs"], [], "radical"),
        // 来る, en kana et en kanji — le kanji ne change pas de lecture ici,
        // donc les deux graphies doivent être couvertes.
        DeinflectionRule("きます", "くる", ["vk"], ["*masu"], "poli"),
        DeinflectionRule("きた", "くる", ["vk"], ["*ta"], "passé"),
        DeinflectionRule("きて", "くる", ["vk"], ["*te"], "forme en te"),
        DeinflectionRule("こない", "くる", ["vk"], ["*nai"], "négatif"),
        DeinflectionRule("くれば", "くる", ["vk"], [], "conditionnel ば"),
        DeinflectionRule("こよう", "くる", ["vk"], [], "volitif"),
        DeinflectionRule("こられる", "くる", ["vk"], ["v1"], "potentiel / passif"),
        DeinflectionRule("こさせる", "くる", ["vk"], ["v1"], "causatif"),
        DeinflectionRule("来ます", "来る", ["vk"], ["*masu"], "poli"),
        DeinflectionRule("来た", "来る", ["vk"], ["*ta"], "passé"),
        DeinflectionRule("来て", "来る", ["vk"], ["*te"], "forme en te"),
        DeinflectionRule("来ない", "来る", ["vk"], ["*nai"], "négatif"),
        DeinflectionRule("来れば", "来る", ["vk"], [], "conditionnel ば"),
        DeinflectionRule("来られる", "来る", ["vk"], ["v1"], "potentiel / passif"),
    ]

    private static let adjectives: [DeinflectionRule] = [
        DeinflectionRule("かった", "い", ["adj-i"], ["*ta"], "passé"),
        DeinflectionRule("くない", "い", ["adj-i"], ["*nai"], "négatif"),
        DeinflectionRule("くありません", "い", ["adj-i"], [], "négatif poli"),
        DeinflectionRule("くて", "い", ["adj-i"], ["*te"], "forme en te"),
        DeinflectionRule("ければ", "い", ["adj-i"], [], "conditionnel ば"),
        DeinflectionRule("く", "い", ["adj-i"], [], "adverbial"),
        DeinflectionRule("さ", "い", ["adj-i"], [], "nominalisation"),
        DeinflectionRule("そう", "い", ["adj-i"], [], "apparence"),
        // いい se conjugue sur よい : 良かった, jamais ×いかった.
        DeinflectionRule("よかった", "いい", ["adj-ix", "adj-i"], ["*ta"], "passé irrégulier"),
        DeinflectionRule("よくない", "いい", ["adj-ix", "adj-i"], ["*nai"], "négatif irrégulier"),
        DeinflectionRule("よくて", "いい", ["adj-ix", "adj-i"], ["*te"], "forme en te irrégulière"),
    ]

    /// Les auxiliaires : ils ne mènent pas au dictionnaire, ils mènent à une
    /// forme intermédiaire que les tables ci-dessus savent finir de défaire.
    private static let auxiliaries: [DeinflectionRule] = [
        DeinflectionRule("ました", "ます", ["*masu"], [], "poli passé"),
        DeinflectionRule("ません", "ます", ["*masu"], [], "poli négatif"),
        DeinflectionRule("ませんでした", "ます", ["*masu"], [], "poli négatif passé"),
        DeinflectionRule("ましょう", "ます", ["*masu"], [], "poli volitif"),
        DeinflectionRule("まして", "ます", ["*masu"], [], "poli en te"),
        DeinflectionRule("ましたら", "ます", ["*masu"], [], "poli conditionnel"),
        // たい s'attache au radical en い, exactement comme ます : réécrire
        // たい en ます fait retomber 買いたい sur 買います, donc sur 買う.
        DeinflectionRule("たい", "ます", ["*masu"], ["*tai"], "désidératif"),
        DeinflectionRule("たかった", "たい", ["*tai"], ["*ta"], "désidératif passé"),
        DeinflectionRule("たくない", "たい", ["*tai"], ["*nai", "adj-i"], "désidératif négatif"),
        DeinflectionRule("たくて", "たい", ["*tai"], ["*te"], "désidératif en te"),
        DeinflectionRule("なかった", "ない", ["*nai", "adj-i"], [], "négatif passé"),
        // ないで et なくて SONT des formes en て : sans `posOut`, la chaîne
        // s'arrêtait net sur 言わないでおこう (おこう ressortait en 御構,
        // « conduite scandaleuse »).
        DeinflectionRule("なくて", "ない", ["*nai", "adj-i"], ["*te"], "négatif en te"),
        DeinflectionRule("なければ", "ない", ["*nai", "adj-i"], [], "négatif conditionnel"),
        DeinflectionRule("ないで", "ない", ["*nai", "adj-i"], ["*te"], "négatif suspensif"),
        DeinflectionRule("なく", "ない", ["*nai", "adj-i"], [], "négatif adverbial"),
        DeinflectionRule("たら", "た", ["*ta"], [], "conditionnel たら"),
        DeinflectionRule("たり", "た", ["*ta"], [], "énumératif たり"),
        DeinflectionRule("だら", "だ", ["*ta"], [], "conditionnel たら"),
        DeinflectionRule("だり", "だ", ["*ta"], [], "énumératif たり"),
        // Aspect : la chaîne ている/でいる et ses contractions.
        DeinflectionRule("ている", "て", ["*te"], ["v1"], "progressif"),
        DeinflectionRule("ています", "て", ["*te"], ["*masu"], "progressif poli"),
        DeinflectionRule("ていた", "て", ["*te"], ["*ta"], "progressif passé"),
        DeinflectionRule("てる", "て", ["*te"], ["v1"], "progressif contracté"),
        DeinflectionRule("てた", "て", ["*te"], ["*ta"], "progressif contracté passé"),
        DeinflectionRule("てしまう", "て", ["*te"], ["v5u"], "accompli"),
        DeinflectionRule("ておく", "て", ["*te"], ["v5k", "v5k-s"], "préparatoire"),
        DeinflectionRule("てみる", "て", ["*te"], ["v1"], "tentative"),
        DeinflectionRule("ていて", "て", ["*te"], [], "progressif en te"),
        DeinflectionRule("てくる", "て", ["*te"], ["vk"], "directionnel"),
        DeinflectionRule("ていく", "て", ["*te"], ["v5k", "v5k-s"], "directionnel"),
        DeinflectionRule("てくれる", "て", ["*te"], ["v1"], "bénéfactif"),
        DeinflectionRule("てもらう", "て", ["*te"], ["v5u"], "bénéfactif"),
        DeinflectionRule("てあげる", "て", ["*te"], ["v1"], "bénéfactif"),
        DeinflectionRule("でいる", "で", ["*te"], ["v1"], "progressif"),
        DeinflectionRule("でいます", "で", ["*te"], ["*masu"], "progressif poli"),
        DeinflectionRule("でいた", "で", ["*te"], ["*ta"], "progressif passé"),
        DeinflectionRule("でる", "で", ["*te"], ["v1"], "progressif contracté"),
        DeinflectionRule("でた", "で", ["*te"], ["*ta"], "progressif contracté passé"),
        DeinflectionRule("でしまう", "で", ["*te"], ["v5u"], "accompli"),
        DeinflectionRule("でおく", "で", ["*te"], ["v5k", "v5k-s"], "préparatoire"),
        // ⚠️ でみる manquait : 読んでみた se cassait en 読んで + みた, et みた
        // ressortait en 見る (« voir ») alors que ce みる est un auxiliaire.
        DeinflectionRule("でみる", "で", ["*te"], ["v1"], "tentative"),
        DeinflectionRule("でいて", "で", ["*te"], [], "progressif en te"),
        DeinflectionRule("でくる", "で", ["*te"], ["vk"], "directionnel"),
        DeinflectionRule("でいく", "で", ["*te"], ["v5k", "v5k-s"], "directionnel"),
        DeinflectionRule("でくれる", "で", ["*te"], ["v1"], "bénéfactif"),
        DeinflectionRule("でもらう", "で", ["*te"], ["v5u"], "bénéfactif"),
        DeinflectionRule("であげる", "で", ["*te"], ["v1"], "bénéfactif"),
        // Contractions familières. Elles sont MAJORITAIRES dans le registre que
        // la feature vise (tweet, bulle de manga, message) et ne menaient nulle
        // part : 飲んじゃった laissait 飲ん sans entrée, 買っとく laissait 買っ,
        // 行かなきゃ laissait 行か. ちゃう = てしまう, とく = ておく, なきゃ =
        // なければ, なくちゃ = なくては.
        DeinflectionRule("ちゃう", "て", ["*te"], ["v5u"], "accompli contracté"),
        DeinflectionRule("じゃう", "で", ["*te"], ["v5u"], "accompli contracté"),
        DeinflectionRule("とく", "て", ["*te"], ["v5k", "v5k-s"], "préparatoire contracté"),
        DeinflectionRule("どく", "で", ["*te"], ["v5k", "v5k-s"], "préparatoire contracté"),
        DeinflectionRule("なきゃ", "ない", ["*nai", "adj-i"], [], "négatif contracté"),
        DeinflectionRule("なくちゃ", "ない", ["*nai", "adj-i"], [], "négatif contracté"),
        DeinflectionRule("なくては", "ない", ["*nai", "adj-i"], [], "négatif conditionnel"),
        // Littéraire, mais courant dans les paroles et les titres.
        DeinflectionRule("ねば", "ない", ["*nai", "adj-i"], [], "négatif conditionnel littéraire"),
        // Ce qui s'accroche au radical en い se ramène à ます, exactement comme
        // たい. Sans ça, 聴きながら donnait le NOM 聴き (« l'ouïe »), 降りそう le
        // nom 降り (« chute de pluie ») et 寝なさい le nom 寝 (« sommeil ») :
        // trois mots de contenu faux proposés à l'apprentissage.
        DeinflectionRule("ながら", "ます", ["*masu"], [], "simultané"),
        DeinflectionRule("なさい", "ます", ["*masu"], [], "impératif poli"),
        DeinflectionRule("そう", "ます", ["*masu"], [], "apparence"),
        // すぎる s'accroche au radical en い des verbes et au radical des
        // adjectifs. 走りすぎる existe dans JMdict, 難しすぎる non — et il
        // ressortait en 難し, un adjectif CLASSIQUE en -く.
        DeinflectionRule("すぎる", "ます", ["*masu"], ["v1"], "excès"),
        DeinflectionRule("すぎる", "い", ["adj-i"], ["v1"], "excès"),
        // La copule polie au passé. でし n'est pas un mot : laissé seul, il
        // ressortait en 弟子 (« disciple »), proposé à l'apprentissage dans
        // toute phrase polie au passé.
        DeinflectionRule("でした", "です", ["cop", "aux-v"], [], "copule passée"),
    ]

    /// The whole table, built once.
    public static let all: [DeinflectionRule] =
        godanRules() + ichidan + irregular + adjectives + auxiliaries

    // MARK: - Index

    /// The table bucketed by the **last character of `suffixIn`**.
    ///
    /// A rule can only fire when the candidate ends with its `suffixIn`, so a
    /// candidate ending in `た` can never match a rule ending in `る`. Bucketing
    /// on that character turns « test all 124 rules » into « test the 3 to 12
    /// that could possibly apply », without changing a single outcome.
    ///
    /// This is not premature optimisation, it closed a measured cliff. The
    /// table grew from 106 to 124 rules when the familiar contractions,
    /// honorifics and aspect chains were added — all legitimate — and a
    /// paragraph went from 53 ms to 737 ms, because the cost is
    /// `depth × frontier × RULES` and every one of those factors had grown.
    /// The choice looked like « correct Japanese or a responsive app ». It was
    /// neither: it was a linear scan in the innermost loop.
    ///
    /// ⚠️ **Chaque seau porte AUSSI les règles sans suffixe**, à leur place
    /// dans `all`. Deux raisons, et la seconde vaut plus que la première.
    ///
    /// 1. Le coût. Concaténer `unanchored` au seau à chaque candidat de la
    ///    frontière alloue un tableau dans la boucle la plus interne. Mesuré
    ///    en release, même machine, même texte : 5 679 caractères passaient de
    ///    92 ms à **37 ms**, et 100 000 caractères de 916 ms à **404 ms**,
    ///    rien qu'en pré-fusionnant.
    /// 2. La preuve. Concaténées, les règles sans suffixe s'appliquaient
    ///    APRÈS toutes celles du seau, là où le balayage linéaire les
    ///    appliquait au milieu de la table. L'ENSEMBLE des déflexions restait
    ///    le même, mais l'ORDRE du tableau changeait — et `bestMatch` garde le
    ///    PREMIER minimum, donc une égalité de score aurait pu basculer.
    ///    Mesuré : 226 formes sur 1 564 ressortaient dans un ordre différent,
    ///    sans qu'aucun verdict ne change — mais c'était vrai par échantillon,
    ///    pas par construction. Fusionnées à leur place, la sortie est
    ///    identique **au tableau près** à celle du balayage linéaire, et la
    ///    question ne se pose plus.
    static let byLastCharacter: [Character: [DeinflectionRule]] = {
        var keys: Set<Character> = []
        for rule in all {
            guard let last = rule.suffixIn.last else { continue }
            keys.insert(last)
        }
        var index: [Character: [DeinflectionRule]] = [:]
        for key in keys {
            index[key] = all.filter { $0.suffixIn.isEmpty || $0.suffixIn.last == key }
        }
        return index
    }()

    /// Rules whose `suffixIn` is empty, so they apply to any candidate.
    ///
    /// Exactly one today — the ichidan stem (食べ → 食べる) — but derived rather
    /// than hardcoded, because a second one would otherwise be silently
    /// dropped by the index above. C'est aussi le repli quand le dernier
    /// caractère du candidat n'ouvre aucun seau — un chiffre, une lettre
    /// latine, un emoji : ces règles-là restent applicables.
    static let unanchored: [DeinflectionRule] = all.filter { $0.suffixIn.isEmpty }
}
