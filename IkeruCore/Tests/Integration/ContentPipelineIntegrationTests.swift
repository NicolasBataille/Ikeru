import Testing
import Foundation
import SQLite3
@testable import IkeruCore

// MARK: - Content Pipeline Integration Tests

/// Integration tests for the full content pipeline:
/// SQLite bundle -> ContentRepository -> KanjiGraphRepository -> ContentLoadingService
@Suite("Content Pipeline Integration")
struct ContentPipelineIntegrationTests {

    // MARK: - Full Pipeline Tests

    @Test("Full pipeline: load bundle, build graph, topological sort, query content")
    func fullPipeline() async throws {
        let dbURL = try createIntegrationDatabase()

        // Step 1: Load content via ContentRepository
        let repo = ContentRepository(bundleURL: dbURL)
        let kanji = await repo.kanjiByLevel(.n5)
        #expect(!kanji.isEmpty)

        // Step 2: Load edges and radicals for graph construction
        let edges = await repo.allEdges()
        let radicals = await repo.allRadicals()
        #expect(!edges.isEmpty)
        #expect(!radicals.isEmpty)

        // Step 3: Build the kanji knowledge graph
        let radicalMap = Dictionary(uniqueKeysWithValues: radicals.map { ($0.character, $0) })
        let kanjiMap = Dictionary(uniqueKeysWithValues: kanji.map { ($0.character, $0) })
        let graph = KanjiGraphRepository(
            edges: edges,
            radicals: radicalMap,
            kanjiMap: kanjiMap
        )

        // Step 4: Topological sort
        let sorted = await graph.topologicalSort()
        #expect(!sorted.isEmpty)

        // Step 5: Verify ordering invariant: for every kanji, all its radicals appear earlier
        for kanjiChar in sorted {
            let prereqs = await graph.prerequisiteRadicals(for: kanjiChar)
            for prereq in prereqs {
                let prereqIndex = sorted.firstIndex(of: prereq.character)
                let kanjiIndex = sorted.firstIndex(of: kanjiChar)
                if let pi = prereqIndex, let ki = kanjiIndex {
                    #expect(pi < ki, "Radical \(prereq.character) must appear before kanji \(kanjiChar)")
                }
            }
        }

        // Step 6: Query content via repository
        let vocab = await repo.vocabularyForKanji("\u{65E5}")
        #expect(!vocab.isEmpty)

        let sentences = await repo.sentencesForVocabulary("\u{65E5}\u{672C}")
        #expect(!sentences.isEmpty)

        let grammar = await repo.grammarPointsByLevel(.n5)
        #expect(!grammar.isEmpty)
    }

    @Test("Graph ordering: every kanji's radicals appear earlier in sorted list")
    func graphOrderingInvariant() async throws {
        let dbURL = try createIntegrationDatabase()
        let repo = ContentRepository(bundleURL: dbURL)

        let kanji = await repo.kanjiByLevel(.n5)
        let edges = await repo.allEdges()
        let radicals = await repo.allRadicals()

        let radicalMap = Dictionary(uniqueKeysWithValues: radicals.map { ($0.character, $0) })
        let kanjiMap = Dictionary(uniqueKeysWithValues: kanji.map { ($0.character, $0) })
        let graph = KanjiGraphRepository(
            edges: edges,
            radicals: radicalMap,
            kanjiMap: kanjiMap
        )

        let sorted = await graph.topologicalSort()

        // For every edge (radical -> kanji), the radical must appear before the kanji
        for edge in edges {
            guard let radIdx = sorted.firstIndex(of: edge.radicalCharacter),
                  let kanjiIdx = sorted.firstIndex(of: edge.kanjiCharacter) else {
                continue
            }
            #expect(
                radIdx < kanjiIdx,
                "Edge \(edge.radicalCharacter) -> \(edge.kanjiCharacter): " +
                "radical at index \(radIdx) must be before kanji at index \(kanjiIdx)"
            )
        }
    }

    // MARK: - Progressive Loading Tests

    @Test("Progressive loading: N5 loads, N4 not available until threshold met")
    func progressiveLoading() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createBundleForLevel(in: dir, level: .n5)
        try createBundleForLevel(in: dir, level: .n4)

        let service = ContentLoadingService(bundleDirectoryURL: dir)

        // N5 should load successfully
        let n5Repo = await service.loadLevel(.n5)
        #expect(n5Repo != nil)
        #expect(service.isLevelLoaded(.n5))

        // N4 should not be suggested until 80% mastery of N5
        let noNext = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 5,
            totalKanjiCount: 10
        )
        #expect(noNext == nil)

        // At 80% mastery, N4 should be suggested
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 8,
            totalKanjiCount: 10
        )
        #expect(next == .n4)

        // Load N4
        let n4Repo = await service.loadLevel(.n4)
        #expect(n4Repo != nil)
        #expect(service.isLevelLoaded(.n4))
    }

    @Test("Content queries return expected data shapes")
    func contentDataShapes() async throws {
        let dbURL = try createIntegrationDatabase()
        let repo = ContentRepository(bundleURL: dbURL)

        // Kanji have required fields populated
        let kanji = await repo.kanjiByLevel(.n5)
        for k in kanji {
            #expect(!k.character.isEmpty)
            #expect(!k.meanings.isEmpty)
            #expect(k.strokeCount > 0)
            #expect(k.jlptLevel == .n5)
        }

        // Radicals have required fields populated
        let radicals = await repo.allRadicals()
        for r in radicals {
            #expect(!r.character.isEmpty)
            #expect(!r.meaning.isEmpty)
            #expect(r.strokeCount > 0)
        }

        // Vocabulary has required fields populated
        let vocab = await repo.vocabularyForKanji("\u{65E5}")
        for v in vocab {
            #expect(!v.word.isEmpty)
            #expect(!v.reading.isEmpty)
            #expect(!v.meaning.isEmpty)
        }

        // Grammar points have required fields populated
        let grammar = await repo.grammarPointsByLevel(.n5)
        for g in grammar {
            #expect(!g.title.isEmpty)
            #expect(!g.explanation.isEmpty)
            #expect(g.jlptLevel == .n5)
        }
    }

    @Test("Concurrent content access does not block")
    func concurrentAccess() async throws {
        let dbURL = try createIntegrationDatabase()
        let repo = ContentRepository(bundleURL: dbURL)

        // Launch multiple concurrent queries
        async let kanjiQuery = repo.kanjiByLevel(.n5)
        async let radicalQuery = repo.allRadicals()
        async let edgeQuery = repo.allEdges()
        async let vocabQuery = repo.vocabularyForKanji("\u{65E5}")
        async let grammarQuery = repo.grammarPointsByLevel(.n5)
        async let sentenceQuery = repo.sentencesForVocabulary("\u{65E5}\u{672C}")

        // All queries should complete without deadlock
        let kanji = await kanjiQuery
        let radicals = await radicalQuery
        let edges = await edgeQuery
        let vocab = await vocabQuery
        let grammar = await grammarQuery
        let sentences = await sentenceQuery

        #expect(!kanji.isEmpty)
        #expect(!radicals.isEmpty)
        #expect(!edges.isEmpty)
        #expect(!vocab.isEmpty)
        #expect(!grammar.isEmpty)
        #expect(!sentences.isEmpty)
    }

    @Test("isReady integrates with graph built from repository data")
    func isReadyIntegration() async throws {
        let dbURL = try createIntegrationDatabase()
        let repo = ContentRepository(bundleURL: dbURL)

        let kanji = await repo.kanjiByLevel(.n5)
        let edges = await repo.allEdges()
        let radicals = await repo.allRadicals()

        let radicalMap = Dictionary(uniqueKeysWithValues: radicals.map { ($0.character, $0) })
        let kanjiMap = Dictionary(uniqueKeysWithValues: kanji.map { ($0.character, $0) })
        let graph = KanjiGraphRepository(
            edges: edges,
            radicals: radicalMap,
            kanjiMap: kanjiMap
        )

        // A kanji with prerequisites should not be ready when no radicals are learned
        let sunKanji = "\u{65E5}" // 日
        let sunPrereqs = await graph.prerequisiteRadicals(for: sunKanji)

        if !sunPrereqs.isEmpty {
            let notReady = await graph.isReady(kanji: sunKanji, learnedRadicals: [])
            #expect(!notReady)

            // After learning all prerequisites, kanji should be ready
            let learnedAll = Set(sunPrereqs.map(\.character))
            let ready = await graph.isReady(kanji: sunKanji, learnedRadicals: learnedAll)
            #expect(ready)
        }

        // A radical with no prerequisites should always be ready
        let radicalChars = Set(radicals.map(\.character))
        let kanjiChars = Set(kanji.map(\.character))
        let pureRadicals = radicalChars.subtracting(kanjiChars)

        if let pureRadical = pureRadicals.first {
            let ready = await graph.isReady(kanji: pureRadical, learnedRadicals: [])
            #expect(ready)
        }
    }

    @Test("dependentKanji returns correct kanji for a radical from live data")
    func dependentKanjiFromLiveData() async throws {
        let dbURL = try createIntegrationDatabase()
        let repo = ContentRepository(bundleURL: dbURL)

        let kanji = await repo.kanjiByLevel(.n5)
        let edges = await repo.allEdges()
        let radicals = await repo.allRadicals()

        let radicalMap = Dictionary(uniqueKeysWithValues: radicals.map { ($0.character, $0) })
        let kanjiMap = Dictionary(uniqueKeysWithValues: kanji.map { ($0.character, $0) })
        let graph = KanjiGraphRepository(
            edges: edges,
            radicals: radicalMap,
            kanjiMap: kanjiMap
        )

        // 一 (one) radical is used by 日 (sun) and 金 (gold)
        let dependents = await graph.dependentKanji(of: "\u{4E00}")
        let dependentChars = dependents.map(\.character)
        #expect(dependentChars.contains("\u{65E5}")) // 日
        #expect(dependentChars.contains("\u{91D1}")) // 金
    }
}

// MARK: - Integration Test Database Helper

/// Creates a test SQLite database with comprehensive N5 content data
/// suitable for integration testing the full pipeline.
private func createIntegrationDatabase() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let dbURL = tempDir.appendingPathComponent("integration-\(UUID().uuidString).sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
        throw IntegrationTestError.cannotOpenDatabase
    }
    defer { sqlite3_close(db) }

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
    if let errMsg { sqlite3_free(errMsg) }

    // Insert radicals
    let radicals: [(String, String, Int32)] = [
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
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO radicals VALUES (?, ?, ?)", -1, &stmt, nil)
        bindText(stmt, 1, char)
        bindText(stmt, 2, meaning)
        sqlite3_bind_int(stmt, 3, strokes)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert kanji with edges
    let kanjiEntries: [(String, [String], String, String, String, Int32)] = [
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

    for (char, rads, onJSON, kunJSON, meaningsJSON, strokes) in kanjiEntries {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO kanji VALUES (?, ?, ?, ?, 'n5', ?, NULL)", -1, &stmt, nil)
        bindText(stmt, 1, char)
        bindText(stmt, 2, onJSON)
        bindText(stmt, 3, kunJSON)
        bindText(stmt, 4, meaningsJSON)
        sqlite3_bind_int(stmt, 5, strokes)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        for radical in rads {
            var edgeStmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO kanji_radical_edges VALUES (?, ?)", -1, &edgeStmt, nil)
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
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO vocabulary VALUES (?, ?, ?, ?, ?, 'n5')", -1, &stmt, nil)
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
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO sentences VALUES (?, ?, ?, ?)", -1, &stmt, nil)
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
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO grammar_points VALUES (?, ?, ?, ?, ?)", -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(i + 1))
        bindText(stmt, 2, level)
        bindText(stmt, 3, title)
        bindText(stmt, 4, explanation)
        bindText(stmt, 5, examplesJSON)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    return dbURL
}

/// Creates a minimal valid SQLite content bundle for a specific level.
private func createBundleForLevel(in directory: URL, level: JLPTLevel) throws {
    let bundleURL = directory.appendingPathComponent("\(level.rawValue)-content.sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(bundleURL.path, &db) == SQLITE_OK else {
        throw IntegrationTestError.cannotOpenDatabase
    }
    defer { sqlite3_close(db) }

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
    if let errMsg { sqlite3_free(errMsg) }

    // Insert a radical
    var radStmt: OpaquePointer?
    sqlite3_prepare_v2(db, "INSERT INTO radicals VALUES (?, ?, ?)", -1, &radStmt, nil)
    bindText(radStmt, 1, "\u{4E00}")
    bindText(radStmt, 2, "one")
    sqlite3_bind_int(radStmt, 3, 1)
    sqlite3_step(radStmt)
    sqlite3_finalize(radStmt)

    // Insert a kanji
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, "INSERT INTO kanji VALUES (?, ?, ?, ?, ?, ?, NULL)", -1, &stmt, nil)
    bindText(stmt, 1, "\u{65E5}")
    bindText(stmt, 2, #"["ニチ"]"#)
    bindText(stmt, 3, #"["ひ"]"#)
    bindText(stmt, 4, #"["day","sun"]"#)
    bindText(stmt, 5, level.rawValue)
    sqlite3_bind_int(stmt, 6, 4)
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)

    // Insert edge
    var edgeStmt: OpaquePointer?
    sqlite3_prepare_v2(db, "INSERT INTO kanji_radical_edges VALUES (?, ?)", -1, &edgeStmt, nil)
    bindText(edgeStmt, 1, "\u{4E00}")
    bindText(edgeStmt, 2, "\u{65E5}")
    sqlite3_step(edgeStmt)
    sqlite3_finalize(edgeStmt)
}

private func makeTempBundleDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("IntegrationTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func cleanUp(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(
        stmt, index, value, -1,
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    )
}

private enum IntegrationTestError: Error {
    case cannotOpenDatabase
}
