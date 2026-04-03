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
///     kanji_character TEXT,   -- nullable FK
///     jlpt_level TEXT
/// );
///
/// CREATE TABLE sentences (
///     id INTEGER PRIMARY KEY,
///     japanese TEXT,
///     english TEXT,
///     vocabulary_word TEXT    -- FK for lookup
/// );
///
/// CREATE TABLE grammar_points (
///     id INTEGER PRIMARY KEY,
///     jlpt_level TEXT,
///     title TEXT,
///     explanation TEXT,
///     examples TEXT           -- JSON array
/// );
/// ```
public final class ContentRepository: Sendable {

    /// The background actor performing thread-safe SQLite operations.
    private let actor: ContentDatabaseActor

    /// Creates a ContentRepository with the given SQLite bundle URL.
    /// - Parameter bundleURL: Path to the .sqlite file. Must be accessible for reading.
    public init(bundleURL: URL) {
        self.actor = ContentDatabaseActor(bundleURL: bundleURL)
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
    private nonisolated(unsafe) var db: OpaquePointer?
    private let decoder = JSONDecoder()

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
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

        let sql = """
            SELECT k.character, k.on_readings, k.kun_readings, k.meanings,
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

    // MARK: - Vocabulary Queries

    func vocabularyForKanji(_ character: String) -> [Vocabulary] {
        guard openIfNeeded() else { return [] }

        let sql = """
            SELECT v.id, v.word, v.reading, v.meaning, v.kanji_character, v.jlpt_level
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
            SELECT v.id, v.word, v.reading, v.meaning, v.kanji_character, v.jlpt_level
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

        let sql = """
            SELECT id, jlpt_level, title, explanation, examples
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
