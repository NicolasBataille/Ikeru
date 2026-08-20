import Foundation
import os
import SQLite3

// MARK: - DictionaryEntry

/// One dictionary entry as the app needs it: a reading, parts of speech, and a
/// gloss in the learner's language when one exists.
public struct DictionaryEntry: Sendable, Equatable, Identifiable, Hashable {

    /// JMdict's `ent_seq`. Stable across releases of the dictionary, which is
    /// what lets a saved card point back at a definition.
    public let id: Int

    /// The primary kana reading — furigana, and what the speech synthesiser
    /// is handed.
    public let reading: String

    /// JMdict part-of-speech tags (`v5r`, `adj-i`, `prt`…). Two jobs: the
    /// deinflector checks them, and the coverage mirror uses them to keep
    /// function words out of its denominator.
    public let partsOfSpeech: [String]

    /// French gloss, `nil` when JMdict has none — which is the common case:
    /// only 7 % of entries carry French, 43 % among the common ones (measured
    /// on the 2026-08-19 file). `nil` is the signal the UI reads to label the
    /// English gloss as English. It must never be papered over.
    public let glossFR: String?

    /// English gloss. Always present — an entry without one is not stored.
    public let glossEN: String

    /// JMdict marks the entry as frequent (`ke_pri`/`re_pri`).
    public let isCommon: Bool

    /// JMdict's frequency band (`nf01`…`nf48`), 99 when the entry carries none.
    /// Lower is more frequent.
    ///
    /// A **weak** signal, ranked late on purpose. The bands come from a
    /// newspaper corpus: 行う is `nf01` and 行く has no band at all, which made
    /// 行って read « effectuer » instead of « aller ». Absence of a band means
    /// « not in that corpus », not « rare ».
    public let frequencyBand: Int

    /// The spelling is part of the app's curated N5 programme.
    ///
    /// A learner-level prior, and the tiebreak that fixes 行く vs 行う where
    /// JMdict's own priorities cannot: both are `ichi1`, only one is a word a
    /// beginner meets. 498 entries carry it.
    public let isCurated: Bool

    /// How central the matched spelling is to this entry: 0 for its principal
    /// written form, 1 for another kanji or its first reading, 2 for any other
    /// reading. Lower wins.
    ///
    /// The single most load-bearing signal in the ranking, and each of its
    /// three levels was added by a wrong answer on real text. As a boolean on
    /// the first kanji alone, この came back as « 九 » and だけ as « 岳 ». With
    /// readings treated like kanji, は, が, から, に, と and も all came back as
    /// NOUNS — 葉, 蛾, 空, 二, 戸, 藻 — because は really is the first reading of
    /// 葉. Depends on the query, hence carried on the result rather than on the
    /// entry itself.
    public let spellingRank: Int

    /// An expression rather than a single word (JMdict `exp`): 雨が降る,
    /// 見に行く, お願いします.
    public var isExpression: Bool { partsOfSpeech.contains("exp") }

    /// May this entry justify gluing several tokens into one word?
    ///
    /// Only a plain content word may. Measured before this guard: 今日 + は
    /// resolved to こんにちは (`int`), 何 + を to なにを (`adv int`) and そこ +
    /// で to そこで (`conj`) — three cases where a greedy join ate a particle
    /// and hid the two ordinary words the learner actually needs. Expressions,
    /// interjections and function words are all still reachable as a single
    /// token; they simply may not swallow their neighbours.
    public var canAbsorbNeighbours: Bool {
        guard isContentWord, !isExpression else { return false }
        // Une entrée qui n'est QU'interjection ne colle pas ses voisins ; une
        // qui l'est accessoirement, si. お願い est `n vs vt int` — un nom
        // parfaitement ordinaire doublé d'une formule — et le filtre brut le
        // recassait en お + 願い. 何を est `adv int`, sans aucun tag solide :
        // refusé, et l'apprenant lit 何 + を.
        guard partsOfSpeech.contains("int") else { return true }
        return partsOfSpeech.contains { tag in
            tag == "n" || tag.hasPrefix("n-") || tag.hasPrefix("v") || tag.hasPrefix("adj")
        }
    }

    public init(id: Int, reading: String, partsOfSpeech: [String],
                glossFR: String?, glossEN: String, isCommon: Bool,
                frequencyBand: Int = 99, isCurated: Bool = false,
                spellingRank: Int = 0) {
        self.id = id
        self.reading = reading
        self.partsOfSpeech = partsOfSpeech
        self.glossFR = glossFR
        self.glossEN = glossEN
        self.isCommon = isCommon
        self.frequencyBand = frequencyBand
        self.isCurated = isCurated
        self.spellingRank = spellingRank
    }

    /// A word a learner can be asked to learn, as opposed to grammatical glue.
    ///
    /// This is what keeps the coverage mirror honest. Counting every token
    /// would measure grammar, not vocabulary: on a realistic sample the raw
    /// figure was 18 %, and most of the gap was て, で, た, ます — things one
    /// does not « know » as words. Excluded tags are function words only;
    /// expressions (`exp`) and counters (`ctr`) stay in, because they are
    /// learnable units.
    public var isContentWord: Bool {
        guard !partsOfSpeech.isEmpty else { return true }
        return !partsOfSpeech.allSatisfy(Self.functionWordTags.contains)
    }

    /// Tags that mark a token as grammar rather than vocabulary.
    public static let functionWordTags: Set<String> = [
        "prt", "aux", "aux-v", "aux-adj", "cop", "cop-da", "conj", "int", "unc",
    ]

    /// Sort key deciding which entry a learner reads first when a spelling is
    /// several words. Lower wins.
    ///
    /// The order is motivated, not arbitrary, and each rung was put there by a
    /// wrong answer on real text:
    ///
    /// 1. **spelling rank** — 降る is ふる « pleuvoir », and only a secondary
    ///    spelling of くだる « descendre » ;
    /// 2. **on the app's programme** — 行く over 行う, which JMdict's own
    ///    priorities cannot separate ;
    /// 3. **flagged common** ;
    /// 4. **newspaper frequency band**, last because it is the weakest and the
    ///    most misleading of the four ;
    /// 5. **identifier**, so the result never depends on row order.
    public static func rank(_ entry: DictionaryEntry) -> (Int, Int, Int, Int, Int) {
        (entry.spellingRank,
         entry.isCurated ? 0 : 1,
         entry.isCommon ? 0 : 1,
         entry.frequencyBand,
         entry.id)
    }
}

// MARK: - DictionaryRepository

/// Read-only reader over `jmdict.sqlite`.
///
/// Mirrors `ContentRepository`: the SQLite3 C API behind an actor, no SwiftData,
/// every query off the main thread. The dictionary is 218 498 entries and
/// 498 413 spellings, so the one thing that matters for responsiveness is
/// **batching** — `entries(forForms:)` answers a whole sentence's worth of
/// candidate forms in one statement instead of one round trip per token. A
/// paragraph generates a few thousand candidate forms after deinflection; as
/// separate queries that is visibly slow, as one `IN (…)` it is not.
public final class DictionaryRepository: Sendable {

    private let actor: DictionaryDatabaseActor

    public init(bundleURL: URL) {
        self.actor = DictionaryDatabaseActor(bundleURL: bundleURL)
    }

    /// Entries for each requested spelling. Absent spellings are simply not in
    /// the result — the caller distinguishes « no entry » from « no French »,
    /// and both are said out loud in the UI rather than smoothed over.
    public func entries(forForms forms: Set<String>) async -> [String: [DictionaryEntry]] {
        await actor.entries(forForms: forms)
    }

    /// Convenience for a single spelling.
    public func entries(for form: String) async -> [DictionaryEntry] {
        await entries(forForms: [form])[form] ?? []
    }

    /// Whether the dictionary opened. Views ask before offering the feature:
    /// a lookup screen that cannot look anything up should say so, not fail
    /// per word.
    public func isAvailable() async -> Bool {
        await actor.isAvailable()
    }
}

// MARK: - DictionaryDatabaseActor

actor DictionaryDatabaseActor {

    private let bundleURL: URL
    nonisolated(unsafe) private var db: OpaquePointer?
    private var didAttemptOpen = false

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }

    nonisolated deinit {
        // Même motif que `ContentDatabaseActor` : à ce point plus personne ne
        // détient le pointeur, sa fermeture est sûre hors isolation.
        if let db { sqlite3_close(db) }
    }

    private func open() {
        guard !didAttemptOpen else { return }
        didAttemptOpen = true
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(bundleURL.path, &handle, flags, nil) == SQLITE_OK else {
            Logger.content.error("Dictionary open failed: \(self.bundleURL.lastPathComponent)")
            if let handle { sqlite3_close(handle) }
            return
        }
        db = handle
    }

    func isAvailable() -> Bool {
        open()
        return db != nil
    }

    func entries(forForms forms: Set<String>) -> [String: [DictionaryEntry]] {
        open()
        guard let db, !forms.isEmpty else { return [:] }

        var result: [String: [DictionaryEntry]] = [:]
        // SQLite's default parameter ceiling is 999; a long paragraph produces
        // far more candidate forms than that, so the batch is chunked rather
        // than assumed to fit.
        for chunk in Array(forms).chunked(into: 900) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
                SELECT f.form, e.id, e.reading, e.pos, e.gloss_fr, e.gloss_en,
                       e.common, e.freq, f.priority, e.curated
                FROM forms f JOIN entries e ON e.id = f.entry_id
                WHERE f.form IN (\(placeholders))
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                Logger.content.error("Dictionary prepare failed")
                continue
            }
            defer { sqlite3_finalize(statement) }
            for (index, form) in chunk.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), form, -1,
                                  unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let form = text(statement, 0),
                      let reading = text(statement, 2),
                      let english = text(statement, 5) else { continue }
                let entry = DictionaryEntry(
                    id: Int(sqlite3_column_int64(statement, 1)),
                    reading: reading,
                    partsOfSpeech: (text(statement, 3) ?? "")
                        .split(separator: " ").map(String.init),
                    glossFR: text(statement, 4),
                    glossEN: english,
                    isCommon: sqlite3_column_int(statement, 6) == 1,
                    frequencyBand: Int(sqlite3_column_int(statement, 7)),
                    isCurated: sqlite3_column_int(statement, 9) == 1,
                    spellingRank: Int(sqlite3_column_int(statement, 8))
                )
                result[form, default: []].append(entry)
            }
        }
        for key in result.keys {
            result[key]?.sort { DictionaryEntry.rank($0) < DictionaryEntry.rank($1) }
        }
        return result
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }
}

// MARK: - Chunking

/// Tranches d'au plus `size`, pour rester sous le plafond de paramètres liés de
/// SQLite. Volontairement `private` : `SyncModelActor` porte la sienne, et deux
/// versions internes du même nom se refusent au niveau du module.
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
