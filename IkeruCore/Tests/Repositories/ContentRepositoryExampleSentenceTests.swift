import Testing
import Foundation
import SQLite3
@testable import IkeruCore

// MARK: - ContentRepository example-sentence tests

/// Covers `exampleSentences(for:limit:)` — the reader that finally consumes
/// `sentences.french`.
///
/// The failure being fixed is not a crash but an omission: the column was
/// populated and **nothing read it**, which no existing test could notice
/// because "returns nothing" was the correct answer for every caller. So the
/// first test below is deliberately blunt — it asserts a real translation
/// comes back — and the rest pin the decisions that are easy to "simplify"
/// away later.
@Suite("ContentRepository example sentences")
struct ContentRepositoryExampleSentenceTests {

    @Test("French serves the sentence AND its French translation")
    func frenchServesTranslation() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .french)

        let examples = await repo.exampleSentences(for: "日本", limit: 5)

        #expect(examples.count == 2)
        #expect(examples.first?.japanese == "日本は島国です。")
        #expect(examples.first?.translation == "Le Japon est un pays insulaire.")
    }

    /// The measurement that shaped this API: the Tatoeba half of the shipped
    /// corpus is French-only (536 of 632 rows carry no English, because the
    /// corpus was selected from Tatoeba's jpn↔fra links). Vocabulary meanings
    /// fall back French → English; doing the same here would render French
    /// sentences under an English UI.
    ///
    /// The contract is therefore: drop the row. An English learner sees fewer
    /// examples, never French ones.
    @Test("English drops French-only rows instead of falling back to French")
    func englishNeverFallsBackToFrench() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .english)

        let examples = await repo.exampleSentences(for: "日本", limit: 5)

        #expect(examples.count == 1, "the French-only row must not surface in English")
        #expect(examples.first?.translation == "Japan is an island country.")
        #expect(examples.allSatisfy { !$0.translation.contains("insulaire") })
    }

    /// `limit` counts *usable* examples. Filtering after the fact would let a
    /// word with two translated rows behind three untranslated ones return
    /// nothing at `limit: 3` — an empty section on a word that has examples.
    @Test("limit counts usable examples, not candidate rows")
    func limitCountsUsableExamples() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .english)

        let examples = await repo.exampleSentences(for: "学生", limit: 2)

        #expect(examples.count == 2)
        #expect(examples.allSatisfy { !$0.translation.isEmpty })
    }

    @Test("blank and '[]' translations count as missing, like everywhere else")
    func degenerateTranslationsAreMissing() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .french)

        let examples = await repo.exampleSentences(for: "今日", limit: 5)

        #expect(examples.isEmpty)
    }

    @Test("a word with no bundled sentence yields nothing, not an error")
    func unknownWordYieldsNothing() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .french)

        #expect(await repo.exampleSentences(for: "この単語はない", limit: 5).isEmpty)
    }

    @Test("limit of zero yields nothing rather than an unbounded query")
    func zeroLimitYieldsNothing() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .french)

        #expect(await repo.exampleSentences(for: "日本", limit: 0).isEmpty)
    }

    /// A bundle predating the French column must not fail to prepare and
    /// return nothing by accident — the schema is probed first, same as
    /// `localizedColumn` does.
    @Test("a bundle without the French column returns nothing in French, without crashing")
    func legacyBundleInFrench() async throws {
        let repo = ContentRepository(bundleURL: try makeLegacySentenceDatabase(), language: .french)

        #expect(await repo.exampleSentences(for: "日本", limit: 5).isEmpty)
    }

    @Test("ordering is stable across calls")
    func orderingIsStable() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .english)

        let first = await repo.exampleSentences(for: "学生", limit: 3)
        let second = await repo.exampleSentences(for: "学生", limit: 3)

        #expect(first == second)
        #expect(!first.isEmpty)
    }
}

// MARK: - Fixtures

private let sentenceSchema = """
    CREATE TABLE sentences (
        id INTEGER PRIMARY KEY,
        japanese TEXT,
        english TEXT,
        vocabulary_word TEXT
    );
    INSERT INTO sentences VALUES
        (1, '日本は島国です。', 'Japan is an island country.', '日本'),
        (2, 'わたしは日本に住んでいます。', NULL, '日本'),
        (3, '今日は暑いです。', '', '今日'),
        (4, 'きょうは雨です。', '[]', '今日'),
        (5, 'わたしは学生です。', 'I am a student.', '学生'),
        (6, '彼は学生ではない。', 'He is not a student.', '学生'),
        (7, '学生は本を読む。', 'The student reads a book.', '学生');
    """

/// Carries the French column, with the shapes that matter: one row translated
/// in both languages, one **French-only** (the Tatoeba shape), and degenerate
/// values (`NULL`, `''`, `'[]'`) that must read as missing.
private func makeSentenceDatabase() throws -> URL {
    try makeSentenceFixture(named: "sentences-fr", sql: sentenceSchema + """

        ALTER TABLE sentences ADD COLUMN french TEXT;

        UPDATE sentences SET french = 'Le Japon est un pays insulaire.' WHERE id = 1;
        UPDATE sentences SET french = 'J''habite au Japon.'             WHERE id = 2;
        UPDATE sentences SET french = NULL                              WHERE id = 3;
        UPDATE sentences SET french = '[]'                              WHERE id = 4;
        UPDATE sentences SET french = 'Je suis étudiant.'               WHERE id = 5;
        UPDATE sentences SET french = ''                                WHERE id = 6;
        UPDATE sentences SET french = 'L''étudiant lit un livre.'       WHERE id = 7;
        """)
}

/// Predates the French column entirely.
private func makeLegacySentenceDatabase() throws -> URL {
    try makeSentenceFixture(named: "sentences-legacy", sql: sentenceSchema)
}

private func makeSentenceFixture(named name: String, sql: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ikeru-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        throw SentenceFixtureError.couldNotOpen(url.path)
    }
    defer { sqlite3_close(db) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let detail = errorMessage.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(errorMessage)
        throw SentenceFixtureError.couldNotBuild(detail)
    }

    return url
}

private enum SentenceFixtureError: Error {
    case couldNotOpen(String)
    case couldNotBuild(String)
}
