import Testing
import Foundation
import SQLite3
@testable import IkeruCore

@Suite("ContentLoadingService")
@MainActor
struct ContentLoadingServiceTests {

    // MARK: - Helpers

    /// Creates a temp directory for content bundles and returns its URL.
    private func makeTempBundleDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentLoadingTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temp directory and all its contents.
    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a minimal valid SQLite content bundle at the expected path for a level.
    /// The database contains a single kanji row matching the given level.
    private func createTestBundle(in directory: URL, for level: JLPTLevel) throws -> URL {
        let bundleURL = directory.appendingPathComponent("\(level.rawValue)-content.sqlite")

        var db: OpaquePointer?
        guard sqlite3_open(bundleURL.path, &db) == SQLITE_OK else {
            throw ContentLoadingTestError.cannotOpenDatabase
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
        let insertRadical = "INSERT INTO radicals VALUES (?, ?, ?)"
        var radStmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertRadical, -1, &radStmt, nil)
        bindText(radStmt, 1, "\u{4E00}")
        bindText(radStmt, 2, "one")
        sqlite3_bind_int(radStmt, 3, 1)
        sqlite3_step(radStmt)
        sqlite3_finalize(radStmt)

        // Insert a kanji for the given level
        let insertKanji = "INSERT INTO kanji VALUES (?, ?, ?, ?, ?, ?, NULL)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertKanji, -1, &stmt, nil)
        bindText(stmt, 1, "\u{65E5}")
        bindText(stmt, 2, #"["ニチ"]"#)
        bindText(stmt, 3, #"["ひ"]"#)
        bindText(stmt, 4, #"["day","sun"]"#)
        bindText(stmt, 5, level.rawValue)
        sqlite3_bind_int(stmt, 6, 4)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        // Insert edge
        let insertEdge = "INSERT INTO kanji_radical_edges VALUES (?, ?)"
        var edgeStmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertEdge, -1, &edgeStmt, nil)
        bindText(edgeStmt, 1, "\u{4E00}")
        bindText(edgeStmt, 2, "\u{65E5}")
        sqlite3_step(edgeStmt)
        sqlite3_finalize(edgeStmt)

        return bundleURL
    }

    /// Creates an empty SQLite bundle (valid schema, no rows) for a level.
    private func createEmptyBundle(in directory: URL, for level: JLPTLevel) throws -> URL {
        let bundleURL = directory.appendingPathComponent("\(level.rawValue)-content.sqlite")

        var db: OpaquePointer?
        guard sqlite3_open(bundleURL.path, &db) == SQLITE_OK else {
            throw ContentLoadingTestError.cannotOpenDatabase
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

        return bundleURL
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(
            stmt, index, value, -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
    }

    // MARK: - loadLevel Tests

    @Test("loadLevel with valid SQLite file returns repository and updates loadedLevels")
    func loadLevelValid() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n5)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let repo = await service.loadLevel(.n5)

        #expect(repo != nil)
        #expect(service.loadedLevels.contains(.n5))
    }

    @Test("loadLevel with missing file returns nil and sets failed state")
    func loadLevelMissingFile() async {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let repo = await service.loadLevel(.n5)

        #expect(repo == nil)
        #expect(service.loadingState.isFailed)

        if case .failed(let error) = service.loadingState,
           let loadingError = error as? ContentLoadingError,
           case .bundleNotFound(let level) = loadingError {
            #expect(level == .n5)
        } else {
            Issue.record("Expected ContentLoadingError.bundleNotFound(.n5)")
        }
    }

    @Test("loadLevel with already-loaded level returns immediately without re-loading")
    func loadLevelAlreadyLoaded() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n5)

        let service = ContentLoadingService(bundleDirectoryURL: dir)

        let first = await service.loadLevel(.n5)
        #expect(first != nil)

        // Loading again should still return a repository (from cache path)
        let second = await service.loadLevel(.n5)
        #expect(second != nil)
        #expect(service.loadedLevels.count == 1)
    }

    @Test("loadLevel transitions state from idle to loading to loaded")
    func loadLevelStateTransitions() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n5)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        #expect(service.loadingState.isIdle)

        let repo = await service.loadLevel(.n5)

        #expect(repo != nil)
        #expect(service.loadingState.isLoaded)
        #expect(service.loadingState.value == .n5)
    }

    @Test("loadLevel with empty bundle returns nil and sets failed state")
    func loadLevelEmptyBundle() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createEmptyBundle(in: dir, for: .n5)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let repo = await service.loadLevel(.n5)

        #expect(repo == nil)
        #expect(service.loadingState.isFailed)
        #expect(!service.loadedLevels.contains(.n5))

        if case .failed(let error) = service.loadingState,
           let loadingError = error as? ContentLoadingError,
           case .emptyBundle(let level) = loadingError {
            #expect(level == .n5)
        } else {
            Issue.record("Expected ContentLoadingError.emptyBundle(.n5)")
        }
    }

    // MARK: - isLevelLoaded Tests

    @Test("isLevelLoaded returns false before loading")
    func isLevelLoadedBeforeLoad() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)

        #expect(!service.isLevelLoaded(.n5))
        #expect(!service.isLevelLoaded(.n4))
        #expect(!service.isLevelLoaded(.n1))
    }

    @Test("isLevelLoaded returns true after successful load")
    func isLevelLoadedAfterLoad() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n5)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        await service.loadLevel(.n5)

        #expect(service.isLevelLoaded(.n5))
        #expect(!service.isLevelLoaded(.n4))
    }

    // MARK: - availableLevels Tests

    @Test("availableLevels returns levels that have files on disk")
    func availableLevelsWithFiles() throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n5)
        try createTestBundle(in: dir, for: .n4)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let available = service.availableLevels()

        #expect(available.contains(.n5))
        #expect(available.contains(.n4))
        #expect(!available.contains(.n3))
        #expect(!available.contains(.n2))
        #expect(!available.contains(.n1))
    }

    @Test("availableLevels returns empty when no bundles exist")
    func availableLevelsEmpty() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let available = service.availableLevels()

        #expect(available.isEmpty)
    }

    // MARK: - nextLevelIfReady Tests

    @Test("nextLevelIfReady returns nil when mastery below 80%")
    func nextLevelBelowThreshold() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 70,
            totalKanjiCount: 100
        )

        #expect(next == nil)
    }

    @Test("nextLevelIfReady returns next level when mastery >= 80%")
    func nextLevelAboveThreshold() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 85,
            totalKanjiCount: 100
        )

        #expect(next == .n4)
    }

    @Test("nextLevelIfReady returns nil when totalKanjiCount is 0")
    func nextLevelZeroTotal() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 0,
            totalKanjiCount: 0
        )

        #expect(next == nil)
    }

    @Test("nextLevelIfReady returns nil when next level is already loaded")
    func nextLevelAlreadyLoaded() async throws {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }
        try createTestBundle(in: dir, for: .n4)

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        await service.loadLevel(.n4)

        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 100,
            totalKanjiCount: 100
        )

        #expect(next == nil)
    }

    @Test("nextLevelIfReady returns nil for N1 (no next level)")
    func nextLevelFromN1() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n1,
            masteredKanjiCount: 100,
            totalKanjiCount: 100
        )

        #expect(next == nil)
    }

    @Test("nextLevelIfReady: exactly 80% triggers unlock")
    func nextLevelExactThreshold() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 80,
            totalKanjiCount: 100
        )

        #expect(next == .n4)
    }

    @Test("nextLevelIfReady: 79% does NOT trigger unlock")
    func nextLevelJustBelowThreshold() {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: .n5,
            masteredKanjiCount: 79,
            totalKanjiCount: 100
        )

        #expect(next == nil)
    }

    @Test("nextLevelIfReady progresses through levels correctly", arguments: [
        (JLPTLevel.n5, JLPTLevel.n4),
        (JLPTLevel.n4, JLPTLevel.n3),
        (JLPTLevel.n3, JLPTLevel.n2),
        (JLPTLevel.n2, JLPTLevel.n1),
    ])
    func nextLevelProgression(current: JLPTLevel, expected: JLPTLevel) {
        let dir = makeTempBundleDirectory()
        defer { cleanUp(dir) }

        let service = ContentLoadingService(bundleDirectoryURL: dir)
        let next = service.nextLevelIfReady(
            currentLevel: current,
            masteredKanjiCount: 100,
            totalKanjiCount: 100
        )

        #expect(next == expected)
    }

    @Test("masteryThreshold constant is 0.80")
    func masteryThresholdValue() {
        #expect(ContentLoadingService.masteryThreshold == 0.80)
    }
}

// MARK: - Test Error

private enum ContentLoadingTestError: Error {
    case cannotOpenDatabase
}
