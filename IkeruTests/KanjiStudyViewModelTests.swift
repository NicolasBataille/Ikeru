import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

@Suite("KanjiStudyViewModel")
@MainActor
struct KanjiStudyViewModelTests {

    // MARK: - Helpers

    private static func makeSampleKanji(
        character: String = "\u{65E5}",
        radicals: [String] = ["\u{4E00}", "\u{53E3}"],
        onReadings: [String] = ["\u{30CB}\u{30C1}"],
        kunReadings: [String] = ["\u{3072}", "\u{3073}"],
        meanings: [String] = ["day", "sun"],
        jlptLevel: JLPTLevel = .n5,
        strokeCount: Int = 4,
        strokeOrderSVGRef: String? = "<path d=\"M 10,50 L 90,50\"/>"
    ) -> Kanji {
        Kanji(
            character: character,
            radicals: radicals,
            onReadings: onReadings,
            kunReadings: kunReadings,
            meanings: meanings,
            jlptLevel: jlptLevel,
            strokeCount: strokeCount,
            strokeOrderSVGRef: strokeOrderSVGRef
        )
    }

    /// Creates a temporary SQLite database with test data.
    private static func makeTestDatabase(
        kanjiCharacter: String = "\u{65E5}",
        radicalCharacters: [(String, String, Int)] = [
            ("\u{4E00}", "one", 1),
            ("\u{53E3}", "mouth", 3),
        ],
        vocabularyItems: [(Int, String, String, String)] = [
            (1, "\u{65E5}\u{672C}", "\u{306B}\u{307B}\u{3093}", "Japan"),
            (2, "\u{6BCE}\u{65E5}", "\u{307E}\u{3044}\u{306B}\u{3061}", "every day"),
        ]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dbURL = tempDir.appendingPathComponent("test_kanji_\(UUID().uuidString).sqlite")

        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw TestDatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        let createTables = """
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

        guard sqlite3_exec(db, createTables, nil, nil, nil) == SQLITE_OK else {
            throw TestDatabaseError.createFailed
        }

        // Insert radicals and edges
        for (char, meaning, strokes) in radicalCharacters {
            let insertRadical = "INSERT INTO radicals VALUES ('\(char)', '\(meaning)', \(strokes))"
            sqlite3_exec(db, insertRadical, nil, nil, nil)

            let insertEdge = "INSERT INTO kanji_radical_edges VALUES ('\(char)', '\(kanjiCharacter)')"
            sqlite3_exec(db, insertEdge, nil, nil, nil)
        }

        // Insert vocabulary
        for (id, word, reading, meaning) in vocabularyItems {
            let insertVocab = """
                INSERT INTO vocabulary VALUES (\(id), '\(word)', '\(reading)', '\(meaning)', '\(kanjiCharacter)', 'N5')
                """
            sqlite3_exec(db, insertVocab, nil, nil, nil)
        }

        return dbURL
    }

    // MARK: - Initial State

    @Test("Initial state is idle with empty radicals and vocabulary")
    func initialState() {
        let kanji = Self.makeSampleKanji()
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        #expect(viewModel.kanji.character == "\u{65E5}")
        #expect(viewModel.radicals.isEmpty)
        #expect(viewModel.vocabulary.isEmpty)
        #expect(viewModel.loadingState.isIdle)
    }

    // MARK: - Loading Success

    @Test("loadContent populates radicals and vocabulary from ContentRepository")
    func loadContentPopulatesData() async throws {
        let dbURL = try Self.makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let repo = ContentRepository(bundleURL: dbURL)
        let kanji = Self.makeSampleKanji()
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        await viewModel.loadContent()

        #expect(viewModel.loadingState.isLoaded)
        #expect(viewModel.radicals.count == 2)
        #expect(viewModel.vocabulary.count == 2)
        #expect(viewModel.radicals.contains { $0.character == "\u{4E00}" })
        #expect(viewModel.radicals.contains { $0.character == "\u{53E3}" })
        #expect(viewModel.vocabulary.contains { $0.word == "\u{65E5}\u{672C}" })
    }

    // MARK: - Empty Radicals

    @Test("loadContent handles kanji with no radicals")
    func loadContentNoRadicals() async throws {
        let dbURL = try Self.makeTestDatabase(radicalCharacters: [])
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let repo = ContentRepository(bundleURL: dbURL)
        let kanji = Self.makeSampleKanji()
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        await viewModel.loadContent()

        #expect(viewModel.loadingState.isLoaded)
        #expect(viewModel.radicals.isEmpty)
        #expect(viewModel.vocabulary.count == 2)
    }

    // MARK: - Empty Vocabulary

    @Test("loadContent handles kanji with no vocabulary")
    func loadContentNoVocabulary() async throws {
        let dbURL = try Self.makeTestDatabase(vocabularyItems: [])
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let repo = ContentRepository(bundleURL: dbURL)
        let kanji = Self.makeSampleKanji()
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        await viewModel.loadContent()

        #expect(viewModel.loadingState.isLoaded)
        #expect(viewModel.radicals.count == 2)
        #expect(viewModel.vocabulary.isEmpty)
    }

    // MARK: - Loading with invalid database

    @Test("loadContent handles ContentRepository errors gracefully")
    func loadContentHandlesErrors() async {
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent.sqlite"))
        let kanji = Self.makeSampleKanji()
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        await viewModel.loadContent()

        // ContentRepository returns empty arrays on failure, so state is still loaded
        #expect(viewModel.loadingState.isLoaded)
        #expect(viewModel.radicals.isEmpty)
        #expect(viewModel.vocabulary.isEmpty)
    }

    // MARK: - Kanji properties preserved

    @Test("ViewModel preserves kanji properties")
    func kanjiPropertiesPreserved() {
        let kanji = Self.makeSampleKanji(
            onReadings: ["\u{30CB}\u{30C1}", "\u{30B8}\u{30C4}"],
            kunReadings: ["\u{3072}", "\u{3073}"],
            meanings: ["day", "sun", "Japan"]
        )
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        #expect(viewModel.kanji.onReadings.count == 2)
        #expect(viewModel.kanji.kunReadings.count == 2)
        #expect(viewModel.kanji.meanings.count == 3)
        #expect(viewModel.kanji.strokeCount == 4)
    }
}

// MARK: - Test Helpers

import SQLite3

private enum TestDatabaseError: Error {
    case openFailed
    case createFailed
}
