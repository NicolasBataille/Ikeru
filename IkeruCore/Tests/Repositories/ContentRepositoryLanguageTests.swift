import Testing
import Foundation
import SQLite3
@testable import IkeruCore

// MARK: - ContentRepository Language Tests

/// Covers the FR/EN selection of learner-facing glosses and — the part that
/// actually protects the screen — the per-row fallback to English when a
/// French translation is missing, blank, or an empty JSON array.
@Suite("ContentRepository language")
struct ContentRepositoryLanguageTests {

    // MARK: - Locale Mapping

    @Test("ContentLanguage maps French locales to .french, everything else to .english")
    func localeMapping() {
        #expect(ContentLanguage(locale: Locale(identifier: "fr")) == .french)
        #expect(ContentLanguage(locale: Locale(identifier: "fr-FR")) == .french)
        #expect(ContentLanguage(locale: Locale(identifier: "fr-CA")) == .french)
        #expect(ContentLanguage(locale: Locale(identifier: "en")) == .english)
        #expect(ContentLanguage(locale: Locale(identifier: "en-US")) == .english)
        #expect(ContentLanguage(locale: Locale(identifier: "ja-JP")) == .english)
    }

    // MARK: - French Selection

    @Test("French serves the translated vocabulary meaning")
    func frenchVocabularyMeaning() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)
        let vocabulary = await repo.vocabularyByLevel(.n5)

        #expect(vocabulary.first { $0.id == 1 }?.meaning == "le Japon")
    }

    @Test("French serves translated kanji meanings and grammar text")
    func frenchKanjiAndGrammar() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)

        let kanji = await repo.kanjiByLevel(.n5)
        #expect(kanji.first { $0.character == "\u{65E5}" }?.meanings == ["jour", "soleil"])

        let grammar = await repo.grammarPointsByLevel(.n5)
        let topicMarker = grammar.first { $0.id == 1 }
        #expect(topicMarker?.title == "\u{306F} (particule de th\u{00E8}me)")
        #expect(topicMarker?.explanation == "Marque le th\u{00E8}me de la phrase.")
        #expect(topicMarker?.examples == [
            "\u{79C1}\u{306F}\u{5B66}\u{751F}\u{3067}\u{3059}\u{3002} — Je suis \u{00E9}tudiant(e)."
        ])
    }

    @Test("Japanese in French rows is served verbatim, never translated away")
    func japaneseUntouched() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)
        let vocabulary = await repo.vocabularyByLevel(.n5)

        let japan = vocabulary.first { $0.id == 1 }
        #expect(japan?.word == "\u{65E5}\u{672C}")
        #expect(japan?.reading == "\u{306B}\u{307B}\u{3093}")
    }

    // MARK: - Fallback

    @Test("A NULL French meaning falls back to English rather than serving nothing")
    func fallbackOnNull() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)
        let vocabulary = await repo.vocabularyByLevel(.n5)

        #expect(vocabulary.first { $0.id == 2 }?.meaning == "today")
    }

    @Test("A blank French meaning falls back to English")
    func fallbackOnEmptyString() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)
        let vocabulary = await repo.vocabularyByLevel(.n5)

        #expect(vocabulary.first { $0.id == 3 }?.meaning == "student")
    }

    @Test("An empty French JSON array falls back to English meanings")
    func fallbackOnEmptyJSONArray() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)

        let kanji = await repo.kanjiByLevel(.n5)
        #expect(kanji.first { $0.character == "\u{6708}" }?.meanings == ["month", "moon"])

        // grammar_points id 2 has '[]' examples_fr and NULL title_fr/explanation_fr.
        let grammar = await repo.grammarPointsByLevel(.n5)
        let politeForm = grammar.first { $0.id == 2 }
        #expect(politeForm?.title == "\u{3067}\u{3059}/\u{307E}\u{3059} (Polite Form)")
        #expect(politeForm?.explanation == "Polite sentence endings.")
        #expect(politeForm?.examples == ["\u{5B66}\u{751F}\u{3067}\u{3059}\u{3002}"])
    }

    @Test("The fallback also applies to vocabulary fetched by kanji")
    func fallbackViaVocabularyForKanji() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .french)
        let vocabulary = await repo.vocabularyForKanji("\u{65E5}")

        #expect(vocabulary.first { $0.id == 1 }?.meaning == "le Japon")
        #expect(vocabulary.first { $0.id == 2 }?.meaning == "today")
    }

    // MARK: - English Selection

    @Test("English ignores the French columns even when they are populated")
    func englishIgnoresFrenchColumns() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase(), language: .english)

        let vocabulary = await repo.vocabularyByLevel(.n5)
        #expect(vocabulary.first { $0.id == 1 }?.meaning == "Japan")

        let kanji = await repo.kanjiByLevel(.n5)
        #expect(kanji.first { $0.character == "\u{65E5}" }?.meanings == ["day", "sun"])

        let grammar = await repo.grammarPointsByLevel(.n5)
        #expect(grammar.first { $0.id == 1 }?.title == "\u{306F} (Topic Marker)")
    }

    @Test("The default language is English — an unwired caller gets complete content")
    func defaultLanguageIsEnglish() async throws {
        let repo = ContentRepository(bundleURL: try makeLocalizedDatabase())
        let vocabulary = await repo.vocabularyByLevel(.n5)

        #expect(vocabulary.first { $0.id == 1 }?.meaning == "Japan")
    }

    // MARK: - Legacy Bundles

    @Test("A bundle with no French columns still serves English content in French mode")
    func legacyBundleWithoutFrenchColumns() async throws {
        let repo = ContentRepository(bundleURL: try makeLegacyDatabase(), language: .french)

        let vocabulary = await repo.vocabularyByLevel(.n5)
        #expect(vocabulary.first { $0.id == 1 }?.meaning == "Japan")

        let kanji = await repo.kanjiByLevel(.n5)
        #expect(kanji.first { $0.character == "\u{65E5}" }?.meanings == ["day", "sun"])

        let grammar = await repo.grammarPointsByLevel(.n5)
        #expect(grammar.first { $0.id == 1 }?.title == "\u{306F} (Topic Marker)")
        #expect(grammar.first { $0.id == 1 }?.examples == [
            "\u{79C1}\u{306F}\u{5B66}\u{751F}\u{3067}\u{3059}\u{3002}"
        ])
    }
}

// MARK: - Fixtures

/// Schema and rows shared by both fixtures. The localized fixture appends the
/// `_fr` columns; the legacy one deliberately does not.
private let baseSchema = """
    CREATE TABLE kanji (
        character TEXT PRIMARY KEY,
        on_readings TEXT,
        kun_readings TEXT,
        meanings TEXT,
        jlpt_level TEXT,
        stroke_count INTEGER,
        stroke_order_svg TEXT
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
    INSERT INTO kanji VALUES
        ('\u{65E5}', '["ニチ"]', '["ひ"]', '["day","sun"]', 'n5', 4, NULL),
        ('\u{6708}', '["ゲツ"]', '["つき"]', '["month","moon"]', 'n5', 4, NULL);
    INSERT INTO vocabulary VALUES
        (1, '\u{65E5}\u{672C}', '\u{306B}\u{307B}\u{3093}', 'Japan', '\u{65E5}', 'n5'),
        (2, '\u{4ECA}\u{65E5}', '\u{304D}\u{3087}\u{3046}', 'today', '\u{65E5}', 'n5'),
        (3, '\u{5B66}\u{751F}', '\u{304C}\u{304F}\u{305B}\u{3044}', 'student', '\u{5B66}', 'n5');
    INSERT INTO grammar_points VALUES
        (1, 'n5', '\u{306F} (Topic Marker)', 'Marks the topic of the sentence.',
            '["私は学生です。"]'),
        (2, 'n5', '\u{3067}\u{3059}/\u{307E}\u{3059} (Polite Form)', 'Polite sentence endings.',
            '["学生です。"]');
    """

/// Fixture carrying the French columns, with one fully translated row per
/// table and deliberately degenerate French values (NULL, `''`, `'[]'`) on the
/// others — those are the rows the fallback has to rescue.
private func makeLocalizedDatabase() throws -> URL {
    try makeDatabase(named: "content-fr", sql: baseSchema + """

        ALTER TABLE vocabulary ADD COLUMN meaning_fr TEXT;
        ALTER TABLE sentences ADD COLUMN french TEXT;
        ALTER TABLE kanji ADD COLUMN meanings_fr TEXT;
        ALTER TABLE grammar_points ADD COLUMN title_fr TEXT;
        ALTER TABLE grammar_points ADD COLUMN explanation_fr TEXT;
        ALTER TABLE grammar_points ADD COLUMN examples_fr TEXT;

        UPDATE vocabulary SET meaning_fr = 'le Japon' WHERE id = 1;
        UPDATE vocabulary SET meaning_fr = NULL       WHERE id = 2;
        UPDATE vocabulary SET meaning_fr = ''         WHERE id = 3;

        UPDATE kanji SET meanings_fr = '["jour","soleil"]' WHERE character = '\u{65E5}';
        UPDATE kanji SET meanings_fr = '[]'                WHERE character = '\u{6708}';

        UPDATE grammar_points SET
            title_fr = '\u{306F} (particule de th\u{00E8}me)',
            explanation_fr = 'Marque le th\u{00E8}me de la phrase.',
            examples_fr = '["私は学生です。 — Je suis étudiant(e)."]'
            WHERE id = 1;
        UPDATE grammar_points SET
            title_fr = NULL, explanation_fr = NULL, examples_fr = '[]'
            WHERE id = 2;
        """)
}

/// Fixture predating the French columns entirely — the shipped bundle before
/// `scripts/apply-content-fr.py` ever ran against it.
private func makeLegacyDatabase() throws -> URL {
    try makeDatabase(named: "content-legacy", sql: baseSchema)
}

private func makeDatabase(named name: String, sql: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ikeru-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        throw ContentLanguageFixtureError.couldNotOpen(url.path)
    }
    defer { sqlite3_close(db) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let detail = errorMessage.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(errorMessage)
        throw ContentLanguageFixtureError.couldNotBuild(detail)
    }

    return url
}

private enum ContentLanguageFixtureError: Error {
    case couldNotOpen(String)
    case couldNotBuild(String)
}
