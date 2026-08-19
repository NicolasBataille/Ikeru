import Foundation

// MARK: - Deinflection

/// One way a surface form could have been derived from a dictionary form.
///
/// `requiredPOS` is the constraint the candidate must satisfy in the
/// dictionary: 降っ deinflects to 降る **only if** 降る is a `v5r`. Without that
/// check the same suffix table happily produces 経つ from 経った and 経る from
/// 経った, and the lookup would show whichever it met first.
public struct Deinflection: Sendable, Equatable, Hashable {

    /// The candidate dictionary form.
    public let term: String

    /// Parts of speech the dictionary entry must carry. Empty for the surface
    /// form itself, which is unconstrained.
    public let requiredPOS: Set<String>

    /// The rules applied, outermost first — `["polite", "past"]`. Kept for
    /// tests and for explaining a match in the UI; never used for matching.
    public let rules: [String]

    public init(term: String, requiredPOS: Set<String> = [], rules: [String] = []) {
        self.term = term
        self.requiredPOS = requiredPOS
        self.rules = rules
    }
}

// MARK: - JapaneseDeinflector

/// Turns an inflected Japanese surface form into the dictionary forms it could
/// come from.
///
/// ## Why this had to be written rather than called
///
/// Apple gives segmentation but **not morphology**. Measured on this project
/// (2026-08-19, macOS 26):
///
/// ```
/// NLTagger.availableTagSchemes(for: .word, language: .japanese)
/// → ["Language", "Script", "TokenType"]
/// ```
///
/// No `.lemma`, no `.lexicalClass`. Verified on isolated inflected verbs:
/// 行きました tokenises to 行き / まし / た with a `nil` lemma on all three,
/// 降っている to 降っ / て / いる, likewise `nil`. So every token arrives
/// inflected, and nothing in the OS says whether a token is a verb or a
/// particle. Both jobs land here and in the dictionary's part-of-speech tags.
///
/// The rule table is **hand-authored from grammar** rather than ported: the
/// widely-copied deinflection tables descend from a copyleft lineage, and the
/// project's rule for borrowed work — set with tegaki — is to adapt, not lift.
///
/// ## How it searches
///
/// Breadth-first over the rule table, each rule rewriting one suffix. A rule
/// applies when the candidate ends with `suffixIn` **and** the candidate is
/// still unconstrained (it is the raw surface form) or its constraint
/// intersects the rule's `posOut`. That second clause is what keeps the search
/// honest: it is why 食べました → 食べます → 食べる is reachable while
/// 食べました → 食べま → … is not.
///
/// The surface form itself is always returned first and unconstrained, because
/// most words in a sentence are not inflected at all.
public enum JapaneseDeinflector {

    /// How many rules may chain. 食べさせられたくなかった is four, and is
    /// already a sentence a learner would not meet before N2; six leaves room
    /// without letting the search fan out.
    public static let maxDepth = 8

    /// Every dictionary form `term` could inflect from, surface form included.
    ///
    /// Results are deduplicated on (term, requiredPOS): two different rule
    /// paths reaching the same conclusion is common — って → う and って → つ
    /// are distinct, but ました → ます → る and たい → ます → る both end at
    /// the same ichidan verb.
    public static func deinflect(_ term: String) -> [Deinflection] {
        guard !term.isEmpty else { return [] }

        var results: [Deinflection] = [Deinflection(term: term)]
        var seen: Set<Deinflection> = [results[0]]
        var frontier: [Deinflection] = results

        for _ in 0..<maxDepth {
            var next: [Deinflection] = []
            for candidate in frontier {
                for rule in DeinflectionRules.all {
                    guard candidate.term.count > rule.suffixIn.count || !rule.suffixOut.isEmpty,
                          candidate.term.hasSuffix(rule.suffixIn) else { continue }
                    // Unconstrained = the raw surface form, which any rule may
                    // attack. Once constrained, only a rule that produces that
                    // shape may continue the chain.
                    guard candidate.requiredPOS.isEmpty
                            || !candidate.requiredPOS.isDisjoint(with: rule.posOut) else { continue }

                    let stem = String(candidate.term.dropLast(rule.suffixIn.count))
                    let rewritten = stem + rule.suffixOut
                    // ⚠️ Ne PAS exiger qu'il reste quelque chose du mot
                    // d'origine. Une première version rejetait les réécritures
                    // à radical vide « pour couper le bruit » et faisait
                    // disparaître tous les irréguliers d'un coup : dans します,
                    // 来ました, できる, よかった, le mot ENTIER est la
                    // flexion. Le bruit est filtré par le dictionnaire, qui
                    // exige `posIn` — pas ici.
                    guard !rewritten.isEmpty else { continue }

                    let produced = Deinflection(
                        term: rewritten,
                        requiredPOS: rule.posIn,
                        rules: candidate.rules + [rule.name]
                    )
                    guard seen.insert(produced).inserted else { continue }
                    results.append(produced)
                    next.append(produced)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return results
    }
}
