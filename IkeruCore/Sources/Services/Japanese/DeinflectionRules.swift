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
            let pos: Set<String> = row.pos == "v5k" ? ["v5k", "v5k-s"] : [row.pos]
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
        DeinflectionRule("なくて", "ない", ["*nai", "adj-i"], [], "négatif en te"),
        DeinflectionRule("なければ", "ない", ["*nai", "adj-i"], [], "négatif conditionnel"),
        DeinflectionRule("ないで", "ない", ["*nai", "adj-i"], [], "négatif suspensif"),
        DeinflectionRule("なく", "ない", ["*nai", "adj-i"], [], "négatif adverbial"),
        DeinflectionRule("たら", "た", ["*ta"], [], "conditionnel たら"),
        DeinflectionRule("たり", "た", ["*ta"], [], "énumératif たり"),
        DeinflectionRule("だら", "だ", ["*ta"], [], "conditionnel たら"),
        DeinflectionRule("だり", "だ", ["*ta"], [], "énumératif たり"),
        // Aspect : la chaîne ている/でいる et ses contractions.
        DeinflectionRule("ている", "て", ["*te"], [], "progressif"),
        DeinflectionRule("ています", "て", ["*te"], ["*masu"], "progressif poli"),
        DeinflectionRule("ていた", "て", ["*te"], ["*ta"], "progressif passé"),
        DeinflectionRule("てる", "て", ["*te"], [], "progressif contracté"),
        DeinflectionRule("てた", "て", ["*te"], ["*ta"], "progressif contracté passé"),
        DeinflectionRule("てしまう", "て", ["*te"], [], "accompli"),
        DeinflectionRule("ておく", "て", ["*te"], [], "préparatoire"),
        DeinflectionRule("てみる", "て", ["*te"], [], "tentative"),
        DeinflectionRule("ていて", "て", ["*te"], [], "progressif en te"),
        DeinflectionRule("てくる", "て", ["*te"], [], "directionnel"),
        DeinflectionRule("ていく", "て", ["*te"], [], "directionnel"),
        DeinflectionRule("てくれる", "て", ["*te"], [], "bénéfactif"),
        DeinflectionRule("てもらう", "て", ["*te"], [], "bénéfactif"),
        DeinflectionRule("てあげる", "て", ["*te"], [], "bénéfactif"),
        DeinflectionRule("でいる", "で", ["*te"], [], "progressif"),
        DeinflectionRule("でいます", "で", ["*te"], ["*masu"], "progressif poli"),
        DeinflectionRule("でいた", "で", ["*te"], ["*ta"], "progressif passé"),
        DeinflectionRule("でる", "で", ["*te"], [], "progressif contracté"),
        DeinflectionRule("でた", "で", ["*te"], ["*ta"], "progressif contracté passé"),
        DeinflectionRule("でしまう", "で", ["*te"], [], "accompli"),
        DeinflectionRule("でおく", "で", ["*te"], [], "préparatoire"),
        DeinflectionRule("でいて", "で", ["*te"], [], "progressif en te"),
        DeinflectionRule("でくる", "で", ["*te"], [], "directionnel"),
        DeinflectionRule("でいく", "で", ["*te"], [], "directionnel"),
        DeinflectionRule("でくれる", "で", ["*te"], [], "bénéfactif"),
        DeinflectionRule("でもらう", "で", ["*te"], [], "bénéfactif"),
        DeinflectionRule("であげる", "で", ["*te"], [], "bénéfactif"),
    ]

    /// The whole table, built once.
    public static let all: [DeinflectionRule] =
        godanRules() + ichidan + irregular + adjectives + auxiliaries
}
