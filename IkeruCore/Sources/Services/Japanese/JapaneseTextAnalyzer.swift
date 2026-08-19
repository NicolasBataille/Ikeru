import Foundation
import NaturalLanguage

// MARK: - AnalyzedToken

/// One piece of an analysed text, in source order.
///
/// The pieces reassemble into the original string exactly: `surface` covers
/// words, and everything between them — punctuation, spaces, line breaks —
/// comes back as a piece with `isWord == false`. A reading view has to redraw
/// exactly what the learner pasted; dropping the 、 because the tokeniser did
/// would silently rewrite their text.
public struct AnalyzedToken: Sendable, Equatable, Identifiable {

    /// Position in the token list. Stable for the life of one analysis, which
    /// is what a `ForEach` needs.
    public let id: Int

    /// The characters exactly as they appear in the source.
    public let surface: String

    /// A word the tokeniser found, as opposed to what sits between words.
    public let isWord: Bool

    /// The dictionary form the surface was walked back to, when one was found.
    /// `nil` means the lookup failed — said out loud in the UI, never hidden.
    public let dictionaryForm: String?

    /// The dictionary entry chosen for this token.
    public let entry: DictionaryEntry?

    /// The other entries sharing the same spelling, best-ranked first.
    ///
    /// A spelling is often several words — 生 is eleven, 降る is two with
    /// different readings and unrelated meanings. Choosing one and hiding the
    /// rest would be guessing quietly; the tap sheet shows the chosen entry and
    /// says the others exist.
    public let alternatives: [DictionaryEntry]

    public init(id: Int, surface: String, isWord: Bool,
                dictionaryForm: String? = nil, entry: DictionaryEntry? = nil,
                alternatives: [DictionaryEntry] = []) {
        self.id = id
        self.surface = surface
        self.isWord = isWord
        self.dictionaryForm = dictionaryForm
        self.entry = entry
        self.alternatives = alternatives
    }

    /// A word a learner could be asked to learn: found in the dictionary, and
    /// not grammatical glue.
    public var isLearnable: Bool {
        entry?.isContentWord ?? false
    }
}

// MARK: - AnalyzedText

/// A text after segmentation, deinflection and lookup.
public struct AnalyzedText: Sendable, Equatable {

    /// The text exactly as it came in.
    public let source: String

    /// Every piece, in order. Concatenating `surface` rebuilds `source`.
    public let tokens: [AnalyzedToken]

    public init(source: String, tokens: [AnalyzedToken]) {
        self.source = source
        self.tokens = tokens
    }

    /// The learnable words, deduplicated on dictionary form, in first-appearance
    /// order.
    public var learnableWords: [AnalyzedToken] {
        var seen: Set<String> = []
        return tokens.filter { token in
            guard token.isLearnable, let form = token.dictionaryForm else { return false }
            return seen.insert(form).inserted
        }
    }

    /// Learnable words absent from `known`.
    public func unknownWords(known: Set<String>) -> [AnalyzedToken] {
        learnableWords.filter { !known.contains($0.dictionaryForm ?? "") }
    }

    /// The share of **content words** already known, 0…1 — `nil` when the text
    /// has no content word to measure.
    ///
    /// The denominator is content words on purpose. Computed over raw tokens it
    /// would measure grammar: on a realistic sample the raw figure was 18 %,
    /// and most of the gap was て, で, た, ます — glue nobody « knows » as
    /// vocabulary. A mirror that tells a learner they do not know て is not a
    /// mirror, it is a reproach.
    public func coverage(known: Set<String>) -> Double? {
        let learnable = tokens.filter(\.isLearnable)
        guard !learnable.isEmpty else { return nil }
        let hits = learnable.filter { known.contains($0.dictionaryForm ?? "") }.count
        return Double(hits) / Double(learnable.count)
    }
}

// MARK: - MatchScore

/// Lexicographic score deciding which reading of a token the learner sees.
///
/// A struct rather than a tuple because Swift stops synthesising `<` past six
/// elements, and this ranking needs seven — each rung put there by a wrong
/// answer on real text. Best first:
///
/// 1. **する after a verbal noun** — オープンした is する, not 下 « en dessous ».
/// 2. **spelling rank** — 降る is ふる, not a second spelling of くだる, and は
///    is the particle, not the first reading of 葉.
/// 3. **fewest rules** — a form that is already a word beats one reached by
///    inflecting it; without this rung で came back as 出る.
/// 4. **on the app's programme** — 行く over 行う, which JMdict's own
///    priorities cannot separate.
/// 5. **flagged common**, 6. **newspaper frequency**, 7. **identifier**, so the
///    result never depends on row order.
struct MatchScore: Comparable {
    let components: [Int]
    static func < (lhs: MatchScore, rhs: MatchScore) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right {
            return left < right
        }
        return lhs.components.count < rhs.components.count
    }
}

// MARK: - JapaneseTextAnalyzer

/// Segments Japanese text, walks each word back to its dictionary form, and
/// looks it up.
///
/// ## Longest match, not token by token
///
/// Apple's tokeniser splits morphologically, which is right for boundaries and
/// wrong for lookup: 思い / ます and 混ん / で are two tokens each and one word
/// each. So the analyser slides a window over **adjacent tokens joined
/// together**, longest first, and takes the first join the dictionary
/// recognises. That one decision fixes over-splitting and inflection at the
/// same time — 降っ / て / い / ます joins to 降っています, deinflects to 降る,
/// and matches.
///
/// Joins never cross a non-word piece. 「今日、雨」 must not become 今日雨: the
/// comma is a boundary in the text, so it is a boundary here.
///
/// ## One query per text, not one per candidate
///
/// Every window position produces up to `maxJoin` joins, and every join a few
/// dozen deinflections. A paragraph reaches several thousand candidate
/// spellings. They are collected first and resolved in a single batched query;
/// one at a time is the difference between instant and visibly slow, and the
/// feature promises « moins d'une minute » end to end.
public struct JapaneseTextAnalyzer: Sendable {

    /// How many adjacent word pieces may be joined. 食べ / させ / られ / たく /
    /// なかった is five, and is the longest chain the rule table can undo.
    public static let maxJoin = 5

    private let dictionary: DictionaryRepository

    public init(dictionary: DictionaryRepository) {
        self.dictionary = dictionary
    }

    public func analyze(_ text: String) async -> AnalyzedText {
        let pieces = Self.segment(text)
        let wordIndices = pieces.indices.filter { pieces[$0].isWord }

        // Pass 1 — every spelling worth asking the dictionary about, and the
        // joins that produced it.
        var options: [Int: [(length: Int, deinflections: [Deinflection])]] = [:]
        var candidates: Set<String> = []
        for (position, start) in wordIndices.enumerated() {
            // Contiguity: extend only while the next word piece is literally
            // the next piece, so a join never swallows punctuation.
            var reach = 0
            while reach < Self.maxJoin,
                  position + reach < wordIndices.count,
                  wordIndices[position + reach] == start + reach {
                reach += 1
            }
            var list: [(Int, [Deinflection])] = []
            for length in stride(from: reach, through: 1, by: -1) {
                let joined = pieces[start..<(start + length)].map(\.surface).joined()
                let deinflections = JapaneseDeinflector.deinflect(joined)
                candidates.formUnion(deinflections.map(\.term))
                list.append((length, deinflections))
            }
            options[start] = list
        }

        let found = await dictionary.entries(forForms: candidates)

        // Pass 2 — left to right, longest join that resolved wins.
        var tokens: [AnalyzedToken] = []
        var lastEntry: DictionaryEntry?
        var index = 0
        while index < pieces.count {
            if pieces[index].isWord, let list = options[index],
               let (length, hit) = Self.firstResolving(list, in: found,
                                                      after: lastEntry) {
                let surface = pieces[index..<(index + length)].map(\.surface).joined()
                let others = (found[hit.form] ?? []).filter { $0.id != hit.entry.id }
                tokens.append(AnalyzedToken(id: tokens.count, surface: surface, isWord: true,
                                            dictionaryForm: hit.form, entry: hit.entry,
                                            alternatives: others))
                lastEntry = hit.entry
                index += length
                continue
            }
            if pieces[index].isWord { lastEntry = nil }
            tokens.append(AnalyzedToken(id: tokens.count, surface: pieces[index].surface,
                                        isWord: pieces[index].isWord))
            index += 1
        }
        return AnalyzedText(source: text, tokens: tokens)
    }

    /// The first join in `list` (longest first) that the dictionary resolved.
    ///
    /// A join of several tokens refuses `exp` entries. JMdict carries 雨が降る,
    /// 見に行く and お願いします as single entries, and a greedy longest match
    /// swallowed them whole — 雨が降っていて came back as one idiom, hiding 雨
    /// and 降る, the two words a learner actually reuses. An expression that IS
    /// a single token still resolves; only the swallowing is refused.
    static func firstResolving(
        _ list: [(length: Int, deinflections: [Deinflection])],
        in found: [String: [DictionaryEntry]],
        after previous: DictionaryEntry? = nil
    ) -> (Int, (form: String, entry: DictionaryEntry))? {
        // Un nom en -する juste avant change la lecture de した / して / します :
        // dans オープンした, した est する, pas 下 « en dessous ». C'est le seul
        // endroit où l'analyseur regarde le mot précédent, et il le fait parce
        // que la forme est autrement indécidable.
        let followsVerbalNoun = previous?.partsOfSpeech.contains("vs") ?? false
        for (length, deinflections) in list {
            if let hit = bestMatch(deinflections, in: found, allowExpressions: length == 1,
                                   preferSuru: followsVerbalNoun) {
                return (length, hit)
            }
        }
        return nil
    }

    /// The best entry among a set of deinflections, respecting each one's
    /// part-of-speech constraint.
    ///
    /// The constraint is what stops 降っ from resolving to 降る *and* 振る *and*
    /// 経つ indiscriminately: a deinflection claiming `v5r` only accepts an
    /// entry the dictionary calls `v5r`.
    ///
    /// ⚠️ **Every candidate is scored; the surface form does not win by
    /// default.** An earlier version returned the first deinflection that
    /// resolved, and since the surface form is always first, 降って came back
    /// as 下って — a rare `conj` meaning « humbly » — instead of the て-form of
    /// 降る. Being spelled exactly as written is not evidence: JMdict has an
    /// entry for a great many inflected-looking strings.
    ///
    /// The ranking is entry quality first — is the matched spelling the
    /// entry's principal one, is it flagged common, how frequent is it — and
    /// only then the number of rules applied, which breaks ties in favour of
    /// the simpler explanation.
    static func bestMatch(
        _ deinflections: [Deinflection],
        in found: [String: [DictionaryEntry]],
        allowExpressions: Bool = true,
        preferSuru: Bool = false
    ) -> (form: String, entry: DictionaryEntry)? {
        var best: (form: String, entry: DictionaryEntry)?
        var bestScore: MatchScore?

        for deinflection in deinflections {
            guard let entries = found[deinflection.term] else { continue }
            var eligible = entries
            if !deinflection.requiredPOS.isEmpty {
                eligible = eligible.filter {
                    !Set($0.partsOfSpeech).isDisjoint(with: deinflection.requiredPOS)
                }
            }
            if !allowExpressions {
                eligible = eligible.filter(\.canAbsorbNeighbours)
            }
            for entry in eligible {
                let base = DictionaryEntry.rank(entry)
                // Le nombre de règles passe AVANT le prior d'apprenant. Une
                // forme qui est déjà un mot du dictionnaire gagne contre une
                // qu'il faut fléchir pour l'atteindre : sans cette marche, で
                // ressortait en 出る (« sortir ») parce que 出る est au
                // programme N5 et pas la particule で.
                let score = MatchScore(components: [
                    preferSuru && deinflection.term == "する" ? 0 : 1,
                    base.0,
                    deinflection.rules.count,
                    base.1, base.2, base.3, base.4,
                ])
                if bestScore == nil || score < bestScore! {
                    bestScore = score
                    best = (deinflection.term, entry)
                }
            }
        }
        return best
    }

    // MARK: - Segmentation

    /// Splits into words and the text between them, preserving everything.
    static func segment(_ text: String) -> [(surface: String, isWord: Bool)] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.japanese)
        tokenizer.string = text

        var pieces: [(String, Bool)] = []
        var cursor = text.startIndex
        for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            if range.lowerBound > cursor {
                pieces.append((String(text[cursor..<range.lowerBound]), false))
            }
            pieces.append((String(text[range]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            pieces.append((String(text[cursor...]), false))
        }
        return pieces
    }
}
