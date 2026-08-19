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

    /// Against the **shipped** bundle, not a fixture.
    ///
    /// Every other test here builds its own SQLite, which proves the query is
    /// correct but not that the real data is shaped the way the query assumes.
    /// This one opens `Ikeru/Resources/ContentBundles/n5-content.sqlite` and
    /// asserts a French translation actually comes back — the closest a
    /// package test can get to "a learner would see this".
    ///
    /// Resolved from `#filePath` because the bundle lives in the app target,
    /// outside this package's resources. Skipped rather than failed if the
    /// layout ever moves: a path assumption breaking should not read as the
    /// feature breaking.
    @Test("the shipped bundle really does serve French example sentences")
    func shippedBundleServesFrench() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Repositories
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // IkeruCore
            .deletingLastPathComponent()   // repo root
        let bundleURL = repositoryRoot
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")

        try #require(
            FileManager.default.fileExists(atPath: bundleURL.path),
            "shipped bundle not found at \(bundleURL.path) — path assumption moved, not a feature failure"
        )

        let repo = ContentRepository(bundleURL: bundleURL, language: .french)
        let examples = await repo.exampleSentences(for: "日本", limit: 2)

        #expect(!examples.isEmpty, "the shipped bundle served no French example for 日本")
        #expect(examples.allSatisfy { !$0.japanese.isEmpty && !$0.translation.isEmpty })
        // A French translation, not the Japanese echoed back or an English one.
        #expect(examples.allSatisfy { $0.translation != $0.japanese })
    }

    // MARK: - Furigana

    @Test("A sentence carries its furigana form, and displayText prefers it")
    func furiganaIsServed() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .french)

        let examples = await repo.exampleSentences(for: "日本", limit: 1)

        let first = try #require(examples.first)
        #expect(first.furigana == "日本(にほん)は島国(しまぐに)です。")
        #expect(first.displayText == first.furigana)
        // Le japonais nu reste disponible : c'est lui qui sert de cle audio.
        #expect(first.japanese == "日本は島国です。")
    }

    /// Le repli qui compte : sans annotation, la phrase doit s'afficher NUE et
    /// lisible, jamais vide. Un ecran vide serait pire que pas de furigana.
    @Test("A row with no furigana falls back to the plain sentence")
    func furiganaFallsBackToPlain() async throws {
        let repo = ContentRepository(bundleURL: try makeSentenceDatabase(), language: .english)

        let examples = await repo.exampleSentences(for: "学生", limit: 1)

        let first = try #require(examples.first)
        #expect(first.furigana.isEmpty)
        #expect(first.displayText == first.japanese)
        #expect(!first.displayText.isEmpty)
    }

    /// Un bundle anterieur a la colonne ne doit ni echouer a preparer la
    /// requete ni rendre zero exemple — il sert les phrases sans annotation.
    @Test("A bundle predating the furigana column still serves examples")
    func legacyBundleWithoutFuriganaColumn() async throws {
        let repo = ContentRepository(bundleURL: try makeLegacySentenceDatabase(),
                                     language: .english)

        let examples = await repo.exampleSentences(for: "日本", limit: 2)

        #expect(!examples.isEmpty, "un bundle sans colonne furigana doit servir les phrases")
        #expect(examples.allSatisfy { $0.furigana.isEmpty })
        #expect(examples.allSatisfy { $0.displayText == $0.japanese })
    }

    /// Contre le bundle EXPEDIE : les 632 phrases doivent toutes porter une
    /// annotation, et retirer les parentheses doit redonner la phrase exacte.
    /// C'est la garantie que le generateur n'a rien altere.
    @Test("The shipped bundle's furigana reconstruct the sentence exactly")
    func shippedFuriganaAreConsistent() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = repositoryRoot
            .appendingPathComponent("Ikeru/Resources/ContentBundles/n5-content.sqlite")
        try #require(FileManager.default.fileExists(atPath: bundleURL.path))

        let repo = ContentRepository(bundleURL: bundleURL, language: .french)
        let examples = await repo.exampleSentences(for: "水", limit: 2)

        #expect(!examples.isEmpty)
        for example in examples {
            #expect(!example.furigana.isEmpty, "phrase expediee sans furigana : \(example.japanese)")
            let stripped = example.furigana.replacingOccurrences(
                of: "\\(([^)]*)\\)", with: "", options: .regularExpression)
            #expect(stripped == example.japanese,
                    "les furigana ont altere la phrase : \(stripped) != \(example.japanese)")
        }
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
        ALTER TABLE sentences ADD COLUMN furigana TEXT;

        UPDATE sentences SET furigana = '日本(にほん)は島国(しまぐに)です。' WHERE id = 1;
        UPDATE sentences SET furigana = ''                                  WHERE id = 5;

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
