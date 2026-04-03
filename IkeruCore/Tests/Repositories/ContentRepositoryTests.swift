import Testing
import Foundation
@testable import IkeruCore

// MARK: - ContentRepository Tests

@Suite("ContentRepository")
struct ContentRepositoryTests {

    /// Creates a temporary in-memory SQLite database with test data and returns a ContentRepository.
    private func makeTestRepository() throws -> ContentRepository {
        let testBundleURL = try createTestDatabase()
        return ContentRepository(bundleURL: testBundleURL)
    }

    // MARK: - Kanji Queries

    @Test("kanjiByLevel returns kanji for the specified level")
    func kanjiByLevel() async throws {
        let repo = try makeTestRepository()
        let kanji = await repo.kanjiByLevel(.n5)

        #expect(!kanji.isEmpty)
        #expect(kanji.allSatisfy { $0.jlptLevel == .n5 })
    }

    @Test("kanjiByLevel returns empty for level with no data")
    func kanjiByLevelEmpty() async throws {
        let repo = try makeTestRepository()
        let kanji = await repo.kanjiByLevel(.n1)

        #expect(kanji.isEmpty)
    }

    @Test("kanjiByLevel returns kanji with correct fields")
    func kanjiFields() async throws {
        let repo = try makeTestRepository()
        let kanji = await repo.kanjiByLevel(.n5)

        guard let sun = kanji.first(where: { $0.character == "\u{65E5}" }) else {
            Issue.record("Expected kanji \u{65E5} not found")
            return
        }

        #expect(sun.character == "\u{65E5}")
        #expect(!sun.onReadings.isEmpty)
        #expect(!sun.kunReadings.isEmpty)
        #expect(!sun.meanings.isEmpty)
        #expect(sun.jlptLevel == .n5)
        #expect(sun.strokeCount > 0)
    }

    @Test("kanjiByLevel populates radicals array from edges")
    func kanjiRadicalsPopulated() async throws {
        let repo = try makeTestRepository()
        let kanji = await repo.kanjiByLevel(.n5)

        guard let sun = kanji.first(where: { $0.character == "\u{65E5}" }) else {
            Issue.record("Expected kanji \u{65E5} not found")
            return
        }

        #expect(!sun.radicals.isEmpty)
    }

    // MARK: - Radical Queries

    @Test("radicalsForKanji returns radicals that compose a kanji")
    func radicalsForKanji() async throws {
        let repo = try makeTestRepository()
        let radicals = await repo.radicalsForKanji("\u{65E5}")

        #expect(!radicals.isEmpty)
        #expect(radicals.allSatisfy { !$0.character.isEmpty })
        #expect(radicals.allSatisfy { !$0.meaning.isEmpty })
    }

    @Test("radicalsForKanji returns empty for unknown kanji")
    func radicalsForUnknownKanji() async throws {
        let repo = try makeTestRepository()
        let radicals = await repo.radicalsForKanji("\u{9F8D}") // dragon - not in test data

        #expect(radicals.isEmpty)
    }

    // MARK: - Vocabulary Queries

    @Test("vocabularyForKanji returns vocabulary related to a kanji")
    func vocabularyForKanji() async throws {
        let repo = try makeTestRepository()
        let vocab = await repo.vocabularyForKanji("\u{65E5}")

        #expect(!vocab.isEmpty)
        #expect(vocab.allSatisfy { $0.kanjiCharacter == "\u{65E5}" })
    }

    @Test("vocabularyForKanji returns empty for kanji with no vocabulary")
    func vocabularyForUnknownKanji() async throws {
        let repo = try makeTestRepository()
        let vocab = await repo.vocabularyForKanji("\u{9F8D}")

        #expect(vocab.isEmpty)
    }

    // MARK: - Sentence Queries

    @Test("sentencesForVocabulary returns sentences for a word")
    func sentencesForVocabulary() async throws {
        let repo = try makeTestRepository()
        let sentences = await repo.sentencesForVocabulary("\u{65E5}\u{672C}") // 日本

        #expect(!sentences.isEmpty)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }

    @Test("sentencesForVocabulary returns empty for unknown word")
    func sentencesForUnknownWord() async throws {
        let repo = try makeTestRepository()
        let sentences = await repo.sentencesForVocabulary("nonexistent")

        #expect(sentences.isEmpty)
    }

    // MARK: - Grammar Queries

    @Test("grammarPointsByLevel returns grammar points for the level")
    func grammarPointsByLevel() async throws {
        let repo = try makeTestRepository()
        let grammar = await repo.grammarPointsByLevel(.n5)

        #expect(!grammar.isEmpty)
        #expect(grammar.allSatisfy { $0.jlptLevel == .n5 })
        #expect(grammar.allSatisfy { !$0.title.isEmpty })
        #expect(grammar.allSatisfy { !$0.explanation.isEmpty })
    }

    @Test("grammarPointsByLevel returns empty for level with no data")
    func grammarPointsByLevelEmpty() async throws {
        let repo = try makeTestRepository()
        let grammar = await repo.grammarPointsByLevel(.n1)

        #expect(grammar.isEmpty)
    }

    // MARK: - Edge Queries

    @Test("allEdges returns all kanji-radical edges")
    func allEdges() async throws {
        let repo = try makeTestRepository()
        let edges = await repo.allEdges()

        #expect(!edges.isEmpty)
        #expect(edges.allSatisfy { !$0.radicalCharacter.isEmpty })
        #expect(edges.allSatisfy { !$0.kanjiCharacter.isEmpty })
    }

    @Test("edgesByLevel returns edges for kanji of that level")
    func edgesByLevel() async throws {
        let repo = try makeTestRepository()
        let edges = await repo.edgesByLevel(.n5)

        #expect(!edges.isEmpty)
    }

    @Test("allRadicals returns all radicals")
    func allRadicals() async throws {
        let repo = try makeTestRepository()
        let radicals = await repo.allRadicals()

        #expect(!radicals.isEmpty)
        #expect(radicals.allSatisfy { !$0.character.isEmpty })
    }

    // MARK: - Error Handling

    @Test("Repository handles missing database file gracefully")
    func missingDatabase() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/test.sqlite")
        let repo = ContentRepository(bundleURL: badURL)

        let kanji = await repo.kanjiByLevel(.n5)
        #expect(kanji.isEmpty)
    }
}

// MARK: - Test Database Helper

import SQLite3

/// Creates a temporary SQLite database with test content data.
/// Returns the URL of the created database file.
private func createTestDatabase() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let dbURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
        throw TestDatabaseError.cannotOpen
    }

    // Create schema
    let schemaSQL = """
    CREATE TABLE kanji (
        character TEXT PRIMARY KEY,
        on_readings TEXT,
        kun_readings TEXT,
        meanings TEXT,
        jlpt_level TEXT,
        stroke_count INTEGER,
        stroke_order_svg TEXT
    );
    CREATE TABLE radicals (
        character TEXT PRIMARY KEY,
        meaning TEXT,
        stroke_count INTEGER
    );
    CREATE TABLE kanji_radical_edges (
        radical_character TEXT,
        kanji_character TEXT,
        PRIMARY KEY (radical_character, kanji_character)
    );
    CREATE TABLE vocabulary (
        id INTEGER PRIMARY KEY,
        word TEXT,
        reading TEXT,
        meaning TEXT,
        kanji_character TEXT,
        jlpt_level TEXT
    );
    CREATE TABLE sentences (
        id INTEGER PRIMARY KEY,
        japanese TEXT,
        english TEXT,
        vocabulary_word TEXT
    );
    CREATE TABLE grammar_points (
        id INTEGER PRIMARY KEY,
        jlpt_level TEXT,
        title TEXT,
        explanation TEXT,
        examples TEXT
    );
    """

    var errMsg: UnsafeMutablePointer<CChar>?
    sqlite3_exec(db, schemaSQL, nil, nil, &errMsg)
    if let errMsg {
        sqlite3_free(errMsg)
    }

    // Insert radicals
    let radicals = [
        ("\u{4E00}", "one", 1),
        ("\u{53E3}", "mouth", 3),
        ("\u{4EBA}", "person", 2),
        ("\u{4E28}", "line", 1),
        ("\u{4E36}", "dot", 1),
        ("\u{30CE}", "slash", 1),
        ("\u{4E8C}", "two", 2),
        ("\u{571F}", "earth", 3),
        ("\u{5B50}", "child", 3),
        ("\u{5DE5}", "craft", 3),
        ("\u{7530}", "rice field", 5),
        ("\u{5927}", "big", 3),
    ]
    for (char, meaning, strokes) in radicals {
        execSQL(db, "INSERT INTO radicals VALUES (?, ?, ?)", texts: [char, meaning], ints: [Int32(strokes)])
    }

    // Insert kanji with edges
    let kanjiEntries: [(String, [String], String, String, String, Int)] = [
        // character, radicals, onReadings JSON, kunReadings JSON, meanings JSON, strokeCount
        ("\u{65E5}", ["\u{4E00}", "\u{53E3}"],
         #"["ニチ","ジツ"]"#, #"["ひ","か"]"#, #"["day","sun"]"#, 4),
        ("\u{6708}", ["\u{4E8C}", "\u{4E28}"],
         #"["ゲツ","ガツ"]"#, #"["つき"]"#, #"["month","moon"]"#, 4),
        ("\u{706B}", ["\u{4EBA}", "\u{4E36}"],
         #"["カ"]"#, #"["ひ","ほ"]"#, #"["fire"]"#, 4),
        ("\u{5B66}", ["\u{5B50}", "\u{30CE}"],
         #"["ガク"]"#, #"["まな"]"#, #"["study","learn"]"#, 8),
        ("\u{7537}", ["\u{7530}", "\u{5927}"],
         #"["ダン","ナン"]"#, #"["おとこ"]"#, #"["man","male"]"#, 7),
        ("\u{91D1}", ["\u{4EBA}", "\u{4E00}", "\u{571F}"],
         #"["キン","コン"]"#, #"["かね","かな"]"#, #"["gold","money"]"#, 8),
    ]

    for (char, radicals, onJSON, kunJSON, meaningsJSON, strokes) in kanjiEntries {
        let sql = "INSERT INTO kanji VALUES (?, ?, ?, ?, 'n5', ?, NULL)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        bindText(stmt, 1, char)
        bindText(stmt, 2, onJSON)
        bindText(stmt, 3, kunJSON)
        bindText(stmt, 4, meaningsJSON)
        sqlite3_bind_int(stmt, 5, Int32(strokes))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        for radical in radicals {
            let edgeSql = "INSERT INTO kanji_radical_edges VALUES (?, ?)"
            var edgeStmt: OpaquePointer?
            sqlite3_prepare_v2(db, edgeSql, -1, &edgeStmt, nil)
            bindText(edgeStmt, 1, radical)
            bindText(edgeStmt, 2, char)
            sqlite3_step(edgeStmt)
            sqlite3_finalize(edgeStmt)
        }
    }

    // Insert vocabulary
    let vocabEntries: [(String, String, String, String)] = [
        ("\u{65E5}\u{672C}", "\u{306B}\u{307B}\u{3093}", "Japan", "\u{65E5}"),
        ("\u{4ECA}\u{65E5}", "\u{304D}\u{3087}\u{3046}", "today", "\u{65E5}"),
        ("\u{5B66}\u{751F}", "\u{304C}\u{304F}\u{305B}\u{3044}", "student", "\u{5B66}"),
    ]

    for (i, (word, reading, meaning, kanjiChar)) in vocabEntries.enumerated() {
        let sql = "INSERT INTO vocabulary VALUES (?, ?, ?, ?, ?, 'n5')"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(i + 1))
        bindText(stmt, 2, word)
        bindText(stmt, 3, reading)
        bindText(stmt, 4, meaning)
        bindText(stmt, 5, kanjiChar)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert sentences
    let sentenceEntries: [(String, String, String)] = [
        ("\u{65E5}\u{672C}\u{306F}\u{7F8E}\u{3057}\u{3044}\u{56FD}\u{3067}\u{3059}\u{3002}",
         "Japan is a beautiful country.", "\u{65E5}\u{672C}"),
        ("\u{4ECA}\u{65E5}\u{306F}\u{3044}\u{3044}\u{5929}\u{6C17}\u{3067}\u{3059}\u{306D}\u{3002}",
         "It is nice weather today.", "\u{4ECA}\u{65E5}"),
    ]

    for (i, (japanese, english, vocabWord)) in sentenceEntries.enumerated() {
        let sql = "INSERT INTO sentences VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(i + 1))
        bindText(stmt, 2, japanese)
        bindText(stmt, 3, english)
        bindText(stmt, 4, vocabWord)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert grammar points
    let grammarEntries: [(String, String, String, String)] = [
        ("n5", "\u{306F} (Topic Marker)", "Marks the topic of the sentence.",
         #"["私は学生です。","今日は月曜日です。"]"#),
        ("n5", "\u{3067}\u{3059}/\u{307E}\u{3059} (Polite Form)", "Polite sentence endings.",
         #"["学生です。","食べます。"]"#),
    ]

    for (i, (level, title, explanation, examplesJSON)) in grammarEntries.enumerated() {
        let sql = "INSERT INTO grammar_points VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(i + 1))
        bindText(stmt, 2, level)
        bindText(stmt, 3, title)
        bindText(stmt, 4, explanation)
        bindText(stmt, 5, examplesJSON)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    sqlite3_close(db)
    return dbURL
}

// MARK: - SQLite Test Helpers

private func execSQL(_ db: OpaquePointer?, _ sql: String, texts: [String], ints: [Int32]) {
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    var paramIndex: Int32 = 1
    for text in texts {
        bindText(stmt, paramIndex, text)
        paramIndex += 1
    }
    for intVal in ints {
        sqlite3_bind_int(stmt, paramIndex, intVal)
        paramIndex += 1
    }
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}

private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
}

private enum TestDatabaseError: Error {
    case cannotOpen
}
