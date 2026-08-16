import Testing
import Foundation
import SQLite3
@testable import IkeruCore

/// Invariants of the **shipped** `n5-content.sqlite`, not of a synthetic
/// fixture.
///
/// `ContentRepositoryTests` in Core builds its own tiny database, which is the
/// right way to test the repository's SQL — but it means nothing ever looked at
/// the file that actually reaches a learner. That gap let two defects ride
/// along unnoticed until the 2026-08-16 vocabulary expansion tripped over
/// them: the bundle carried 今年 **twice** (206 rows for 205 distinct words),
/// and the French translations were keyed on `id` — ids that
/// `generate_content_bundles.py` assigns by enumeration, so any insertion
/// silently shifted every translation onto the wrong word.
///
/// This suite runs in the app target because that is where the bundle is a
/// resource: `Bundle.main` resolves it exactly as `HomeView`, `EtudeView` and
/// `ExerciseTransitionContainer` do at runtime.
///
/// The counts below are deliberately exact rather than `> 0`. A loose bound
/// would have passed on all of the above.
@Suite("Content bundle — vocabulary")
struct ContentBundleVocabularyTests {

    /// One row of `vocabulary`, read straight from the shipped file.
    private struct Row {
        let word: String
        let reading: String
        let meaning: String
        let meaningFR: String
        let listSource: String
    }

    private func shippedRows() throws -> [Row] {
        let url = try #require(
            Bundle.main.url(forResource: "n5-content", withExtension: "sqlite"),
            "n5-content.sqlite is not in the app bundle — nothing below can be checked"
        )

        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database = handle
        else {
            Issue.record("Could not open the shipped content bundle at \(url.path)")
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = """
            SELECT word, reading, meaning, COALESCE(meaning_fr, ''), COALESCE(list_source, '')
            FROM vocabulary ORDER BY id
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let query = statement
        else {
            Issue.record("Could not prepare the vocabulary query — has the schema changed?")
            return []
        }
        defer { sqlite3_finalize(query) }

        func text(_ column: Int32) -> String {
            sqlite3_column_text(query, column).map { String(cString: $0) } ?? ""
        }

        var rows: [Row] = []
        while sqlite3_step(query) == SQLITE_ROW {
            rows.append(
                Row(
                    word: text(0),
                    reading: text(1),
                    meaning: text(2),
                    meaningFR: text(3),
                    listSource: text(4)
                )
            )
        }
        return rows
    }

    @Test("Every word appears exactly once")
    func noDuplicateWords() throws {
        let rows = try shippedRows()
        let duplicates = Dictionary(grouping: rows, by: \.word)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        #expect(
            duplicates.isEmpty,
            "Duplicated in the shipped bundle: \(duplicates.joined(separator: ", ")). A duplicate word means one is unreachable through `word`-keyed lookups, and the learner can be shown the same card twice."
        )
    }

    @Test("No row ships without a meaning, in either language")
    func noEmptyGlosses() throws {
        let rows = try shippedRows()
        let missingEN = rows.filter { $0.meaning.trimmingCharacters(in: .whitespaces).isEmpty }
        let missingFR = rows.filter { $0.meaningFR.trimmingCharacters(in: .whitespaces).isEmpty }

        #expect(missingEN.isEmpty, "No English gloss: \(missingEN.map(\.word).prefix(10))")
        #expect(missingFR.isEmpty, "No French gloss: \(missingFR.map(\.word).prefix(10))")
    }

    @Test("No row ships without a reading")
    func noEmptyReadings() throws {
        let rows = try shippedRows()
        let missing = rows.filter { $0.reading.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(missing.isEmpty, "No reading: \(missing.map(\.word).prefix(10))")
    }

    /// Guards the attribution shown in `AttributionView`.
    ///
    /// The app tells learners that the meanings are Ikeru's and the N5 word
    /// list is Tanos's. `list_source` is what makes that checkable instead of
    /// merely asserted — so if it ever goes NULL or picks up a third value,
    /// the on-screen claim has quietly stopped being verifiable.
    @Test("Provenance of the word selection is recorded on every row")
    func listSourceIsRecorded() throws {
        let rows = try shippedRows()
        let counts = Dictionary(grouping: rows, by: \.listSource).mapValues(\.count)

        #expect(counts["ikeru"] == 205, "Ikeru's own word list changed size: \(counts)")
        #expect(counts["tanos"] == 488, "The imported N5 list changed size: \(counts)")
        #expect(
            Set(counts.keys) == ["ikeru", "tanos"],
            "Unexpected list_source values: \(Set(counts.keys)). Every value needs a matching credit in AttributionView."
        )
        #expect(rows.count == 693)
    }
}
