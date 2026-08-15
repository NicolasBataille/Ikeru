import Foundation
import os
import SQLite3

// MARK: - ContentRepository

/// Read-only repository for static content stored in pre-built SQLite bundles.
///
/// Uses the SQLite3 C API directly for read-only access to avoid SwiftData overhead.
/// All queries are async and run off the main thread.
///
/// ## SQLite Bundle Schema
///
/// ```sql
/// CREATE TABLE kanji (
///     character TEXT PRIMARY KEY,
///     on_readings TEXT,       -- JSON array
///     kun_readings TEXT,      -- JSON array
///     meanings TEXT,          -- JSON array
///     jlpt_level TEXT,
///     stroke_count INTEGER,
///     stroke_order_svg TEXT   -- KanjiVG SVG path data
/// );
///
/// CREATE TABLE radicals (
///     character TEXT PRIMARY KEY,
///     meaning TEXT,
///     stroke_count INTEGER
/// );
///
/// CREATE TABLE kana (
///     character TEXT PRIMARY KEY,
///     stroke_count INTEGER,       -- derived from the stored SVG's path count
///     stroke_order_svg TEXT       -- KanjiVG SVG path data
/// );                              -- covers the 92 base + 50 dakuten kana only;
///                                 -- yōon digraphs (きゃ, etc.) have no row —
///                                 -- KanjiVG has no file for a two-codepoint
///                                 -- combination. See KanaGroup.swift for the
///                                 -- full 208-character list (romaji, section).
///
/// CREATE TABLE kanji_radical_edges (
///     radical_character TEXT,
///     kanji_character TEXT,
///     PRIMARY KEY (radical_character, kanji_character)
/// );
///
/// CREATE TABLE vocabulary (
///     id INTEGER PRIMARY KEY,
///     word TEXT,
///     reading TEXT,
///     meaning TEXT,
///     meaning_fr TEXT,        -- French gloss (see below)
///     kanji_character TEXT,   -- nullable FK
///     jlpt_level TEXT
/// );
///
/// CREATE TABLE sentences (
///     id INTEGER PRIMARY KEY,
///     japanese TEXT,
///     english TEXT,
///     french TEXT,            -- French translation (no reader yet, see below)
///     vocabulary_word TEXT    -- FK for lookup
/// );
///
/// CREATE TABLE grammar_points (
///     id INTEGER PRIMARY KEY,
///     jlpt_level TEXT,
///     title TEXT,
///     title_fr TEXT,
///     explanation TEXT,
///     explanation_fr TEXT,
///     examples TEXT,          -- JSON array
///     examples_fr TEXT        -- JSON array
/// );
/// ```
///
/// ## Language
///
/// Learner-facing glosses exist in English (authoritative, every row) and
/// French (`_fr` columns, written by `scripts/apply-content-fr.py`). The
/// language is fixed at construction — Core never reads `Locale.current`, the
/// app target resolves it from `AppLocale` and passes it in.
///
/// Two safeguards, both handled here so no caller has to think about them:
///
/// - **Per-row fallback**: a French column that is NULL, blank, or an empty
///   JSON array (`[]`) serves the English value instead. A field of English
///   text beats a blank field on screen.
/// - **Older bundles**: a bundle predating the French columns is detected via
///   `PRAGMA table_info` and queried in English, rather than failing to
///   prepare and returning nothing.
///
/// `sentences.french` is populated but has no reader: `fetchSentences` only
/// serves the Japanese, and nothing in the app reads `sentences.english`
/// today either. The data is in place for a future consumer.
public final class ContentRepository: Sendable {

    /// The background actor performing thread-safe SQLite operations.
    private let actor: ContentDatabaseActor

    /// Creates a ContentRepository with the given SQLite bundle URL.
    /// - Parameters:
    ///   - bundleURL: Path to the .sqlite file. Must be accessible for reading.
    ///   - language: Language for learner-facing glosses. Defaults to
    ///     `.english`, the bundle's authoritative language — an unwired
    ///     caller gets complete content, never a silent locale guess.
    public init(bundleURL: URL, language: ContentLanguage = .english) {
        self.actor = ContentDatabaseActor(bundleURL: bundleURL, language: language)
    }

    // MARK: - Kanji Queries

    /// Fetch all kanji for a given JLPT level.
    /// - Parameter level: The JLPT level to filter by.
    /// - Returns: Array of Kanji structs for that level.
    public func kanjiByLevel(_ level: JLPTLevel) async -> [Kanji] {
        await actor.kanjiByLevel(level)
    }

    /// Fetch radicals that compose a given kanji.
    /// - Parameter character: The kanji character to look up.
    /// - Returns: Array of Radical structs that are components of the kanji.
    public func radicalsForKanji(_ character: String) async -> [Radical] {
        await actor.radicalsForKanji(character)
    }

    // MARK: - Kana Queries

    /// Fetch stroke-order trace data for a single kana character.
    ///
    /// Covers the 92 base + 50 dakuten kana only (single Unicode codepoint
    /// each). Yōon digraphs (きゃ, しゅ, ...) return `nil` — KanjiVG, the
    /// upstream data source, has no file for a two-codepoint combination.
    /// See `KanaGroup.swift` for the full 208-character kana list.
    /// - Parameter character: The kana character to look up (e.g. "か").
    /// - Returns: `(strokeCount, svg)` if trace data exists, else `nil`.
    public func kanaStrokeData(for character: String) async -> (strokeCount: Int, svg: String)? {
        await actor.kanaStrokeData(for: character)
    }

    // MARK: - Vocabulary Queries

    /// Fetch vocabulary items related to a given kanji.
    /// - Parameter character: The kanji character to look up.
    /// - Returns: Array of Vocabulary structs related to the kanji.
    public func vocabularyForKanji(_ character: String) async -> [Vocabulary] {
        await actor.vocabularyForKanji(character)
    }

    /// Fetch example sentences for a vocabulary word.
    /// - Parameter word: The vocabulary word to look up.
    /// - Returns: Array of Japanese sentence strings.
    public func sentencesForVocabulary(_ word: String) async -> [String] {
        await actor.sentencesForVocabulary(word)
    }

    /// Fetch vocabulary items for a given JLPT level.
    /// - Parameter level: The JLPT level to filter by.
    /// - Returns: Array of Vocabulary structs for that level.
    public func vocabularyByLevel(_ level: JLPTLevel) async -> [Vocabulary] {
        await actor.vocabularyByLevel(level)
    }

    /// Build a `word -> reading` lookup for a given JLPT level from the
    /// curated bundle. Used to validate/correct AI-generated furigana in
    /// conversation vocabulary hints (see `ReadingValidator`) — the bundle's
    /// readings are authoritative, unlike the model's.
    /// - Parameter level: The JLPT level to filter by.
    /// - Returns: A `word -> reading` map, skipping entries with an empty
    ///   word or empty reading. On a duplicate word (a future homograph with
    ///   two curated rows) the lowest-`id` entry wins, so the reading Sakura
    ///   enforces is deterministic rather than dependent on unordered SQL.
    public func readingLookup(for level: JLPTLevel) async -> [String: String] {
        Self.buildReadingLookup(from: await vocabularyByLevel(level))
    }

    /// Pure dedupe step factored out of `readingLookup(for:)` so it is
    /// unit-testable without a database. Sorted by `id` first so the
    /// first-writer-wins tie-break is deterministic (lowest id wins)
    /// regardless of the order rows come back from the query.
    static func buildReadingLookup(from vocabulary: [Vocabulary]) -> [String: String] {
        var lookup: [String: String] = [:]
        for entry in vocabulary.sorted(by: { $0.id < $1.id }) where !entry.word.isEmpty && !entry.reading.isEmpty {
            if lookup[entry.word] == nil {
                lookup[entry.word] = entry.reading
            }
        }
        return lookup
    }

    // MARK: - Grammar Queries

    /// Fetch grammar points for a given JLPT level.
    /// - Parameter level: The JLPT level to filter by.
    /// - Returns: Array of GrammarPoint structs for that level.
    public func grammarPointsByLevel(_ level: JLPTLevel) async -> [GrammarPoint] {
        await actor.grammarPointsByLevel(level)
    }

    // MARK: - Edge Queries

    /// Fetch all kanji-radical edges for a given JLPT level.
    /// - Parameter level: The JLPT level to filter by.
    /// - Returns: Array of KanjiRadicalEdge structs.
    public func edgesByLevel(_ level: JLPTLevel) async -> [KanjiRadicalEdge] {
        await actor.edgesByLevel(level)
    }

    /// Fetch all kanji-radical edges in the database.
    /// - Returns: Array of all KanjiRadicalEdge structs.
    public func allEdges() async -> [KanjiRadicalEdge] {
        await actor.allEdges()
    }

    /// Fetch all radicals in the database.
    /// - Returns: Array of all Radical structs.
    public func allRadicals() async -> [Radical] {
        await actor.allRadicals()
    }
}

// MARK: - ContentDatabaseActor

/// SQLite destructor type constant: tells SQLite to copy the bound string data.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Actor that encapsulates SQLite3 C API operations for thread safety.
/// All database access is serialized through this actor.
actor ContentDatabaseActor {

    private let bundleURL: URL
    private let language: ContentLanguage
    private nonisolated(unsafe) var db: OpaquePointer?
    private let decoder = JSONDecoder()

    /// Column names per table, read once via `PRAGMA table_info` and cached —
    /// used to tell a French-capable bundle from an older English-only one.
    private var columnCache: [String: Set<String>] = [:]

    init(bundleURL: URL, language: ContentLanguage = .english) {
        self.bundleURL = bundleURL
        self.language = language
    }

    // MARK: - Database Lifecycle

    private func openIfNeeded() -> Bool {
        guard db == nil else { return true }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(bundleURL.path, &db, flags, nil)

        if result != SQLITE_OK {
            let errorMessage = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Logger.content.error("Failed to open content database: \(errorMessage)")
            db = nil
            return false
        }

        Logger.content.info("Opened content database: \(self.bundleURL.lastPathComponent)")
        return true
    }

    nonisolated deinit {
        // OpaquePointer is safe to close from deinit — no other references exist at this point
        if let db = self.db {
            sqlite3_close(db)
        }
    }

    // MARK: - Kanji Queries

    func kanjiByLevel(_ level: JLPTLevel) -> [Kanji] {
        guard openIfNeeded() else { return [] }

        let meanings = localizedColumn(
            english: "meanings", french: "meanings_fr", table: "kanji", qualifier: "k."
        )
        let sql = """
            SELECT k.character, k.on_readings, k.kun_readings, \(meanings),
                   k.jlpt_level, k.stroke_count, k.stroke_order_svg
            FROM kanji k WHERE k.jlpt_level = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare kanjiByLevel query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, level.rawValue, -1, SQLITE_TRANSIENT)

        var results: [Kanji] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let character = columnText(stmt, 0)
            let onReadings = decodeJSONArray(columnText(stmt, 1))
            let kunReadings = decodeJSONArray(columnText(stmt, 2))
            let meanings = decodeJSONArray(columnText(stmt, 3))
            let jlptLevel = JLPTLevel(rawValue: columnText(stmt, 4)) ?? .n5
            let strokeCount = Int(sqlite3_column_int(stmt, 5))
            let strokeOrderSVG = columnOptionalText(stmt, 6)

            // Fetch radicals for this kanji inline
            let radicals = fetchRadicalCharacters(for: character)

            let kanji = Kanji(
                character: character,
                radicals: radicals,
                onReadings: onReadings,
                kunReadings: kunReadings,
                meanings: meanings,
                jlptLevel: jlptLevel,
                strokeCount: strokeCount,
                strokeOrderSVGRef: strokeOrderSVG
            )
            results.append(kanji)
        }

        Logger.content.debug("Fetched \(results.count) kanji for level \(level.rawValue)")
        return results
    }

    func radicalsForKanji(_ character: String) -> [Radical] {
        guard openIfNeeded() else { return [] }

        let sql = """
            SELECT r.character, r.meaning, r.stroke_count
            FROM radicals r
            JOIN kanji_radical_edges e ON r.character = e.radical_character
            WHERE e.kanji_character = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare radicalsForKanji query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, character, -1, SQLITE_TRANSIENT)

        var results: [Radical] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let radical = Radical(
                character: columnText(stmt, 0),
                meaning: columnText(stmt, 1),
                strokeCount: Int(sqlite3_column_int(stmt, 2))
            )
            results.append(radical)
        }
        return results
    }

    // MARK: - Kana Queries

    /// Returns `nil` both when the character has no trace data (e.g. a yōon
    /// digraph) and when the bundle predates the `kana` table entirely —
    /// `sqlite3_prepare_v2` fails gracefully on a missing table, it is
    /// logged, not a crash.
    func kanaStrokeData(for character: String) -> (strokeCount: Int, svg: String)? {
        guard openIfNeeded() else { return nil }

        let sql = "SELECT stroke_count, stroke_order_svg FROM kana WHERE character = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare kanaStrokeData query")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, character, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let svg = columnOptionalText(stmt, 1) else {
            return nil
        }
        let strokeCount = Int(sqlite3_column_int(stmt, 0))
        return (strokeCount, svg)
    }

    // MARK: - Vocabulary Queries

    func vocabularyForKanji(_ character: String) -> [Vocabulary] {
        guard openIfNeeded() else { return [] }

        let sql = """
            SELECT v.id, v.word, v.reading, \(vocabularyMeaningColumn),
                   v.kanji_character, v.jlpt_level
            FROM vocabulary v WHERE v.kanji_character = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare vocabularyForKanji query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, character, -1, SQLITE_TRANSIENT)

        var results: [Vocabulary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let vocabId = Int(sqlite3_column_int(stmt, 0))
            let word = columnText(stmt, 1)

            // Fetch sentences for this word
            let sentences = fetchSentences(for: word)

            let vocab = Vocabulary(
                id: vocabId,
                word: word,
                reading: columnText(stmt, 2),
                meaning: columnText(stmt, 3),
                kanjiCharacter: columnOptionalText(stmt, 4),
                jlptLevel: JLPTLevel(rawValue: columnText(stmt, 5)) ?? .n5,
                exampleSentences: sentences
            )
            results.append(vocab)
        }
        return results
    }

    func sentencesForVocabulary(_ word: String) -> [String] {
        fetchSentences(for: word)
    }

    func vocabularyByLevel(_ level: JLPTLevel) -> [Vocabulary] {
        guard openIfNeeded() else { return [] }

        let sql = """
            SELECT v.id, v.word, v.reading, \(vocabularyMeaningColumn),
                   v.kanji_character, v.jlpt_level
            FROM vocabulary v WHERE v.jlpt_level = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare vocabularyByLevel query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, level.rawValue, -1, SQLITE_TRANSIENT)

        var results: [Vocabulary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let vocabId = Int(sqlite3_column_int(stmt, 0))
            let word = columnText(stmt, 1)
            let sentences = fetchSentences(for: word)

            let vocab = Vocabulary(
                id: vocabId,
                word: word,
                reading: columnText(stmt, 2),
                meaning: columnText(stmt, 3),
                kanjiCharacter: columnOptionalText(stmt, 4),
                jlptLevel: JLPTLevel(rawValue: columnText(stmt, 5)) ?? .n5,
                exampleSentences: sentences
            )
            results.append(vocab)
        }

        Logger.content.debug("Fetched \(results.count) vocabulary for level \(level.rawValue)")
        return results
    }

    // MARK: - Grammar Queries

    func grammarPointsByLevel(_ level: JLPTLevel) -> [GrammarPoint] {
        guard openIfNeeded() else { return [] }

        let title = localizedColumn(english: "title", french: "title_fr", table: "grammar_points")
        let explanation = localizedColumn(
            english: "explanation", french: "explanation_fr", table: "grammar_points"
        )
        let examples = localizedColumn(
            english: "examples", french: "examples_fr", table: "grammar_points"
        )
        let sql = """
            SELECT id, jlpt_level, \(title), \(explanation), \(examples)
            FROM grammar_points WHERE jlpt_level = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare grammarPointsByLevel query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, level.rawValue, -1, SQLITE_TRANSIENT)

        var results: [GrammarPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let grammar = GrammarPoint(
                id: Int(sqlite3_column_int(stmt, 0)),
                jlptLevel: JLPTLevel(rawValue: columnText(stmt, 1)) ?? .n5,
                title: columnText(stmt, 2),
                explanation: columnText(stmt, 3),
                examples: decodeJSONArray(columnText(stmt, 4))
            )
            results.append(grammar)
        }
        return results
    }

    // MARK: - Edge Queries

    func edgesByLevel(_ level: JLPTLevel) -> [KanjiRadicalEdge] {
        guard openIfNeeded() else { return [] }

        let sql = """
            SELECT e.radical_character, e.kanji_character
            FROM kanji_radical_edges e
            JOIN kanji k ON e.kanji_character = k.character
            WHERE k.jlpt_level = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare edgesByLevel query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, level.rawValue, -1, SQLITE_TRANSIENT)

        var results: [KanjiRadicalEdge] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let edge = KanjiRadicalEdge(
                radicalCharacter: columnText(stmt, 0),
                kanjiCharacter: columnText(stmt, 1)
            )
            results.append(edge)
        }
        return results
    }

    func allEdges() -> [KanjiRadicalEdge] {
        guard openIfNeeded() else { return [] }

        let sql = "SELECT radical_character, kanji_character FROM kanji_radical_edges"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare allEdges query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [KanjiRadicalEdge] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let edge = KanjiRadicalEdge(
                radicalCharacter: columnText(stmt, 0),
                kanjiCharacter: columnText(stmt, 1)
            )
            results.append(edge)
        }
        return results
    }

    func allRadicals() -> [Radical] {
        guard openIfNeeded() else { return [] }

        let sql = "SELECT character, meaning, stroke_count FROM radicals"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.content.error("Failed to prepare allRadicals query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [Radical] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let radical = Radical(
                character: columnText(stmt, 0),
                meaning: columnText(stmt, 1),
                strokeCount: Int(sqlite3_column_int(stmt, 2))
            )
            results.append(radical)
        }
        return results
    }

    // MARK: - Language Helpers

    /// Column names of `table`, cached after the first `PRAGMA table_info`.
    /// An unknown or missing table yields an empty set, which makes
    /// `localizedColumn` degrade to the English column.
    private func columnNames(of table: String) -> Set<String> {
        if let cached = columnCache[table] { return cached }

        var names: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                names.insert(columnText(stmt, 1))
            }
        } else {
            Logger.content.error("Failed to read schema of table \(table)")
        }
        sqlite3_finalize(stmt)

        columnCache[table] = names
        return names
    }

    /// The localized `vocabulary.meaning` expression, shared by the two
    /// vocabulary queries so they can never drift apart on language.
    private var vocabularyMeaningColumn: String {
        localizedColumn(
            english: "meaning", french: "meaning_fr", table: "vocabulary", qualifier: "v."
        )
    }

    /// SQL expression serving the localized value of a column, with an
    /// explicit per-row fallback to English.
    ///
    /// In English, or against a bundle whose French column doesn't exist, this
    /// is just the English column. In French it becomes a `CASE` that treats
    /// NULL, blank and `'[]'` (an empty JSON array — how a missing
    /// `meanings_fr` / `examples_fr` would show up) as "not translated" and
    /// serves the English value for that row.
    /// - Parameters:
    ///   - english: The authoritative column name.
    ///   - french: The `_fr` column name.
    ///   - table: Table the columns belong to, for the schema probe.
    ///   - qualifier: Table alias prefix used in the query (e.g. `"v."`).
    /// - Returns: An expression to splice into a SELECT list.
    private func localizedColumn(
        english: String,
        french: String,
        table: String,
        qualifier: String = ""
    ) -> String {
        let englishColumn = qualifier + english
        guard language == .french, columnNames(of: table).contains(french) else {
            return englishColumn
        }
        let frenchColumn = qualifier + french
        return "CASE WHEN TRIM(COALESCE(\(frenchColumn), '')) IN ('', '[]') "
            + "THEN \(englishColumn) ELSE \(frenchColumn) END"
    }

    // MARK: - Private Helpers

    private func fetchRadicalCharacters(for kanjiCharacter: String) -> [String] {
        guard let db else { return [] }

        let sql = "SELECT radical_character FROM kanji_radical_edges WHERE kanji_character = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, kanjiCharacter, -1, SQLITE_TRANSIENT)

        var radicals: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            radicals.append(columnText(stmt, 0))
        }
        return radicals
    }

    private func fetchSentences(for word: String) -> [String] {
        guard openIfNeeded() else { return [] }

        let sql = "SELECT japanese FROM sentences WHERE vocabulary_word = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)

        var sentences: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sentences.append(columnText(stmt, 0))
        }
        return sentences
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func decodeJSONArray(_ jsonString: String) -> [String] {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let array = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return array
    }
}
